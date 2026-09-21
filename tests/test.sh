#!/bin/bash
# Runs bootstrap.sh in an Ubuntu docker container matching what a fresh VPS looks like
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HERE}/.." && pwd)"
IMAGE=bootstrap-ubuntu-test-base
CONTAINER=boffyn-bootstrap-test
MOUNT_PATH=/opt/bootstrap-ubuntu
SSH_PORT=2244
KEY_DIR="$(mktemp -d)"
RUN2_LOG="$(mktemp)"

cleanup() {
    docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
    rm -rf "${KEY_DIR}"
    rm -f "${RUN2_LOG}"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }
run() { docker exec "${CONTAINER}" bash -c "$1"; }

echo "--- Generating SSH key pair ---"
ssh-keygen -t ed25519 -f "${KEY_DIR}/id_ed25519" -N "" -q
PUBKEY="$(cat "${KEY_DIR}/id_ed25519.pub")"

echo "--- Building test image ---"
# The official ubuntu image uses init, so swap to systemd
docker build -q -t "${IMAGE}" -f "${HERE}/Dockerfile" "${HERE}" >/dev/null

echo "--- Starting test container ---"
docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
# Start docker with workarounds for systemd (`--privileged --cgroups=host`)
docker run -d --name "${CONTAINER}" --privileged --cgroupns=host \
    -p "127.0.0.1:${SSH_PORT}:22" \
    -v "${REPO_ROOT}:${MOUNT_PATH}:ro" \
    "${IMAGE}" >/dev/null

echo "--- Waiting for systemd ---"
ready=0
for _ in $(seq 1 30); do
    if docker exec "${CONTAINER}" test -S /run/systemd/private 2>/dev/null \
        && [ "$(docker exec "${CONTAINER}" systemctl is-active ssh.socket 2>/dev/null)" = "active" ]; then
        ready=1
        break
    fi
    sleep 1
done
[ "${ready}" = 1 ] || fail "systemd never reached a ready state"

# Sometimes we get a bad request, retry
echo "--- Reconfiguring apt ---"
run "printf 'Acquire::Retries \"3\";\nAcquire::http::Pipeline-Depth \"0\";\n' > /etc/apt/apt.conf.d/80-retries"

echo "--- Running bootstrap.sh ---"
run "BOFFYN_ADMIN_USER=admin BOFFYN_ADMIN_KEY='${PUBKEY}' BOFFYN_DEPLOY_USER=deployer BOFFYN_UNSAFE_WRITES=yes bash ${MOUNT_PATH}/bootstrap.sh" \
    || fail "bootstrap.sh failed on first run"

echo
echo "=== Checks ==="

echo "--- admin and deploy users exist ---"
run "id admin" >/dev/null || fail "admin user was not created"
run "id deployer" >/dev/null || fail "deployer user was not created"
pass "admin and deployer users exist"

echo "--- admin has passwordless sudo ---"
run "grep -q 'admin ALL=(ALL) NOPASSWD: ALL' /etc/sudoers.d/boffyn_users" \
    || fail "admin does not have passwordless sudo configured"
pass "admin has passwordless sudo"

echo "--- SSH is actually reachable with the installed key ---"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 \
    -i "${KEY_DIR}/id_ed25519" -p "${SSH_PORT}" admin@127.0.0.1 \
    "sudo whoami" | grep -q root \
    || fail "could not SSH in as admin and sudo to root"
pass "SSH connection works and admin can sudo"

echo "--- SSH hardening took effect ---"
run "sshd -T | grep -q '^passwordauthentication no\$'" \
    || fail "PasswordAuthentication was not disabled"
run "sshd -T | grep -q '^permitrootlogin no\$'" \
    || fail "PermitRootLogin was not disabled"
pass "SSH hardening (password auth / root login) took effect"

echo "--- Default runtime (podman) installed ---"
run "command -v podman >/dev/null && podman --version >/dev/null" \
    || fail "podman was not installed"
pass "podman installed"

echo "--- Unprivileged ports sysctl took effect ---"
run "sysctl -n net.ipv4.ip_unprivileged_port_start" | grep -qx 80 \
    || fail "net.ipv4.ip_unprivileged_port_start was not set to 80"
pass "unprivileged-ports sysctl applied"

echo "--- Re-running bootstrap.sh (idempotency) ---"
run "BOFFYN_ADMIN_USER=admin BOFFYN_ADMIN_KEY='${PUBKEY}' BOFFYN_DEPLOY_USER=deployer BOFFYN_UNSAFE_WRITES=yes bash ${MOUNT_PATH}/bootstrap.sh" \
    > "${RUN2_LOG}" 2>&1 || { cat "${RUN2_LOG}" >&2; fail "bootstrap.sh failed on re-run"; }
pass "bootstrap.sh re-ran cleanly"

echo "--- Re-run made no changes (real idempotency, not just 'didn't error') ---"
if ! grep -qE '^localhost\s*:.*changed=0\b' "${RUN2_LOG}"; then
    grep -E '^localhost\s*:' "${RUN2_LOG}" >&2 || cat "${RUN2_LOG}" >&2
    fail "second run reported changed tasks - not actually idempotent"
fi
pass "second run reported changed=0"

echo
echo "All checks passed."
