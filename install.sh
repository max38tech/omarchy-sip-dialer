#!/usr/bin/env bash
#
# Omarchy SIP Softphone & Dialer Installer
# Installs baresip, writes your SIP account, and sets up the dialer CLI,
# the Quickshell top-bar widget, the background services, the keybinding,
# and the application launcher entry.
#
# Interactive by default. Use --non-interactive with the flags to script it.
#

set -euo pipefail

# Keep credential files private from the moment they are created.
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURRENT_USER="$(whoami)"
PLUGIN_ID="${CURRENT_USER}.dialer"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
SIP_JSON="$HOME/.config/omarchy/sip.json"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
BINDINGS_LUA="$HOME/.config/hypr/bindings.lua"
BIND_LINE='o.bind("SUPER + ALT + P", "SIP Softphone Dialer", "omarchy-dialer toggle")'

die() {
    echo "Error: $*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: ./install.sh [OPTIONS]

Run without options to be prompted for each value.

Options:
  --server HOST        SIP server / PBX hostname or IP
  --extension EXT      SIP extension number (default: 10)
  --username USER      SIP authentication username (default: the extension)
  --password PASS      SIP password. Prefer the prompt: flags show up in
                       shell history and in the process list.
  --port PORT          SIP port (default: 5060)
  --transport PROTO    udp, tcp, or tls (default: udp)
  --stun SERVER        STUN server, host:port (default: <server>:3478)
  --non-interactive    Never prompt. Missing required values are an error.
  --help, -h           Show this help message
EOF
}

SIP_SERVER=""
SIP_EXT=""
SIP_USER=""
SIP_PASS=""
SIP_PORT=""
SIP_TRANSPORT=""
STUN_SERVER=""
NON_INTERACTIVE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --server|--extension|--ext|--username|--user|--password|--pass|--port|--transport|--stun)
            [[ $# -ge 2 ]] || die "$1 needs a value"
            case $1 in
                --server) SIP_SERVER="$2" ;;
                --extension|--ext) SIP_EXT="$2" ;;
                --username|--user) SIP_USER="$2" ;;
                --password|--pass) SIP_PASS="$2" ;;
                --port) SIP_PORT="$2" ;;
                --transport) SIP_TRANSPORT="$2" ;;
                --stun) STUN_SERVER="$2" ;;
            esac
            shift
            ;;
        --non-interactive) NON_INTERACTIVE=true ;;
        --help|-h) usage; exit 0 ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
    shift
done

# ask VAR "Question" [default] [secret]
# Keeps a value already given by a flag. Otherwise prompts (interactive) or
# uses the default (non-interactive). Fails if the value is still empty.
ask() {
    local var="$1" question="$2" default="${3:-}" secret="${4:-}" answer=""

    [ -z "${!var}" ] || return 0

    if [ "$NON_INTERACTIVE" = true ]; then
        [ -n "$default" ] || die "$question is required (see --help)"
        printf -v "$var" '%s' "$default"
        return 0
    fi

    while :; do
        if [ "$secret" = secret ]; then
            read -rsp "$question: " answer
            echo ""
        elif [ -n "$default" ]; then
            read -rp "$question [$default]: " answer
        else
            read -rp "$question: " answer
        fi
        answer="${answer:-$default}"
        [ -n "$answer" ] && break
        echo "  A value is required."
    done
    printf -v "$var" '%s' "$answer"
}

# Values are written into baresip's account URI, where ; < > and quotes
# are structural characters. Refuse them rather than write a broken account.
check_value() {
    local name="$1" value="$2"
    case "$value" in
        *[';<>"'[:space:]]*) die "$name cannot contain spaces, ;, <, >, or double quotes" ;;
    esac
}

# Renders a {{KEY}} template: render SRC DST KEY=VALUE...
# Done in Python so values are inserted literally, with no sed escaping.
render() {
    local src="$1" dst="$2"
    shift 2
    python3 - "$src" "$dst" "$@" <<'PY'
import sys

src, dst, *pairs = sys.argv[1:]
with open(src, encoding="utf-8") as f:
    text = f.read()
for pair in pairs:
    key, value = pair.split("=", 1)
    text = text.replace("{{" + key + "}}", value)
with open(dst, "w", encoding="utf-8") as f:
    f.write(text)
PY
}

echo "========================================================"
echo "    Omarchy SIP Softphone & Dialer Installation         "
echo "========================================================"
echo ""

echo "[-] Checking prerequisites..."
if command -v pacman >/dev/null 2>&1; then
    MISSING_PKGS=()
    for pkg in baresip libpulse jq python; do
        pacman -Qq "$pkg" >/dev/null 2>&1 || MISSING_PKGS+=("$pkg")
    done
    if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
        echo "[*] Installing missing packages: ${MISSING_PKGS[*]}"
        echo "    (sudo will ask for your password)"
        sudo pacman -S --needed "${MISSING_PKGS[@]}" \
            || die "could not install ${MISSING_PKGS[*]}. Run: sudo pacman -S --needed ${MISSING_PKGS[*]}"
    fi
