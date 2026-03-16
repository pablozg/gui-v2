#!/bin/bash
#
# Deploy modified GUI v2 QML files to Cerbo GX via SSH
# Automatically detects all changed files (committed + uncommitted) vs origin/main
# Reads SSH password from .deploy-password file (not tracked by git)
#
# Usage: ./deploy-to-gx.sh <IP_or_hostname> [--restart]
#
# Examples:
#   ./deploy-to-gx.sh 192.168.1.100
#   ./deploy-to-gx.sh 192.168.1.100 --restart
#   ./deploy-to-gx.sh venus.local --restart

set -e

GX_HOST="${1}"
RESTART="${2}"
GX_USER="root"
GX_BASE="/opt/victronenergy/gui-v2/Victron/VenusOS"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$GX_HOST" ]; then
    echo "Usage: $0 <IP_or_hostname> [--restart]"
    echo ""
    echo "Options:"
    echo "  --restart    Restart the GUI service after uploading"
    exit 1
fi

cd "$SCRIPT_DIR"

# Password setup via sshpass
PW_FILE="$SCRIPT_DIR/.deploy-password"
if [ ! -f "$PW_FILE" ]; then
    echo "Password file not found: .deploy-password"
    echo "Create it with your GX root password:"
    echo "  echo 'YOUR_PASSWORD' > .deploy-password"
    exit 1
fi

if ! command -v sshpass &>/dev/null; then
    echo "sshpass not installed. Install it: sudo apt install sshpass"
    exit 1
fi

export SSHPASS="$(cat "$PW_FILE" | tr -d '\\n')"
SSH="sshpass -e ssh -o StrictHostKeyChecking=no"
SCP="sshpass -e scp -o StrictHostKeyChecking=no"

# Auto-detect modified QML/JS/JSON files vs origin/main (committed + uncommitted)
mapfile -t FILES < <(
    {
        git diff --name-only origin/main HEAD 2>/dev/null
        git diff --name-only HEAD 2>/dev/null
    } | sort -u | grep -E '\.(qml|js|json)$' | grep -E '^(components|pages|data|themes)/|^[^/]+\.(qml|js)$'
)

if [ ${#FILES[@]} -eq 0 ]; then
    echo "No modified QML/JS files found vs origin/main."
    exit 0
fi

echo "=== Deploy GUI v2 to Cerbo GX ==="
echo "Host: ${GX_HOST}"
echo "Target: ${GX_BASE}"
echo "Files to deploy: ${#FILES[@]}"
echo ""

# Create backup on GX device
echo ">> Creating backup on GX device..."
BACKUP_CMD="mkdir -p /tmp/gui-v2-backup"
for FILE in "${FILES[@]}"; do
    DIR=$(dirname "$FILE")
    BACKUP_CMD+="; if [ -f '${GX_BASE}/${FILE}' ]; then mkdir -p '/tmp/gui-v2-backup/${DIR}' && cp '${GX_BASE}/${FILE}' '/tmp/gui-v2-backup/${FILE}'; fi"
done
$SSH "${GX_USER}@${GX_HOST}" "${BACKUP_CMD}"
echo "   Backup saved to /tmp/gui-v2-backup/"
echo ""

# Pack, upload, and extract in minimal connections
echo ">> Packing ${#FILES[@]} files into tar..."
TAR_FILE="/tmp/gui-v2-deploy.tar.gz"
tar czf "$TAR_FILE" "${FILES[@]}"
echo "   Created $TAR_FILE"

echo ">> Uploading tar to GX device..."
$SCP "$TAR_FILE" "${GX_USER}@${GX_HOST}:/tmp/gui-v2-deploy.tar.gz"
rm -f "$TAR_FILE"
echo "   Uploaded successfully"
echo ""

echo ">> Extracting on GX device..."
EXTRACT_CMD="cd '${GX_BASE}' && tar xzf /tmp/gui-v2-deploy.tar.gz && rm /tmp/gui-v2-deploy.tar.gz"
if [ "$RESTART" = "--restart" ]; then
    EXTRACT_CMD+=" && svc -t /service/start-gui && echo 'GUI service restarted'"
fi
$SSH "${GX_USER}@${GX_HOST}" "${EXTRACT_CMD}"
echo "   Extracted ${#FILES[@]} files"
if [ "$RESTART" = "--restart" ]; then
    echo "   GUI service restarted"
fi

echo ""
echo "=== Done: ${#FILES[@]} files deployed ==="

echo ""
echo "To restore backup:"
echo "  ssh ${GX_USER}@${GX_HOST} 'cp -r /tmp/gui-v2-backup/* ${GX_BASE}/'"
