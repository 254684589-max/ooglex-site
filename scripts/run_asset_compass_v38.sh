#!/usr/bin/env bash
# V38 Mac operator entrypoint. No secrets printed or uploaded to GitHub.
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"
VENV="${HOME}/.local/share/ooglex/v38-venv"
if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3 required" >&2
  exit 1
fi
if [ ! -x "$VENV/bin/python" ]; then
  mkdir -p "$(dirname "$VENV")"
  python3 -m venv "$VENV"
fi
if ! "$VENV/bin/python" -c "import cryptography, boto3" >/dev/null 2>&1; then
  "$VENV/bin/python" -m pip install "cryptography==46.0.4" "boto3>=1.35,<2"
fi
# --capture fetches official webpages into a private local directory.
# --offsite explicitly enables private R2 upload and recovered read-back.
exec "$VENV/bin/python" -m scripts.accept_asset_compass_recovery_v38 \
  --private-dir "$HOME/.local/share/ooglex/private-historical-evidence" \
  --backup-dir "$HOME/.local/share/ooglex/private-backups" \
  --output "/tmp/ooglex-v38-acceptance.json" "$@"