else
    for cmd in baresip jq python3; do
        command -v "$cmd" >/dev/null 2>&1 \
            || die "$cmd is not installed. Install baresip, libpulse, jq, and python with your package manager, then run this again."
    done
fi

for cmd in pipewire wireplumber quickshell; do
    command -v "$cmd" >/dev/null 2>&1 \
        || echo "[!] $cmd not found. The top-bar widget and audio routing need it (Omarchy normally installs it)."
done

systemctl --user show-environment >/dev/null 2>&1 \
    || die "no systemd user session. Run this from your Omarchy desktop session (not over plain SSH or sudo)."

echo "[+] Prerequisites OK."
echo ""

if [ "$NON_INTERACTIVE" = false ]; then
    echo "Enter your SIP account details. Press Enter to accept a default in [brackets]."
fi
ask SIP_SERVER "SIP server / PBX host (e.g. pbx.example.com)"
ask SIP_EXT "SIP extension number" "10"
ask SIP_USER "SIP username / auth ID" "$SIP_EXT"
ask SIP_PASS "SIP password" "" secret
ask SIP_TRANSPORT "Transport (udp, tcp, or tls)" "udp"
ask SIP_PORT "SIP port" "5060"
ask STUN_SERVER "STUN server (host:port, for NAT traversal)" "$SIP_SERVER:3478"

# Accept "stun:host:port" as well as "host:port".
STUN_SERVER="${STUN_SERVER#stun:}"

check_value "SIP server" "$SIP_SERVER"
check_value "extension" "$SIP_EXT"
check_value "username" "$SIP_USER"
check_value "password" "$SIP_PASS"
check_value "STUN server" "$STUN_SERVER"
[[ "$SIP_PORT" =~ ^[0-9]+$ ]] || die "port must be a number"
case "$SIP_TRANSPORT" in
    udp|tcp|tls) ;;
    *) die "transport must be udp, tcp, or tls" ;;
esac

echo ""
echo "[-] Installing the omarchy-dialer CLI to ~/.local/bin/..."
mkdir -p "$HOME/.local/bin"
install -m 755 "$SCRIPT_DIR/bin/omarchy-dialer" "$HOME/.local/bin/omarchy-dialer"

echo "[-] Configuring the Baresip engine in ~/.baresip/..."
mkdir -p "$HOME/.baresip"
install -m 644 "$SCRIPT_DIR/config/baresip.config.template" "$HOME/.baresip/config"
render "$SCRIPT_DIR/config/baresip.accounts.template" "$HOME/.baresip/accounts" \
    "USERNAME=$SIP_USER" \
    "SERVER=$SIP_SERVER" \
    "PASSWORD=$SIP_PASS" \
    "PORT=$SIP_PORT" \
    "TRANSPORT=$SIP_TRANSPORT" \
    "REGINT=60" \
    "MEDIANAT=stun" \
    "NATPINHOLE=yes" \
    "STUN_SERVER=$STUN_SERVER"
chmod 600 "$HOME/.baresip/accounts"

echo "[-] Writing SIP settings to $SIP_JSON..."
mkdir -p "$HOME/.config/omarchy"
# Keep audio devices picked in the app if this is a re-install.
OLD_INPUT=""
OLD_OUTPUT=""
if [ -f "$SIP_JSON" ]; then
    OLD_INPUT="$(jq -r '.audio_input // ""' "$SIP_JSON" 2>/dev/null || true)"
    OLD_OUTPUT="$(jq -r '.audio_output // ""' "$SIP_JSON" 2>/dev/null || true)"
fi
jq -n \
    --arg extension "$SIP_EXT" \
    --arg username "$SIP_USER" \
    --arg server "$SIP_SERVER" \
    --argjson port "$SIP_PORT" \
    --arg transport "$SIP_TRANSPORT" \
    --arg stun "$STUN_SERVER" \
    --arg input "$OLD_INPUT" \
    --arg output "$OLD_OUTPUT" \
    '{extension: $extension, username: $username, server: $server, port: $port,
      transport: $transport, stun_server: $stun, audio_input: $input, audio_output: $output}' \
    > "$SIP_JSON"
chmod 600 "$SIP_JSON"

