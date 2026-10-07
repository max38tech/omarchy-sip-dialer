---
name: omarchy-sip
description: >
  Install, configure, and maintain the native SIP softphone dialer, quicklaunch bar widget,
  and audio manager for Omarchy Linux.
  Use when the user wants to set up VoIP/SIP calling, phone dialer, softphone, baresip,
  or manage SIP credentials and audio devices in Omarchy.
  Triggers: SIP, VoIP, softphone, dialer, baresip, phone call, PBX, asterisk,
  freepbx, audio device selector, phone dialpad.
---

# Omarchy SIP Softphone & Dialer Skill

This skill provides complete instructions for autonomous AI agents to set up, configure, and troubleshoot the native SIP softphone client, Quickshell top-bar widget, and PipeWire audio manager on Omarchy Linux.

---

## 1. MANDATORY INTERACTIVE DISCOVERY (DO THIS FIRST)

> [!IMPORTANT]
> **NEVER generate dummy credentials or proceed with installation without user input.**
> Before executing ANY installation commands or writing configuration files, you **MUST** prompt the user for their SIP account and PBX details:

Ask the user for:
1. **SIP Server / Hostname**: The PBX or SIP provider domain or IP (e.g., `pbx.example.com`, `192.168.1.100`).
2. **SIP Extension**: The user's internal extension number (e.g., `10`, `1001`).
3. **SIP Username / Auth ID**: Authentication ID (often `ext-account` or matching extension).
4. **SIP Password / Secret**: SIP secret for registration.
5. **STUN Server** *(Optional)*: Recommended for NAT traversal. Usually `<server>:3478` or `stun.l.google.com:19302`.
6. **Transport & Port** *(Optional)*: UDP, TCP, or TLS (default: UDP port 5060).

---

## 2. CRITICAL TECHNICAL ARCHITECTURE & GOTCHAS

When setting up or debugging baresip on Omarchy, keep these proven lessons in mind:

### A. Module Load Order (NAT / Two-Way Audio Silence)
- In `~/.baresip/config`, `stun.so`, `turn.so`, and `ice.so` **MUST** be loaded **BEFORE** `account.so`.
- If loaded after `account.so`, baresip logs `account: medianat not found: 'stun'`, ignores STUN, and places private LAN IPs (`192.168.x.x`) into the SDP session. This causes **total silence (0 bit/s RX)** because the remote RTP media cannot traverse NAT.

### B. Omarchy Plugin Namespace Rule
- Omarchy's plugin validator (`omarchy-plugin-validate`) **forbids** user plugins from using the `omarchy.*` ID namespace.
- You **MUST** use `<username>.dialer` (e.g. `user.dialer`) or a custom prefix like `custom.dialer`.

### C. PipeWire & Audio Device Naming
- Baresip uses the `pulse` audio driver to route through PipeWire.
- Never pass `pulse,default` to `/ausrc` or `/auplay`; pass either `pulse` (omitting device to use current default) or the full ALSA node name (e.g. `pulse,alsa_output.pci-0000_00_1f.3.analog-stereo`).

---

## 3. STEP-BY-STEP IMPLEMENTATION PROCEDURE

Once the user provides credentials, perform the following steps:

### Step 1: Install System Packages
Ensure packages are installed via pacman:
```bash
sudo pacman -S --needed baresip libpulse pipewire wireplumber jq python
```

### Step 2: Configure Baresip Engine
Create `~/.baresip/config`:
```text
sip_listen          0.0.0.0:0
sip_cafile          /etc/ssl/certs/ca-certificates.crt
sip_capath          /etc/ssl/certs
sip_tos             160

call_local_timeout  120
call_max_calls      4
call_hold_other_calls yes
call_accept         no

audio_player        pulse
audio_source        pulse
audio_alert         pulse
ausrc_format        s16
auplay_format       s16
auenc_format        s16
audec_format        s16
audio_buffer        20-160
audio_telev_pt      101

rtp_tos             184
audio_jitter_buffer_type    fixed
audio_jitter_buffer_ms      100-200
audio_jitter_buffer_size    50

module_path         /usr/lib/baresip/modules

# CRITICAL: STUN loaded before account.so
module              stun.so
module              turn.so
module              ice.so

module              account.so
module              contact.so
module              menu.so
module              ctrl_tcp.so
ctrl_tcp_listen     127.0.0.1:4444

module              pulse.so

module              opus.so
module              g711.so
module              g722.so
module              in_band_dtmf.so
```

