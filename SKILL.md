---
name: omarchy-sip
description: >
  Install, configure, troubleshoot, and remove the SIP softphone dialer for Omarchy Linux:
  baresip engine, top-bar phone widget, dialer CLI, and keybinding.
  Use when the user wants to set up VoIP/SIP calling, a phone dialer or softphone on Omarchy,
  or to change SIP credentials, fix registration, or uninstall it.
  Triggers: SIP, VoIP, softphone, dialer, baresip, phone call, PBX, asterisk, freepbx,
  phone dialpad, omarchy-dialer.
---

# Omarchy SIP Dialer Skill

This skill installs and maintains the dialer by running the repository's own scripts.
`install.sh` does all the work. This file covers how to drive it, what it needs from the
user, and how to check that it worked. Do not rebuild its steps by hand.

Work from the repository root, the directory that contains `install.sh`.

---

## 1. Collect the SIP details first

Do not run anything until the user has given you these values. Never invent credentials.

| Value | Flag | Required | Default |
| :--- | :--- | :--- | :--- |
| PBX / SIP server host or IP | `--server` | yes | none |
| Extension | `--extension` | no | `10` |
| Auth username | `--username` | no | the extension |
| Password | `--password` | yes | none |
| Transport: udp, tcp, or tls | `--transport` | no | `udp` |
| Port | `--port` | no | `5060` |
| STUN server, host:port | `--stun` | no | `<server>:3478` |

Ask for the server, extension, username, password, and transport. Offer the STUN default.
If the user's PBX gives the port, ask for it too.

Two constraints to tell the user about:
- Passwords and other values cannot contain spaces, `;`, `<`, `>`, or double quotes. The
  installer rejects them.
- `--password` puts the secret in the shell history and the process list. If the user
  cares, have them run the installer themselves and type the password at the prompt.

---

## 2. Run the installer

Non-interactive, with the values the user gave:

```bash
./install.sh --non-interactive \
  --server pbx.example.com \
  --extension 10 \
  --username 10-12345 \
  --password 'THEIR_PASSWORD' \
  --transport tcp
```

Add `--stun host:port` only if the user gave one. Otherwise the installer uses `<server>:3478`.

What the installer does, so you can explain it:
1. Installs missing packages with `sudo pacman` (`baresip`, `libpulse`, `jq`, `python`).
2. Installs the `omarchy-dialer` CLI to `~/.local/bin/` and writes the baresip config to `~/.baresip/`.
3. Writes `~/.config/omarchy/sip.json` and the widget to `~/.config/omarchy/plugins/<user>.dialer/`.
4. Enables and restarts the `baresip` and `omarchy-dialer-monitor` user services.
5. Places the widget in the top bar with `omarchy-plugin-enable`, and adds `SUPER + ALT + P` to `~/.config/hypr/bindings.lua`.
6. Waits up to 20 seconds for PBX registration and reports the result.

It is safe to run again. It updates the settings and keeps the audio devices the user chose.

### sudo needs a real terminal

The `sudo pacman` step asks for the user's password. You cannot type it, and this session
has no terminal for it. If `baresip` is missing, the installer fails with
`sudo: a terminal is required`. Do not ask the user for their sudo password. Tell them to run
this in their own terminal, outside the agent session:

```bash
sudo pacman -S --needed baresip libpulse
```

Once it finishes, run the installer again. It skips packages that are already installed.

---

## 3. Verify

Run these and report the actual output:

1. `~/.local/bin/omarchy-dialer status`: expect `"registered": true` and `"state": "idle"`.
2. If registration is false, read the log with `journalctl --user -u baresip.service -n 50 --no-pager`.
   Common causes are a wrong password, wrong transport or port, or a server that is unreachable from the network.
3. `hyprctl binds | grep "SIP Softphone"`: the keybinding is loaded.
4. `jq '.bar.layout.right' ~/.config/omarchy/shell.json`: the list includes `<user>.dialer`.

The top-bar icon appears right after install. If it does not, have the user log out and back in.

Test a call only with the user's agreement. `omarchy-dialer dial <number>` places a real call.

---

## 4. Troubleshooting

- **Registered but no two-way audio (0 bit/s RX):** baresip loaded `account.so` before the
  NAT modules. The shipped `config/baresip.config.template` has the correct order
  (`stun.so`, `turn.so`, `ice.so` before `account.so`). If someone edited it, restore that order.
- **Widget missing from the bar:** run `omarchy-shell shell rescanPlugins`, then
  `omarchy-plugin-enable <user>.dialer right --index 0`. If that fails, run `omarchy-restart-shell`.
- **Plugin ID rule:** Omarchy rejects plugin IDs in the `omarchy.*` namespace. The installer uses `<user>.dialer`. Keep it that way.
- **Audio device names:** baresip uses the `pulse` driver. Do not pass `pulse,default`
  to `/ausrc` or `/auplay`. Use `pulse` alone, or the full PipeWire node name. The in-app
  Audio drawer and `omarchy-dialer set-device` handle this.

---

## 5. Uninstall

```bash
./uninstall.sh
```

It asks whether to delete the SIP settings. It leaves the pacman packages installed.
