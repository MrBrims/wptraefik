# Traefik Local Proxy

[![Traefik](https://img.shields.io/badge/Traefik-v2.11-24A1C1.svg)](https://doc.traefik.io/traefik/)
[![Docker](https://img.shields.io/badge/Docker-Compose-blue.svg)](https://docs.docker.com/compose/)
[![mkcert](https://img.shields.io/badge/mkcert-local%20TLS-green.svg)](https://github.com/FiloSottile/mkcert)
[![Version](https://img.shields.io/badge/Version-1.1.0-green.svg)](#changelog)

A local reverse proxy for Docker projects. Traefik routes containers by domain (`mysite.localhost`) over HTTPS. Each project gets its own **mkcert** certificate (`certs/<slug>/` + `dynamic/<slug>-tls.yml`).

Browsers resolve `*.localhost` to `127.0.0.1` automatically — no hosts file edits on the dev machine.

## Description

This repository runs a single Traefik instance that:

- Listens on ports **80** (redirect to HTTPS) and **443** (TLS)
- Discovers site containers via Docker labels on the external network `traefik_web`
- Loads per-project TLS certificates from `dynamic/*-tls.yml`
- Exposes a dev dashboard on **http://127.0.0.1:8080** (localhost only, no TLS)

Site projects connect through `docker-compose.override.yml` labels — they stay in their own repositories.

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

4. Configure labels in the site project's `docker-compose.override.yml` and run `docker compose up -d` there.

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

Replace `mysite` (folder slug) and `mysite.localhost` (domain). If the site uses `PROJECT_NAME` / `PROJECT_DOMAIN` in `.env`, those values usually match the slug and domain.

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

In the site's `docker-compose.override.yml`:

- Network `traefik_web` (`external: true`)
- No direct host ports for HTTP (port 80 inside the container)
- Labels on each public service:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.${PROJECT_NAME}-php.rule=Host(`${PROJECT_DOMAIN}`)"
  - "traefik.http.routers.${PROJECT_NAME}-php.entrypoints=websecure"
  - "traefik.http.routers.${PROJECT_NAME}-php.tls=true"
  - "traefik.http.services.${PROJECT_NAME}-php.loadbalancer.server.port=80"
  - "traefik.docker.network=traefik_web"
```

If the **service** name differs from the **router** name, add an explicit binding:

```yaml
- "traefik.http.routers.${PROJECT_NAME}-php.service=${PROJECT_NAME}-nginx"
```

By default Traefik links router and service when they share the same name (e.g. both `${PROJECT_NAME}-php`).

| Service    | Host rule                    | Port |
|------------|------------------------------|------|
| phpMyAdmin | `` Host(`pma.${PROJECT_DOMAIN}`) `` | 80   |
| MailHog    | `` Host(`mail.${PROJECT_DOMAIN}`) `` | 8025 |

Set **https://** URLs in the site project's `.env` / `.env.example` (e.g. `https://mysite.localhost`).

#### 4. Start the site project

```bash
cd /path/to/project
docker compose up -d
```

#### 5. Verify

- https://mysite.localhost
- https://pma.mysite.localhost (if phpMyAdmin is enabled)
- https://mail.mysite.localhost (if MailHog is enabled)

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
