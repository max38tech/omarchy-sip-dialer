# Omarchy SIP Softphone & Dialer 󰏲

A native SIP softphone, Quickshell top-bar widget, and PipeWire audio device manager for [Omarchy Linux](https://omarchy.org/) (Arch Linux + Hyprland).

Powered by the [`baresip`](https://github.com/baresip/baresip) SIP engine, with STUN/NAT traversal, PipeWire audio routing, incoming call notifications, and an in-app audio device drawer.

---

## Features

- 󰏲 **Top bar widget**: a phone icon in the Omarchy status bar. It shows registration status, flashes on incoming calls, and turns green during a call.
- ⌨ **Dialpad & panel**: open with `SUPER + ALT + P` or by clicking the icon. Includes a 3x4 keypad, DTMF during calls, a live call timer, and recent calls.
- 🎚 **Audio device drawer**: switch microphones and speakers without leaving the dialer. Includes a test chime and a microphone boost.
- 🌐 **NAT traversal**: STUN and NAT pinhole keepalive, which prevents the one-way or no-audio problem behind home routers and CGNAT.
- 🔔 **Call monitor**: a background service announces incoming calls with desktop notifications and answer buttons.
- 💻 **CLI**: `omarchy-dialer` with `dial`, `hangup`, `answer`, `dtmf`, `status`, `devices`, `set-device`, `test-audio`, `logs`, and `monitor`.
- 📜 **Live logs and call errors**: a log drawer in the panel, and a banner that explains failed calls (404, busy, and similar).

---

## Requirements

- Omarchy (Arch Linux with Hyprland and the Omarchy shell). The installer uses `pacman`.
- A SIP account: PBX or SIP provider hostname, extension, username, and password.
- A normal desktop login with a systemd user session. Run the installer from the desktop, not over plain SSH.

The installer installs `baresip`, `libpulse`, `jq`, and `python` if they're missing. PipeWire, WirePlumber, and Quickshell come with Omarchy.

---

## Install

Choose one of two ways. Both run the same `install.sh`.

### Option A: Installer (no AI agent)

```bash
git clone https://github.com/max38tech/omarchy-sip-dialer.git
cd omarchy-sip-dialer
./install.sh
```

The installer asks for each value. Press Enter to accept a default in `[brackets]`:

1. PBX / SIP server host (required)
2. Extension (default `10`)
3. Username (default: the extension)
4. Password (typed in without echoing)
5. Transport: `udp`, `tcp`, or `tls` (default `udp`)
6. Port (default `5060`)
7. STUN server (default `<server>:3478`)

When it finishes, it prints whether the PBX accepted registration. If it did not, the output shows the relevant log lines.

**sudo:** the installer runs `sudo pacman` if packages are missing, so run it in a terminal where you can type your password.

To script the install, give the values as flags and add `--non-interactive`:

```bash
./install.sh --non-interactive \
  --server pbx.example.com \
  --extension 100 \
  --username 100-user \
  --password 'YourSecretPass' \
  --transport tcp \
  --stun stun.example.com:3478
```

Run `./install.sh --help` for all options.

Values can't contain spaces, `;`, `<`, `>`, or double quotes. The installer rejects them, since baresip reads those characters as part of the account address.

Passing `--password` on the command line leaves it in your shell history and visible in the process list. Use the prompt if that matters.

### Option B: AI agent (`SKILL.md`)

The skill tells an AI coding agent to collect the SIP details, run `install.sh`, and check registration. It also covers the sudo step and troubleshooting. It is useful if you already work with an agent and want it to handle the setup.

1. Copy the skill to your agent's skills folder:
   ```bash
   mkdir -p ~/.agents/skills/omarchy-sip
   cp SKILL.md ~/.agents/skills/omarchy-sip/SKILL.md
   ```
2. Ask your agent: *"Set up the Omarchy SIP dialer on my system."*
3. The agent asks for your SIP details, runs the installer, and reports the registration result.

---

## After installing

- **Open the dialpad:** `SUPER + ALT + P`, or click the phone icon in the top bar.
- **Pick your microphone and speaker:** open the Audio drawer in the panel.
- **Dial from a terminal:** `omarchy-dialer dial <number>`.
- **Check registration:** `omarchy-dialer status`.

If the top-bar icon doesn't show, run `omarchy-restart-shell`, or log out and back in.

### Keybindings & commands

| Action | Shortcut / Command |
| :--- | :--- |
| **Toggle dialpad** | `SUPER + ALT + P`, or click the top-bar icon |
| **Hang up active call** | Right-click the top-bar icon |
| **Dial from CLI** | `omarchy-dialer dial <number>` |
| **Hang up from CLI** | `omarchy-dialer hangup` |
| **Check registration** | `omarchy-dialer status` |
| **View engine logs** | `omarchy-dialer logs [-n 50]` |
| **List audio devices** | `omarchy-dialer devices` |
| **Switch output device** | `omarchy-dialer set-device --output "<device-name>"` |
| **Switch input device** | `omarchy-dialer set-device --input "<device-name>"` |

The keybinding is in `~/.config/hypr/bindings.lua`. Change or remove it there.

---

## Uninstall

```bash
./uninstall.sh
```

This stops the services and removes the CLI, widget, launcher entry, top-bar placement, and keybinding. It asks before deleting your SIP settings. It leaves the pacman packages installed.

---

## Troubleshooting

- **Not registered:** `omarchy-dialer status`, then `journalctl --user -u baresip.service -n 50 --no-pager`. Check the password, transport, and port first.
- **Connected but no audio (`0 bit/s RX`):** the NAT modules must load before `account.so`. The shipped config already does this. Don't reorder `config/baresip.config.template`.
- **Widget not in the bar:** run `omarchy-shell shell rescanPlugins`, then `omarchy-plugin-enable <user>.dialer right --index 0`.
- **Re-running the installer:** safe. It updates your settings and keeps the audio devices you picked.

---

## Development notes

- `install.sh` is the source of truth for setup. The skill calls it rather than repeating its steps.
- Omarchy plugin IDs can't use the `omarchy.*` namespace, so the widget is installed as `<user>.dialer`.

---

## License

MIT License. See [LICENSE](LICENSE) for details.
