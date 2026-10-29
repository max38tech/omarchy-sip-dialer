#!/usr/bin/env bash
#
# Omarchy SIP Softphone & Dialer Installer
# Installs baresip, configures SIP credentials, sets up Quickshell widget,
# PipeWire audio integration, systemd services, and desktop integration.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURRENT_USER="$(whoami)"
PLUGIN_ID="${CURRENT_USER}.dialer"

echo "========================================================"
echo "    Omarchy SIP Softphone & Dialer Installation         "
echo "========================================================"
echo ""

# Parse CLI flags
SIP_SERVER=""
SIP_EXT=""
SIP_USER=""
SIP_PASS=""
SIP_PORT="5060"
SIP_TRANSPORT="udp"
STUN_SERVER=""
NON_INTERACTIVE=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --server) SIP_SERVER="$2"; shift ;;
        --extension|--ext) SIP_EXT="$2"; shift ;;
        --username|--user) SIP_USER="$2"; shift ;;
        --password|--pass) SIP_PASS="$2"; shift ;;
        --port) SIP_PORT="$2"; shift ;;
        --transport) SIP_TRANSPORT="$2"; shift ;;
        --stun) STUN_SERVER="$2"; shift ;;
        --non-interactive) NON_INTERACTIVE=true ;;
        --help|-h)
            echo "Usage: ./install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --server HOST        SIP server / PBX hostname or IP"
            echo "  --extension EXT      SIP extension number (e.g. 10)"
            echo "  --username USER      SIP authentication username"
            echo "  --password PASS      SIP authentication password"
            echo "  --port PORT          SIP port (default: 5060)"
            echo "  --transport PROTO    SIP transport (udp, tcp, tls; default: udp)"
            echo "  --stun SERVER        STUN server for NAT traversal (e.g. host:3478)"
            echo "  --non-interactive    Do not prompt interactively for missing fields"
            echo "  --help, -h           Show this help message"
            exit 0
            ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Check / Prompt for credentials
if [ -z "$SIP_SERVER" ]; then
    if [ "$NON_INTERACTIVE" = true ]; then
        echo "Error: --server is required in non-interactive mode." >&2
        exit 1
    fi
    read -rp "Enter SIP Server/PBX Host (e.g. pbx.example.com): " SIP_SERVER
fi

if [ -z "$SIP_EXT" ]; then
    if [ "$NON_INTERACTIVE" = true ]; then
        SIP_EXT="10"
    else
        read -rp "Enter SIP Extension Number (default: 10): " SIP_EXT
        SIP_EXT="${SIP_EXT:-10}"
    fi
fi

if [ -z "$SIP_USER" ]; then
    if [ "$NON_INTERACTIVE" = true ]; then
        SIP_USER="$SIP_EXT"
    else
        read -rp "Enter SIP Username / Auth ID (default: $SIP_EXT): " SIP_USER
        SIP_USER="${SIP_USER:-$SIP_EXT}"
    fi
fi

if [ -z "$SIP_PASS" ]; then
    if [ "$NON_INTERACTIVE" = true ]; then
        echo "Error: --password is required in non-interactive mode." >&2
        exit 1
    fi
    read -rsp "Enter SIP Password / Secret: " SIP_PASS
    echo ""
fi

if [ -z "$STUN_SERVER" ]; then
    if [ "$NON_INTERACTIVE" = false ]; then
        read -rp "Enter STUN server (leave empty to use ${SIP_SERVER}:3478): " STUN_INPUT
        if [ -n "$STUN_INPUT" ]; then
            STUN_SERVER="$STUN_INPUT"
        else
            STUN_SERVER="${SIP_SERVER}:3478"
        fi
    else
        STUN_SERVER="${SIP_SERVER}:3478"
    fi
fi

echo ""
echo "[-] Verifying system prerequisites..."

# Check dependencies
MISSING_PKGS=()
for pkg in baresip pipewire wireplumber jq python; do
    if ! command -v "$pkg" >/dev/null 2>&1; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo "[!] Missing packages: ${MISSING_PKGS[*]}"
    if command -v pacman >/dev/null 2>&1; then
        echo "[*] Installing missing dependencies via pacman..."
        sudo pacman -S --needed --noconfirm "${MISSING_PKGS[@]}" libpulse
    else
        echo "Please install ${MISSING_PKGS[*]} using your system package manager."
        exit 1
    fi
fi

echo "[+] Dependencies verified."

# 1. Install CLI binary
echo "[-] Installing omarchy-dialer CLI bridge to ~/.local/bin/..."
mkdir -p "$HOME/.local/bin"
cp "$SCRIPT_DIR/bin/omarchy-dialer" "$HOME/.local/bin/omarchy-dialer"
chmod +x "$HOME/.local/bin/omarchy-dialer"

# 2. Configure Baresip
echo "[-] Configuring Baresip engine in ~/.baresip/..."
mkdir -p "$HOME/.baresip"

# Copy config
cp "$SCRIPT_DIR/config/baresip.config.template" "$HOME/.baresip/config"

# Generate accounts config
MEDIANAT="none"
NATPINHOLE="no"
if [ -n "$STUN_SERVER" ]; then
    MEDIANAT="stun"
    NATPINHOLE="yes"
fi

