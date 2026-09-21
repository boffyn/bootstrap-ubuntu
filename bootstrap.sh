#!/bin/bash
#
# boffyn bootstrap for Ubuntu servers
#
# **Do not run directly** - run using `boff bootstrap`
#
# Sets up and runs ansible locally to configure the host
set -euo pipefail

# Trace every command so it's visible in boffyn output
export PS4='+ [${BASH_SOURCE##*/}:${LINENO}] '
set -x

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: bootstrap must run as root. (boff runs it with sudo)" >&2
    exit 1
fi
. /etc/os-release
if [ "${ID:-}" != "ubuntu" ]; then
    echo "ERROR: this bootstrap only supports Ubuntu (detected: ${ID:-unknown})" >&2
    exit 1
fi

pinned_version() {
    local pkg="$1" version
    version="$(sed -nE "s/^${pkg}==([^[:space:]#]+).*/\1/p" "${HERE}/requirements.txt")"
    [ -n "${version}" ] || { echo "ERROR: no pinned version for ${pkg} in requirements.txt" >&2; exit 1; }
    echo "${version}"
}

UV_VERSION="$(pinned_version uv)"
ANSIBLE_VERSION="$(pinned_version ansible-core)"

# Ensure core dependencies
apt-get update -q
apt-get install -y -q ca-certificates curl

if ! command -v uv >/dev/null 2>&1 || [ "$(uv --version | awk '{print $2}')" != "${UV_VERSION}" ]; then
    curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" \
        | env UV_INSTALL_DIR=/usr/local/bin INSTALLER_NO_MODIFY_PATH=1 sh
fi

# Install ansible
export UV_TOOL_BIN_DIR=/usr/local/bin
uv tool install --python 3.12 "ansible-core==${ANSIBLE_VERSION}"

# Run playbook
export ANSIBLE_LOCALHOST_WARNING=False
export ANSIBLE_RETRY_FILES_ENABLED=False
/usr/local/bin/ansible-playbook \
    -i "localhost," \
    -c local \
    "${HERE}/playbook.yml"
