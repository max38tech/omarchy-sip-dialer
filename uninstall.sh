#!/usr/bin/env bash
#
# Omarchy SIP Softphone & Dialer Uninstaller
# Stops the background services and removes the CLI, widget, launcher entry,
# top-bar placement, and keybinding. Your SIP settings are kept unless you say so.
#

set -euo pipefail

CURRENT_USER="$(whoami)"
PLUGIN_ID="${CURRENT_USER}.dialer"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
BINDINGS_LUA="$HOME/.config/hypr/bindings.lua"

echo "========================================================"
echo "    Omarchy SIP Softphone & Dialer Uninstaller          "
echo "========================================================"
echo ""

echo "[-] Stopping and disabling background services..."
systemctl --user disable --now baresip.service omarchy-dialer-monitor.service 2>/dev/null || true

echo "[-] Removing systemd service files..."
rm -f "$HOME/.config/systemd/user/baresip.service"
rm -f "$HOME/.config/systemd/user/omarchy-dialer-monitor.service"
systemctl --user daemon-reload 2>/dev/null || true

echo "[-] Removing the omarchy-dialer CLI..."
rm -f "$HOME/.local/bin/omarchy-dialer"

echo "[-] Removing the application launcher entry..."
rm -f "$HOME/.local/share/applications/omarchy-dialer.desktop"

echo "[-] Removing the Quickshell widget ($PLUGIN_ID)..."
if command -v omarchy-plugin-disable >/dev/null 2>&1; then
    omarchy-plugin-disable "$PLUGIN_ID" >/dev/null 2>&1 || true
fi
rm -rf "$PLUGIN_DIR"
if command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
fi

# Remove the widget from every bar section in shell.json.
if [ -f "$SHELL_JSON" ] && command -v jq >/dev/null 2>&1; then
    echo "[-] Removing the widget from the top bar..."
    jq --arg id "$PLUGIN_ID" '
        if .bar?.layout then
            .bar.layout |= with_entries(.value |= map(select(.id != $id)))
        else
            .
        end
    ' "$SHELL_JSON" > "${SHELL_JSON}.tmp" && mv "${SHELL_JSON}.tmp" "$SHELL_JSON"
fi

if [ -f "$BINDINGS_LUA" ] && grep -q "omarchy-dialer toggle" "$BINDINGS_LUA"; then
    echo "[-] Removing the keybinding from bindings.lua..."
    sed -i '/omarchy-dialer toggle/d' "$BINDINGS_LUA"
    if command -v omarchy-restart-hyprctl >/dev/null 2>&1; then
        omarchy-restart-hyprctl >/dev/null 2>&1 || true
    fi
fi

echo ""
read -rp "Also remove your SIP account and call settings (~/.baresip, ~/.config/omarchy/sip*.json)? [y/N]: " REMOVE_CONF
if [[ "$REMOVE_CONF" =~ ^[Yy]$ ]]; then
    rm -rf "$HOME/.baresip"
    rm -f "$HOME/.config/omarchy/sip.json"
    rm -f "$HOME/.config/omarchy/sip_recents.json"
    rm -f "$HOME/.config/omarchy/sip_call_state.json"
    echo "[+] SIP settings removed."
else
    echo "[+] SIP settings kept in ~/.baresip and ~/.config/omarchy/sip.json."
fi

echo ""
echo "[+] Omarchy SIP Dialer has been uninstalled."
echo "    The pacman packages (baresip, libpulse) were left installed."
