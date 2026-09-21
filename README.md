# Boffyn bootstrap-ubuntu

The standard boffyn server bootstrap for Ubuntu hosts.

Run this against a clean remote host using `boff bootstrap`.

This is designed to be safe to re-run if you make changes to your configuration or want
to apply the latest version of this repository.


## Usage

In your host manifest, specify this as your bootstrap repo and configure it through
environment variables:

```yaml
host:
  name: myserver.example.com
  bootstrap:
    repo: "gh:boffyn/bootstrap-ubuntu.git"
    hash: "<commit sha>"  # optional but strongly recommended - see Security below
    env:
      ADMIN_USER: admin
      ADMIN_KEY: "ssh-ed25519 AAAA... you@example.com"
      DEPLOY_USER: deployer
      DEPLOY_KEY: "ssh-ed25519 AAAA... you@example.com"
      TZ: Europe/London
```

You can then bootstrap your host with:

```sh
boff bootstrap -m myserver.yml
```


## Configuration (BOFFYN_* env vars)

| Manifest env key | Default     | Purpose                              |
|------------------|-------------|---------------------------------------|
| `ADMIN_USER`     | (none)      | Admin account with passwordless sudo |
| `ADMIN_KEY`      | (none)      | SSH public key(s) for the admin      |
| `DEPLOY_USER`    | `deployer`  | Deploy account                       |
| `DEPLOY_KEY`     | `ADMIN_KEY` | SSH public key(s) for the deployer   |
| `TZ`             | `UTC`       | System timezone                      |
| `RUNTIME`        | `podman`    | Container runtime: `docker` or `podman` |

Keys may be a single public key or a list (one per line). Each is checked with
`ssh-keygen` before it is installed; anything that isn't a public key aborts the run.


## Security notes

**Pin the repo with `hash:`.** The whole tree runs as root on your server, so we
recommend pinning a commit in your host manifest, setting the `bootstrap.hash` value to
the git commit hash, and reviewing the changes before running it.

**Unprivileged ports start at 80** (`net.ipv4.ip_unprivileged_port_start`) so rootless
containers can serve 80/443. This applies to every non-root user on the host, not just
the deployer; fine for a single-purpose server, but just to be aware. If this is a
problem for you, you could use docker instead of podman, or run on a higher port and put
a reverse proxy in front of your server.

**Security updates are installed automatically** but the host does not reboot
itself. Check `/var/run/reboot-required` (or watch for the MOTD notice) after
kernel updates.


## Development and customisation

If you want to help work on this, or you want to customise your own bootstrap repo:

* `bootstrap.sh` is the entrypoint `boff bootstrap` runs. It installs `ansible-core`,
  then uses it to run `playbook.yml`.
- `playbook.yml` is the top-level ansible configuration
- `group_vars/all.yml` - maps `BOFFYN_*` env vars (and `requirements.txt`'s pinned
  versions) into the variables the roles use.
- `roles/` - the Ansible roles
- `requirements.txt` - pinned tool versions (`uv`, `ansible-core`, `podman-compose`).
  This file is not used by pip/uv directly - the versions are extracted by the bash
  function `pinned_version` - but it is watched by dependabot to keep things up-to-date.

Run `./tests/test.sh` with docker installed to test the bootstrap script in a container.
