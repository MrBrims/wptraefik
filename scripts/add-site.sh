#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: add-site.sh <slug> <domain> [--force]

  slug    Folder name for certs/ and dynamic/ (e.g. mysite)
  domain  Primary domain (e.g. mysite.localhost)

Examples:
  ./scripts/add-site.sh mysite mysite.localhost
  make add-site SLUG=mysite DOMAIN=mysite.localhost
EOF
}

if [[ $# -lt 2 ]]; then
  usage
  exit 1
fi

SLUG="$1"
DOMAIN="$2"
FORCE=false

if [[ "${3:-}" == "--force" ]]; then
  FORCE=true
elif [[ -n "${3:-}" ]]; then
  echo "Unknown argument: $3" >&2
  usage
  exit 1
fi

# Slug becomes the folder name in certs/ and dynamic/ (e.g. certs/mysite/, dynamic/mysite-tls.yml)
if [[ ! "$SLUG" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
  echo "Invalid slug: $SLUG (use letters, numbers, underscore, hyphen)" >&2
  exit 1
fi

# mkcert -install must be run once so browsers trust the local CA
if ! command -v mkcert >/dev/null 2>&1; then
  echo "mkcert not found in PATH. Install mkcert and run 'mkcert -install' first." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CERT_DIR="$ROOT_DIR/certs/$SLUG"
TLS_FILE="$ROOT_DIR/dynamic/${SLUG}-tls.yml"
TEMPLATE="$ROOT_DIR/templates/_template-tls.yml"

if [[ ! -f "$TEMPLATE" ]]; then
  echo "Template not found: $TEMPLATE" >&2
  exit 1
fi

if [[ -d "$CERT_DIR" || -f "$TLS_FILE" ]]; then
  if [[ "$FORCE" != true ]]; then
    echo "Site '$SLUG' already exists:" >&2
    [[ -d "$CERT_DIR" ]] && echo "  - $CERT_DIR" >&2
    [[ -f "$TLS_FILE" ]] && echo "  - $TLS_FILE" >&2
    echo "Use --force to overwrite." >&2
    exit 1
  fi
fi

mkdir -p "$CERT_DIR"

# Wildcard covers subdomains (pma., mail., etc.) with a single certificate
mkcert \
  -cert-file "$CERT_DIR/local.pem" \
  -key-file "$CERT_DIR/local-key.pem" \
  "$DOMAIN" "*.$DOMAIN"

# Generate dynamic/<slug>-tls.yml from template; Traefik loads it via file provider
sed "s/PROJECT_SLUG/$SLUG/g" "$TEMPLATE" > "$TLS_FILE"

echo "Created:"
echo "  $CERT_DIR/local.pem"
echo "  $CERT_DIR/local-key.pem"
echo "  $TLS_FILE"
echo ""
echo "Next steps:"
echo "  1. Add Traefik labels in the site project's docker-compose.override.yml"
echo "  2. Set https:// URLs in the site project's .env"
echo ""

# Restart picks up the new dynamic TLS config immediately (watch may lag on some setups)
if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'traefik_proxy'; then
  echo "Restarting traefik_proxy..."
  docker restart traefik_proxy
else
  echo "Traefik is not running. Start it with: make up"
fi
