#!/usr/bin/env bash
#
# Omarchy SIP Softphone & Dialer Uninstaller
# Cleans up background daemons, Quickshell widget, binaries, and configurations.
#

set -e

CURRENT_USER="$(whoami)"
PLUGIN_ID="${CURRENT_USER}.dialer"

echo "========================================================"
echo "    Omarchy SIP Softphone & Dialer Uninstaller          "
echo "========================================================"
echo ""

echo "[-] Stopping and disabling background services..."
systemctl --user stop baresip.service omarchy-dialer-monitor.service 2>/dev/null || true
systemctl --user disable baresip.service omarchy-dialer-monitor.service 2>/dev/null || true

echo "[-] Removing systemd service files..."
rm -f "$HOME/.config/systemd/user/baresip.service"
rm -f "$HOME/.config/systemd/user/omarchy-dialer-monitor.service"
systemctl --user daemon-reload 2>/dev/null || true

echo "[-] Removing omarchy-dialer binary..."
rm -f "$HOME/.local/bin/omarchy-dialer"

echo "[-] Removing desktop application entry..."
rm -f "$HOME/.local/share/applications/omarchy-dialer.desktop"

echo "[-] Removing Quickshell dialer plugin ($PLUGIN_ID)..."
rm -rf "$HOME/.config/omarchy/plugins/$PLUGIN_ID"

# Remove from shell.json if present
SHELL_JSON="$HOME/.config/omarchy/shell.json"
if [ -f "$SHELL_JSON" ] && command -v jq >/dev/null 2>&1; then
    echo "[-] Removing plugin from shell.json layout..."
    jq --arg pid "$PLUGIN_ID" '
        if .layout?.primary?.right then
            .layout.primary.right = (.layout.primary.right | map(select(. != $pid)))
        else
            .
        end
    ' "$SHELL_JSON" > "${SHELL_JSON}.tmp" && mv "${SHELL_JSON}.tmp" "$SHELL_JSON"
fi

echo ""
read -rp "Do you also want to remove SIP accounts and configuration files (~/.baresip, ~/.config/omarchy/sip*.json)? [y/N]: " REMOVE_CONF
if [[ "$REMOVE_CONF" =~ ^[Yy]$ ]]; then
    rm -rf "$HOME/.baresip"
    rm -f "$HOME/.config/omarchy/sip.json"
    rm -f "$HOME/.config/omarchy/sip_recents.json"
    echo "[+] Configuration files deleted."
fi

echo ""
echo "[+] Omarchy SIP Dialer has been uninstalled."
