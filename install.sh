#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLICATIONS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
DESKTOP_FILE="$APPLICATIONS_DIR/vpn-browser.desktop"

mkdir -p "$APPLICATIONS_DIR"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=VPN Browser & Torrent
Comment=Run Firefox and qBittorrent through Speedify
Exec=$PROJECT_DIR/vpn-browser
Icon=network-vpn
Terminal=false
Type=Application
Categories=Network;
StartupNotify=true
EOF

chmod +x "$PROJECT_DIR/vpn-browser"
chmod +x "$DESKTOP_FILE"

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APPLICATIONS_DIR"
fi

echo "Installed VPN Browser & Torrent application shortcut."
echo "Launcher: $DESKTOP_FILE"
