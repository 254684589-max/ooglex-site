#!/usr/bin/env bash
# V52 one-command private BLS/BEA source capture + authenticated restore.
# Never put secrets or originals in the public website repository.
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"
OFFSITE=0
if [ "${1:-}" = "--offsite" ]; then OFFSITE=1
elif [ "$#" -ne 0 ]; then
  echo "Usage: bash scripts/run_asset_compass_v52.sh [--offsite]" >&2
  exit 2
fi
BASE="$HOME/.local/share/ooglex"
VENV="$BASE/v52-venv"
PRIVATE="$BASE/private-historical-evidence/v52"
BACKUPS="$BASE/private-backups/v52"
mkdir -p "$BASE" "$PRIVATE" "$BACKUPS"
chmod 700 "$PRIVATE" "$BACKUPS"
if [ ! -x "$VENV/bin/python" ]; then python3 -m venv "$VENV"; fi
if ! "$VENV/bin/python" -c "import cryptography" >/dev/null 2>&1; then
  "$VENV/bin/python" -m pip install "cryptography==46.0.4"
fi
if [ "$OFFSITE" -eq 1 ]; then
  if ! "$VENV/bin/python" -c "import boto3" >/dev/null 2>&1; then
    "$VENV/bin/python" -m pip install "boto3>=1.35,<2"
  fi
  for name in CLOUDFLARE_ACCOUNT_ID OOGLEX_R2_PRIVATE_BUCKET AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY; do
    if [ -z "${!name:-}" ]; then
      echo "Missing required private R2 configuration: $name" >&2
      exit 2
    fi
  done
fi
if [ -z "${OOGLEX_BACKUP_PASSPHRASE:-}" ]; then
  printf 'Enter V52 private backup passphrase (16+ characters; input hidden): ' >&2
  IFS= read -r -s OOGLEX_BACKUP_PASSPHRASE
  printf '\n' >&2
  export OOGLEX_BACKUP_PASSPHRASE
fi
if [ "${#OOGLEX_BACKUP_PASSPHRASE}" -lt 16 ]; then
  echo "Backup passphrase must be 16 characters or longer" >&2
  exit 2
fi
"$VENV/bin/python" -m scripts.asset_compass_custody_v52 capture \
  --private-dir "$PRIVATE" --output /tmp/ooglex-v52-capture.json
"$VENV/bin/python" -m scripts.asset_compass_custody_v52 audit \
  --private-dir "$PRIVATE" --output /tmp/ooglex-v52-audit.json
EXTRA=()
if [ "$OFFSITE" -eq 1 ]; then EXTRA=(--offsite); fi
"$VENV/bin/python" -m scripts.asset_compass_custody_v52 backup \
  --private-dir "$PRIVATE" --backup-dir "$BACKUPS" \
  --output /tmp/ooglex-v52-backup.json "${EXTRA[@]}"
echo "V52 verified: local raw HTML saved privately; AES-256-GCM archive and restore test complete."
if [ "$OFFSITE" -eq 1 ]; then echo "Private R2 readback plus actual decrypted restore verified."; fi
echo "Historical PIT authorization and six-asset scoring remain blocked."
