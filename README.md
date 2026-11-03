<div align="center">
  <h1>openGym on Proxmox VE</h1>
  <p><strong>A one-command LXC installer for <a href="https://github.com/DuarteSantos8/openGym">openGym</a>, the self-hosted gym and body-weight tracker</strong></p>

  <p>
    <a href="https://github.com/DuarteSantos8/openGym"><img src="https://img.shields.io/badge/App-openGym-4c9b3f?style=flat-square" alt="openGym" /></a>
    <a href="https://github.com/community-scripts/ProxmoxVE"><img src="https://img.shields.io/badge/Based_on-community--scripts-7289da?style=flat-square" alt="Based on community-scripts" /></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue?style=flat-square" alt="License" /></a>
  </p>
</div>

---

## What is this?

A fork of [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE)
that is mainly about **openGym**. One command in the Proxmox shell creates a Debian 13
container, installs openGym (the latest GitHub release) with nginx in front of it, and
sets up an `update` command inside the container.

The difference from the upstream script: the container's `update` pulls the script
**from this repo**. So fixes like the migration from the old installation land here
first, without waiting for upstream.

| | |
|---|---|
| Scripts | [`ct/opengym.sh`](ct/opengym.sh), [`install/opengym-install.sh`](install/opengym-install.sh) |
| App | [DuarteSantos8/openGym](https://github.com/DuarteSantos8/openGym) |
| Defaults | Debian 13, 2 CPU, 2048 MB RAM, 4 GB disk, unprivileged |

## Installation

In the shell of the **Proxmox host**:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/hutti207/proxmox-opengym/main/ct/opengym.sh)"
```

Afterwards openGym is reachable at `http://<container-IP>`. The first profile you
create becomes the admin.

## Updating

In the **container**:

```bash
update
```

The script checks for a new openGym release, builds it and restarts the service.
The data in `/opt/opengym_data` is kept.

**Containers from the very first version of this script** (git checkout of
`arvids-unavailable/openGym`, data in `/opt/opengym-data`) are migrated automatically on
the first `update`: the data moves to `/opt/opengym_data`, a backup lands in
`/opt/opengym-migration-backup-<date>.tar.gz`, and the old folder stays in place.

## Configuration

Everything lives in `/opt/opengym_data/.env`. After changes:

```bash
systemctl restart opengym
```

**Passkeys and the mobile app** need HTTPS on a hostname. Behind a reverse proxy
(Caddy, Cloudflare Tunnel, ...) set both values to the address in the browser:

```bash
RP_ID=gym.example.com
ORIGIN=https://gym.example.com
```

Then open openGym only through that address. Pair the app under
Settings → Account → "Pair the mobile app". Changing `RP_ID` later
invalidates existing passkeys.

| Path | Contents |
|---|---|
| `/opt/opengym` | App (replaced on every update) |
| `/opt/opengym_data` | Database, secrets, uploads, `.env` |
| `/etc/nginx/sites-available/opengym` | nginx: frontend + proxy for `/api/` |
| `opengym.service` | API on port 3000 |

## Syncing with upstream

```bash
git fetch upstream
git merge upstream/main
```

On conflicts in `README.md` keep this version; in `ct/opengym.sh` keep the
`_CS_DEFAULT_URL` line.

## Credits

- [openGym](https://github.com/DuarteSantos8/openGym) by Duarte Santos (AGPL-3.0)
- [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE) and
  [core](https://github.com/community-scripts/core), built on
  [@tteck](https://github.com/tteck)'s original work (MIT)