sed \
    -e "s|{{USERNAME}}|$SIP_USER|g" \
    -e "s|{{SERVER}}|$SIP_SERVER|g" \
    -e "s|{{PASSWORD}}|$SIP_PASS|g" \
    -e "s|{{PORT}}|$SIP_PORT|g" \
    -e "s|{{TRANSPORT}}|$SIP_TRANSPORT|g" \
    -e "s|{{REGINT}}|60|g" \
    -e "s|{{MEDIANAT}}|$MEDIANAT|g" \
    -e "s|{{STUN_SERVER}}|$STUN_SERVER|g" \
    -e "s|{{NATPINHOLE}}|$NATPINHOLE|g" \
    "$SCRIPT_DIR/config/baresip.accounts.template" > "$HOME/.baresip/accounts"
chmod 600 "$HOME/.baresip/accounts"

# 3. Create ~/.config/omarchy/sip.json
echo "[-] Writing Omarchy SIP metadata to ~/.config/omarchy/sip.json..."
mkdir -p "$HOME/.config/omarchy"
cat <<EOF > "$HOME/.config/omarchy/sip.json"
{
  "extension": "$SIP_EXT",
  "username": "$SIP_USER",
  "server": "$SIP_SERVER",
  "port": $SIP_PORT,
  "transport": "$SIP_TRANSPORT",
  "stun_server": "$STUN_SERVER",
  "audio_input": "",
  "audio_output": ""
}
EOF
chmod 600 "$HOME/.config/omarchy/sip.json"

# 4. Install Quickshell plugin
TARGET_PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
echo "[-] Installing Quickshell widget to $TARGET_PLUGIN_DIR..."
mkdir -p "$TARGET_PLUGIN_DIR"
cp "$SCRIPT_DIR/plugin/BarWidget.qml" "$TARGET_PLUGIN_DIR/"
cp "$SCRIPT_DIR/plugin/Panel.qml" "$TARGET_PLUGIN_DIR/"

sed \
    -e "s|{{USER_PLUGIN_ID}}|$PLUGIN_ID|g" \
    -e "s|{{USER_NAME}}|$CURRENT_USER|g" \
    "$SCRIPT_DIR/plugin/manifest.json.template" > "$TARGET_PLUGIN_DIR/manifest.json"

# 5. Install systemd user services
echo "[-] Installing systemd user services..."
mkdir -p "$HOME/.config/systemd/user"
cp "$SCRIPT_DIR/services/baresip.service" "$HOME/.config/systemd/user/baresip.service"
cp "$SCRIPT_DIR/services/omarchy-dialer-monitor.service" "$HOME/.config/systemd/user/omarchy-dialer-monitor.service"

systemctl --user daemon-reload
systemctl --user enable --now baresip.service omarchy-dialer-monitor.service

# 6. Install desktop launcher
echo "[-] Installing desktop launcher entry..."
mkdir -p "$HOME/.local/share/applications"
sed -e "s|Exec=omarchy-dialer toggle|Exec=$HOME/.local/bin/omarchy-dialer toggle|g" \
    "$SCRIPT_DIR/services/omarchy-dialer.desktop" > "$HOME/.local/share/applications/omarchy-dialer.desktop"
chmod +x "$HOME/.local/share/applications/omarchy-dialer.desktop"

# 7. Check / Register in Omarchy top bar layout
SHELL_JSON="$HOME/.config/omarchy/shell.json"
if [ -f "$SHELL_JSON" ]; then
    if ! grep -q "$PLUGIN_ID" "$SHELL_JSON"; then
        echo "[*] Adding $PLUGIN_ID to Omarchy top bar (shell.json)..."
        # Insert into bar.layout.right (entries are {"id": ...} objects) if jq is available
        if command -v jq >/dev/null 2>&1; then
            if jq --arg pid "$PLUGIN_ID" '
                if .bar?.layout?.right then
                    .bar.layout.right = ([{id: $pid}] + (.bar.layout.right | map(select(.id != $pid))))
                else
                    error("no bar.layout.right in shell.json")
                end
            ' "$SHELL_JSON" > "${SHELL_JSON}.tmp"; then
                mv "${SHELL_JSON}.tmp" "$SHELL_JSON"
                echo "[+] Widget added to bar.layout.right."
            else
                rm -f "${SHELL_JSON}.tmp"
                echo "[!] Could not add widget to shell.json; add {\"id\": \"$PLUGIN_ID\"} to bar.layout.right manually."
            fi
        fi
    fi
fi

# 8. Check Hyprland keybinding
BINDINGS_LUA="$HOME/.config/hypr/bindings.lua"
if [ -f "$BINDINGS_LUA" ]; then
    if ! grep -q "omarchy-dialer toggle" "$BINDINGS_LUA"; then
        echo "[*] Tip: Add SUPER + ALT + P shortcut to $BINDINGS_LUA:"
        echo '    { "SUPER ALT", "P", "omarchy-dialer toggle", "SIP Softphone Dialer" },'
    fi
fi

echo ""
echo "========================================================"
echo "    Installation Complete!                              "
echo "========================================================"
echo ""
echo "Status check:"
sleep 1
"$HOME/.local/bin/omarchy-dialer" status || true
echo ""
echo "Use:"
echo "  - Super + Alt + P (or click 󰏲 on bar) to open the dialpad"
echo "  - In-app ' Audio' drawer to select your mic and headset"
echo "  - 'omarchy-dialer dial <number>' from any terminal"
echo ""