Create `~/.baresip/accounts` (chmod 600):
```text
<sip:USERNAME@SERVER:PORT;transport=TRANSPORT>;auth_user=USERNAME;auth_pass=PASSWORD;regint=60;medianat=stun;stunserver="stun:STUN_SERVER";natpinhole=yes;dtmfmode=rtpevent
```
*(If STUN is not used, omit `medianat`, `stunserver`, and `natpinhole`).*

### Step 3: Write Metadata File
Save `~/.config/omarchy/sip.json` (chmod 600) with:
```json
{
  "extension": "<EXT>",
  "username": "<USERNAME>",
  "server": "<SERVER>",
  "port": 5060,
  "transport": "udp",
  "stun_server": "<STUN_SERVER>",
  "audio_input": "",
  "audio_output": ""
}
```

### Step 4: Install omarchy-dialer CLI Bridge
Deploy the Python control bridge to `~/.local/bin/omarchy-dialer` and ensure it is executable (`chmod +x`).

Test command:
```bash
omarchy-dialer devices
```

### Step 5: Install Quickshell Bar Widget & Panel
Create `~/.config/omarchy/plugins/<username>.dialer/` containing:
- `manifest.json`:
  ```json
  {
    "schemaVersion": 1,
    "id": "<username>.dialer",
    "name": "Phone / Dialer",
    "version": "1.0.0",
    "author": "<username>",
    "description": "SIP softphone and dialer panel",
    "kinds": ["bar-widget"],
    "entryPoints": {
      "barWidget": "BarWidget.qml"
    },
    "barWidget": {
      "displayName": "Phone / Dialer",
      "description": "SIP softphone and dialer",
      "category": "Communication",
      "allowMultiple": false
    }
  }
  ```
- `BarWidget.qml`: Status bar icon (`󰏲`) with active call badge and tooltip.
- `Panel.qml`: 3x4 dialpad, live call timer, call/end buttons, recent calls, and collapsible ` Audio` device drawer.

### Step 6: Enable Background Services
Deploy user systemd service units:
- `~/.config/systemd/user/baresip.service`:
  ```ini
  [Unit]
  Description=Baresip SIP Daemon for Omarchy
  After=pipewire.service pipewire-pulse.service network-online.target
  Wants=network-online.target

  [Service]
  Type=simple
  ExecStart=/usr/bin/baresip -f %h/.baresip
  Restart=always
  RestartSec=3

  [Install]
  WantedBy=default.target
  ```

- `~/.config/systemd/user/omarchy-dialer-monitor.service`:
  ```ini
  [Unit]
  Description=Omarchy SIP Dialer Incoming Call Monitor
  After=baresip.service
  Wants=baresip.service

  [Service]
  Type=simple
  ExecStart=%h/.local/bin/omarchy-dialer monitor
  Restart=always
  RestartSec=3

  [Install]
  WantedBy=default.target
  ```

Reload and start:
```bash
systemctl --user daemon-reload
systemctl --user enable --now baresip.service omarchy-dialer-monitor.service
```

### Step 7: Add to Status Bar & Keybindings
1. Edit `~/.config/omarchy/shell.json` to insert `"<username>.dialer"` into `layout.primary.right`.
2. Add Hyprland keybinding to `~/.config/hypr/bindings.lua`:
   ```lua
   { "SUPER ALT", "P", "omarchy-dialer toggle", "SIP Softphone Dialer" },
   ```
3. Create `~/.local/share/applications/omarchy-dialer.desktop` for application launchers.
4. Refresh Omarchy bar:
   ```bash
   omarchy-shell shell restart
   ```

---

## 4. VERIFICATION & VALIDATION

Verify that the dialer is operating properly:
1. **Check Registration**: Run `omarchy-dialer status`. Output should show `"registered": true` and `"state": "idle"`.
2. **Check Audio Devices**: Run `omarchy-dialer devices`. Output should list all PipeWire input and output devices.
3. **Test Sound**: Run `omarchy-dialer test-audio` to play a test chime through the speakers.
4. **Test Outbound Call**: Run `omarchy-dialer dial <number>`.
5. **Verify Audio Statistics**: In baresip logs (`journalctl --user -u baresip -n 30`), check that RTP transmission (`RX` and `TX`) shows active bitrates (e.g., `RX = 64.0 / TX = 64.0 kbit/s`), confirming full two-way NAT traversal.
