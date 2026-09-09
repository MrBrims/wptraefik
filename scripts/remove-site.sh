#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: remove-site.sh <slug>

  slug  Folder name used in certs/ and dynamic/ (e.g. mysite)

Examples:
  ./scripts/remove-site.sh mysite
  make remove-site SLUG=mysite
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

SLUG="$1"

if [[ ! "$SLUG" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
  echo "Invalid slug: $SLUG (use letters, numbers, underscore, hyphen)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# Each site is a cert pair + dynamic TLS file; both must be removed together
CERT_DIR="$ROOT_DIR/certs/$SLUG"
TLS_FILE="$ROOT_DIR/dynamic/${SLUG}-tls.yml"

REMOVED=false

if [[ -d "$CERT_DIR" ]]; then
  rm -rf "$CERT_DIR"
  echo "Removed: $CERT_DIR"
  REMOVED=true
fi

if [[ -f "$TLS_FILE" ]]; then
  rm -f "$TLS_FILE"
  echo "Removed: $TLS_FILE"
  REMOVED=true
fi

if [[ "$REMOVED" != true ]]; then
  echo "Nothing to remove for slug '$SLUG'." >&2
  exit 1
fi

# Site projects are separate repos — Traefik labels must be removed manually there
echo ""
echo "Remember to remove Traefik labels from the site project's docker-compose.override.yml."
echo ""

# Traefik stops serving the old cert once the dynamic file is gone
if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'traefik_proxy'; then
  echo "Restarting traefik_proxy..."
  docker restart traefik_proxy
else
  echo "Traefik is not running."
fi
