# Omarchy SIP Softphone & Dialer 󰏲

A native, elegant SIP VoIP softphone dialer, Quickshell status bar widget, and PipeWire audio device manager tailored for [Omarchy Linux](https://omarchy.org/) (Arch Linux + Hyprland).

Powered by the robust, low-latency [`baresip`](https://github.com/baresip/baresip) SIP engine with full STUN/NAT traversal, native PipeWire integration, incoming call notifications, and an in-app audio device selector drawer.

---

## Features

- 󰏲 **Top Bar Quicklaunch Widget**: Live connection status badge (`󰏲`) in the Omarchy status bar, flashing on incoming calls and glowing green during conversations.
- ⌨ **Interactive Dialpad & Panel**: Accessible via shortcut `SUPER + ALT + P` or top bar click. Full 3x4 telephone keypad, DTMF digit sending during calls, live call timers, and recent call history.
-  **In-App Audio Device Drawer**: Dynamically view and switch active microphones and headsets/speakers on the fly using PipeWire/PulseAudio without leaving the dialer. Includes a 1-click audio chime test and mic volume booster (`80%`).
- 🌐 **Bulletproof NAT Traversal**: Pre-configured STUN and NAT pinhole keepalive support, preventing the classic "one-way / no audio" issue behind consumer routers and CGNAT.
- 🔔 **Desktop Notifications & Call Monitor**: Background event monitor (`omarchy-dialer-monitor.service`) announces incoming calls with desktop notifications and 1-click answer actions.
- 💻 **CLI & Scripting Bridge**: Command-line control via `omarchy-dialer` (`dial`, `hangup`, `answer`, `dtmf`, `status`, `devices`, `set-device`, `test-audio`).
- 🤖 **AI Agent Ready**: Comes with an autonomous agent skill (`SKILL.md`) allowing AI coding assistants to install and configure everything interactively.

---

## Quick Start (Interactive Installer)

Clone the repository and run the automated installer:

```bash
git clone https://github.com/max38tech/omarchy-sip-dialer.git
cd omarchy-sip-dialer
./install.sh
```

The installer will:
1. Verify system dependencies (`baresip`, `pipewire`, `wireplumber`, `quickshell`, `jq`).
2. Prompt for your SIP account details (server, extension, username, password, STUN server).
3. Generate sanitized configurations in `~/.baresip/` and `~/.config/omarchy/sip.json`.
4. Deploy the Quickshell bar widget to `~/.config/omarchy/plugins/<user>.dialer`.
5. Install and enable background user systemd services (`baresip.service`, `omarchy-dialer-monitor.service`).
6. Register the top bar widget in `~/.config/omarchy/shell.json`.

### Non-Interactive / Scripted Installation

You can also pass credentials directly via flags:

```bash
./install.sh \
  --server pbx.example.com \
  --extension 100 \
  --username 100-user \
  --password "YourSecretPass" \
  --stun "stun:stun.l.google.com:19302" \
  --non-interactive
```

---

## AI Agent Installation (`SKILL.md`)

If you use AI coding assistants (e.g. Antigravity, Claude Code, Cursor, Codex):

1. Copy `SKILL.md` to your agent skills folder:
   ```bash
   cp SKILL.md ~/.agents/skills/omarchy-sip/SKILL.md
   ```
2. Prompt your agent:
   > *"Set up the Omarchy SIP dialer on my system."*
3. The agent will follow `SKILL.md`, interview you for your SIP account credentials, and handle the entire setup automatically!

---

## Keybindings & Usage

| Action | Shortcut / Command |
| :--- | :--- |
| **Toggle Dialpad** | `SUPER + ALT + P` (or left-click top bar icon `󰏲`) |
| **Hangup Active Call** | Right-click top bar icon `󰏲` |
| **Dial Number via CLI** | `omarchy-dialer dial <number>` |
| **Hangup via CLI** | `omarchy-dialer hangup` |
| **Check Registration** | `omarchy-dialer status` |
| **View Engine Logs** | `omarchy-dialer logs [-n 50]` |
| **List Audio Devices** | `omarchy-dialer devices` |
| **Switch Output Device** | `omarchy-dialer set-device --output "<device-name>"` |
| **Switch Input Device** | `omarchy-dialer set-device --input "<device-name>"` |

---

## In-App Drawers: Audio & Live Logs

Inside the dialer panel:
- **📜 Live Logs Drawer**: Click the scroll icon in the header to view live Baresip SIP engine events, connection attempts, error reasons, and SDP negotiation. Includes a 1-click refresh button.
- ** Audio Device Drawer**: Click the gear icon to switch microphones and speakers dynamically, test playback chime, and boost microphone volume to 80%.
- **Step-by-Step Call State Banner**: Whenever a call fails (e.g. 404, busy, or truncated URI), an alert banner immediately shows the exact reason with a 1-click shortcut to view the logs.

---

## Critical Technical Gotchas

### STUN Module Ordering (No Audio / Private LAN IP in SDP)
In `~/.baresip/config`, `stun.so`, `turn.so`, and `ice.so` **must** be loaded *before* `account.so`. If loaded after, baresip drops STUN and advertises private LAN IPs (`192.168.x.x`) to the PBX, causing remote RTP packets to fail to route (resulting in `0 bit/s RX`). This repository's templates already configure the exact correct ordering.

### Omarchy Plugin Namespace Rule
Omarchy's plugin validator (`omarchy-plugin-validate`) disallows third-party plugins from using the `omarchy.*` ID namespace. The installer dynamically namespaces the plugin as `<username>.dialer`.

---

## Uninstallation

To cleanly remove the dialer and background services:

```bash
./uninstall.sh
```

---

## License

MIT License. See [LICENSE](LICENSE) for details.