echo "[-] Installing the Quickshell widget to $PLUGIN_DIR..."
mkdir -p "$PLUGIN_DIR"
install -m 644 "$SCRIPT_DIR/plugin/BarWidget.qml" "$SCRIPT_DIR/plugin/Panel.qml" "$PLUGIN_DIR/"
render "$SCRIPT_DIR/plugin/manifest.json.template" "$PLUGIN_DIR/manifest.json" \
    "USER_PLUGIN_ID=$PLUGIN_ID" \
    "USER_NAME=$CURRENT_USER"

echo "[-] Installing and starting the systemd user services..."
mkdir -p "$HOME/.config/systemd/user"
install -m 644 "$SCRIPT_DIR/services/baresip.service" "$HOME/.config/systemd/user/baresip.service"
install -m 644 "$SCRIPT_DIR/services/omarchy-dialer-monitor.service" "$HOME/.config/systemd/user/omarchy-dialer-monitor.service"
systemctl --user daemon-reload
systemctl --user enable baresip.service omarchy-dialer-monitor.service
# restart (not just enable --now) so a re-install picks up the new settings.
systemctl --user restart baresip.service omarchy-dialer-monitor.service

echo "[-] Installing the application launcher entry..."
mkdir -p "$HOME/.local/share/applications"
sed -e "s|Exec=omarchy-dialer toggle|Exec=$HOME/.local/bin/omarchy-dialer toggle|g" \
    "$SCRIPT_DIR/services/omarchy-dialer.desktop" > "$HOME/.local/share/applications/omarchy-dialer.desktop"
chmod 644 "$HOME/.local/share/applications/omarchy-dialer.desktop"

# Place the widget in the top bar's right-hand section.
echo "[-] Adding the widget to the top bar..."
if [ ! -f "$SHELL_JSON" ]; then
    echo "[!] $SHELL_JSON not found. Is this an Omarchy desktop? Skipping bar placement."
elif command -v omarchy-plugin-enable >/dev/null 2>&1 && command -v omarchy-shell >/dev/null 2>&1 \
    && { omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true; } \
    && omarchy-plugin-enable "$PLUGIN_ID" right --index 0 >/dev/null 2>&1; then
    echo "[+] Widget placed in the top bar."
elif jq -e '.bar.layout.right' "$SHELL_JSON" >/dev/null 2>&1; then
    # Shell not reachable: edit shell.json directly. It is read at shell start.
    jq --arg id "$PLUGIN_ID" '
        .bar.layout.right = ([{id: $id}] + (.bar.layout.right | map(select(.id != $id))))
    ' "$SHELL_JSON" > "${SHELL_JSON}.tmp" && mv "${SHELL_JSON}.tmp" "$SHELL_JSON"
    echo "[+] Widget added to shell.json. Run omarchy-restart-shell (or log out and back in) to show it."
else
    echo "[!] Could not find bar.layout.right in $SHELL_JSON. Add {\"id\": \"$PLUGIN_ID\"} to it by hand."
fi

echo "[-] Adding the keybinding (SUPER + ALT + P)..."
if [ ! -f "$BINDINGS_LUA" ]; then
    echo "[!] $BINDINGS_LUA not found. Add this line to your Hyprland bindings yourself:"
    echo "    $BIND_LINE"
elif grep -q "omarchy-dialer toggle" "$BINDINGS_LUA"; then
    echo "[+] Keybinding already present."
else
    printf '\n%s\n' "$BIND_LINE" >> "$BINDINGS_LUA"
    if command -v omarchy-restart-hyprctl >/dev/null 2>&1; then
        omarchy-restart-hyprctl >/dev/null 2>&1 || true
    fi
    echo "[+] Keybinding added."
fi

echo "[-] Checking registration with the PBX (up to 20 seconds)..."
REGISTERED=false
for _ in $(seq 1 20); do
    STATUS="$("$HOME/.local/bin/omarchy-dialer" status 2>/dev/null || true)"
    if [[ "$STATUS" == *'"registered": true'* ]]; then
        REGISTERED=true
        break
    fi
    sleep 1
done

echo ""
echo "========================================================"
if [ "$REGISTERED" = true ]; then
    echo "    Installation complete. Registered with $SIP_SERVER."
else
    echo "    Installed, but the PBX has not accepted registration yet."
fi
echo "========================================================"
echo ""
if [ "$REGISTERED" != true ]; then
    echo "Recent Baresip log:"
    journalctl --user -u baresip.service -n 15 --no-pager || true
    echo ""
    echo "Check the server, extension, username, password, and transport, then run:"
    echo "  $HOME/.local/bin/omarchy-dialer status"
    echo "  journalctl --user -u baresip.service -n 50 --no-pager"
    echo ""
fi
echo "Use it:"
echo "  - Super + Alt + P, or click the phone icon in the top bar, to open the dialpad"
echo "  - The Audio drawer in the panel picks your microphone and speaker"
echo "  - omarchy-dialer dial <number> from any terminal"
echo ""
