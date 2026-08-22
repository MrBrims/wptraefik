# Traefik Local Proxy

[![Traefik](https://img.shields.io/badge/Traefik-v2.11-24A1C1.svg)](https://doc.traefik.io/traefik/)
[![Docker](https://img.shields.io/badge/Docker-Compose-blue.svg)](https://docs.docker.com/compose/)
[![mkcert](https://img.shields.io/badge/mkcert-local%20TLS-green.svg)](https://github.com/FiloSottile/mkcert)
[![WordPress stack](https://img.shields.io/badge/WordPress-wpdocker-21759B.svg)](https://github.com/MrBrims/wpdocker)
[![Version](https://img.shields.io/badge/Version-1.1.0-green.svg)](#changelog)

A local reverse proxy for Docker projects. Traefik routes containers by domain (`mysite.localhost`) over HTTPS. Each project gets its own **mkcert** certificate (`certs/<slug>/` + `dynamic/<slug>-tls.yml`).

Browsers resolve `*.localhost` to `127.0.0.1` automatically — no hosts file edits on the dev machine.

## Description

This repository runs a single Traefik instance that:

- Listens on ports **80** (redirect to HTTPS) and **443** (TLS)
- Discovers site containers via Docker labels on the external network `traefik_web`
- Loads per-project TLS certificates from `dynamic/*-tls.yml`
- Exposes a dev dashboard on **http://127.0.0.1:8080** (localhost only, no TLS)

Site projects connect via Docker labels on the external network `traefik_web` — they stay in their own repositories.

## Works with wpdocker

This repository is the **reverse proxy and TLS layer** only — it does not run WordPress.

The companion stack is **[MrBrims/wpdocker](https://github.com/MrBrims/wpdocker)**: PHP-FPM, Nginx, MySQL, and phpMyAdmin with Traefik labels already wired in `docker-compose.yml`.

## Full stack quick start (with wpdocker)

1. Clone and start Traefik:
   ```bash
   git clone https://github.com/MrBrims/wptraefik.git
   cd wptraefik
   make up
   ```

2. Register TLS for the default wpdocker hostnames:
   ```bash
   make add-site SLUG=wp DOMAIN=wp.localhost
   ```
   Slug `wp` matches `PROJECT_NAME` in wpdocker. The `*.wp.localhost` wildcard covers `pma.wp.localhost`.

3. Clone and start WordPress:
   ```bash
   git clone https://github.com/MrBrims/wpdocker.git
   cd wpdocker
   cp .env.example .env
   make start
   ```

4. Open [https://wp.localhost](https://wp.localhost) and [https://pma.wp.localhost](https://pma.wp.localhost).

## Requirements

- Docker Desktop (or Docker + Docker Compose)
- [mkcert](https://github.com/FiloSottile/mkcert) — after install, run **`mkcert -install`** (trust the local CA in Windows; for Firefox see [Troubleshooting](#troubleshooting))
- Site projects attached to the `traefik_web` network with Traefik labels (see [Adding a site](#adding-a-site))

## Installation

### Quick start

1. Start Traefik from the repository root:
   ```bash
   make up
   ```
   Or without Make: `docker compose up -d`.

2. Open the dashboard:
   ```bash
   make dashboard
   ```
   Or open http://127.0.0.1:8080 in a browser.

3. Add a site certificate and TLS config:
   ```bash
   make add-site SLUG=mysite DOMAIN=mysite.localhost
   ```

4. Configure Traefik labels in the site project (if not already present) and run `docker compose up -d` there. [wpdocker](https://github.com/MrBrims/wpdocker) ships with labels in its main `docker-compose.yml`.

After at least one site is configured, open it at `https://<domain>.localhost`.

### Make commands

`make help` lists all targets:

```bash
make help                                        # list commands
make up                                          # start Traefik
make down                                        # stop Traefik
make restart                                     # restart traefik_proxy
make logs                                        # follow Traefik logs
make dashboard                                   # open dashboard in browser
make add-site SLUG=mysite DOMAIN=mysite.localhost  # mkcert + dynamic TLS
make remove-site SLUG=mysite                     # remove cert and dynamic TLS
```

## Adding a site

Replace `mysite` (folder slug) and `mysite.localhost` (domain). If the site uses `PROJECT_NAME` and hostname variables in `.env` (as in [wpdocker](https://github.com/MrBrims/wpdocker)), the slug and domain usually match those values.

### Quick setup (recommended)

From the repository root:

```bash
make add-site SLUG=mysite DOMAIN=mysite.localhost
```

This creates `certs/mysite/` (mkcert), `dynamic/mysite-tls.yml`, and restarts Traefik if the container is already running.

### Manual setup

#### 1. mkcert certificate

From the repository root:

```bash
mkdir -p certs/mysite

mkcert -cert-file certs/mysite/local.pem -key-file certs/mysite/local-key.pem \
  mysite.localhost "*.mysite.localhost"
```

Include the primary domain and a wildcard for subdomains (`pma.`, `mail.`, etc.).

#### 2. Dynamic TLS in Traefik

```bash
cp templates/_template-tls.yml dynamic/mysite-tls.yml
```

Replace `PROJECT_SLUG` with `mysite` (paths `/certs/mysite/local.pem` and `local-key.pem`).

Traefik reloads dynamic config automatically (`watch: true`). If unsure:

```bash
docker restart traefik_proxy
```

#### 3. Site project Docker Compose

Add Traefik labels to each public service in the site's `docker-compose.yml` or `docker-compose.override.yml`. [wpdocker](https://github.com/MrBrims/wpdocker) already includes them in the main compose file — see the [full example](https://github.com/MrBrims/wpdocker/blob/main/docker-compose.yml).

- Network `traefik_web` (`external: true`)
- No direct host ports for HTTP (port 80 inside the container)
- Labels on each public service (Nginx + phpMyAdmin example from wpdocker):

```yaml
networks:
  traefik_web:
    external: true

services:
  nginx:
    networks:
      - traefik_web
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${PROJECT_NAME}-nginx.rule=Host(`${SITE_HOSTNAME}`)"
      - "traefik.http.routers.${PROJECT_NAME}-nginx.entrypoints=websecure"
      - "traefik.http.routers.${PROJECT_NAME}-nginx.tls=true"
      - "traefik.http.services.${PROJECT_NAME}-nginx.loadbalancer.server.port=80"
      - "traefik.docker.network=traefik_web"

  phpmyadmin:
    networks:
      - traefik_web
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${PROJECT_NAME}-pma.rule=Host(`${PMA_HOSTNAME}`)"
      - "traefik.http.routers.${PROJECT_NAME}-pma.entrypoints=websecure"
      - "traefik.http.routers.${PROJECT_NAME}-pma.tls=true"
      - "traefik.http.services.${PROJECT_NAME}-pma.loadbalancer.server.port=80"
      - "traefik.docker.network=traefik_web"
```

If the **service** name differs from the **router** name, add an explicit binding:

```yaml
- "traefik.http.routers.${PROJECT_NAME}-nginx.service=${PROJECT_NAME}-web"
```

By default Traefik links router and service when they share the same name (e.g. both `${PROJECT_NAME}-nginx`).

Set **https://** URLs in the site project's `.env` / `.env.example` (e.g. `SITE_HOSTNAME=wp.localhost`, `PMA_HOSTNAME=pma.wp.localhost`).

#### 4. Start the site project

```bash
cd /path/to/project
docker compose up -d
```

#### 5. Verify

- https://mysite.localhost
- https://pma.mysite.localhost (if phpMyAdmin is enabled; wpdocker default: `pma.wp.localhost`)

HTTP on port 80 should redirect to HTTPS.

## Removing a site

```bash
make remove-site SLUG=mysite
```

Or manually:

1. Delete `certs/<slug>/`
2. Delete `dynamic/<slug>-tls.yml`
3. Remove Traefik labels / override in the site repository

## LAN access (phone or another PC)

On other devices, `*.localhost` does **not** resolve to the dev machine IP — configure hosts or DNS manually:

1. On the dev machine: `mkcert -CAROOT` — copy `rootCA.pem` to the device and install as a trusted CA.
2. On the device hosts file — dev machine IP and the same domains (`mysite.localhost`, `pma.mysite.localhost`, etc.).
3. Certificates in `certs/<slug>/` must already exist on the machine running Traefik.

## Project Structure

```
.
├── certs/                    # per-site mkcert files (*.pem gitignored)
│   └── .gitkeep
├── dynamic/                  # Traefik file provider — TLS configs
│   ├── .gitkeep
│   └── example-tls.yml       # committed example; real sites via make add-site
├── scripts/
│   ├── add-site.sh           # mkcert + dynamic TLS scaffold
│   └── remove-site.sh        # remove site cert and TLS config
├── templates/
│   └── _template-tls.yml     # template for new dynamic TLS files
├── .cursor/rules/
│   └── traefik-local-ssl.mdc # Cursor rule for local HTTPS setup
├── docker-compose.yml        # Traefik container, ports, healthcheck
├── traefik.yml               # static config (entrypoints, providers)
├── Makefile                  # docker compose wrappers (make help)
├── .gitignore
└── README.md
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `NET::ERR_CERT_AUTHORITY_INVALID` | Run **`mkcert -install`**, then fully restart the browser. `.pem` files alone do not trust the CA — the mkcert root CA must be installed in the OS. |
| Firefox on Windows | mkcert does not install CA in Firefox. Import manually: Settings → Privacy → Certificates → View → Authorities → Import → `%LOCALAPPDATA%\mkcert\rootCA.pem` (path from `mkcert -CAROOT`) → trust for websites. |
| Wrong cert / `TRAEFIK DEFAULT CERT` | No `certs/<slug>/` + `dynamic/<slug>-tls.yml` pair for this domain. Create TLS for that slug (one cert per project). |
| One `.localhost` site works, another does not | Each project needs its own slug in `certs/` and `dynamic/`, not only the committed example. |
| Cert name mismatch | Check mkcert SAN (`*.domain.localhost`), paths in `dynamic/*-tls.yml`, open the correct domain (not bare IP). |
| 404 / Bad Gateway | Container on `traefik_web`, `traefik.enable=true`, service port matches container port. |
| Site only over HTTP | Add labels `entrypoints=websecure` and `tls=true`. |
| Traefik ignores cert | Ensure `local.pem` / `local-key.pem` exist and are non-empty; `docker restart traefik_proxy` after creating pem files. |

### Verify from the dev machine

```bash
# Certificate served for a domain (should be mkcert, not TRAEFIK DEFAULT CERT):
echo | openssl s_client -connect 127.0.0.1:443 -servername example.localhost 2>/dev/null | openssl x509 -noout -subject

# mkcert root CA in Windows (should mention mkcert development CA):
mkcert -install
```

## Example: example.localhost

- Slug: `example`, domain: `example.localhost`
- Committed sample: `dynamic/example-tls.yml` (certificates are generated locally)

```bash
make add-site SLUG=example DOMAIN=example.localhost
```

## Changelog

### 1.1.0

- **NEW**: `make dashboard` — open Traefik dashboard in the default browser
- **NEW**: `make add-site` / `make remove-site` — mkcert certificate and dynamic TLS automation
- **CHANGED**: Makefile rewritten for Traefik (removed unrelated WordPress targets)
- **CHANGED**: Dashboard bound to `127.0.0.1:8080` only (not exposed on LAN)
- **NEW**: Container healthcheck via Traefik ping
- **CHANGED**: README restructured in English with badges, project tree, and changelog

### 1.0.0

- **NEW**: Traefik v2.11 reverse proxy with Docker and file providers
- **NEW**: Per-project mkcert TLS (`certs/<slug>/` + `dynamic/<slug>-tls.yml`)
- **NEW**: HTTP → HTTPS redirect on port 80
- **NEW**: External Docker network `traefik_web` for site projects
- **NEW**: Cursor rule and README for local HTTPS onboarding

## Support

Open an issue in this repository or contact the maintainer.
