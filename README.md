# AgentWatch

**Apple Watch / Android notifications for Claude Code and AI agent workflows.**

AgentWatch lets you walk away from your Mac (or Windows PC) while Claude Code works. When the agent needs your approval, needs attention, or finishes a task — your wrist vibrates with a short event card. Works with Apple Watch, Android phones, and connected bands (Huawei/Xiaomi/Samsung bands that sync phone notifications).

> 中文用户请查看 [README_CN.md](README_CN.md)

---

## Table of Contents

1. [Why AgentWatch?](#why-agentwatch)
2. [Screenshots](#screenshots)
3. [Features](#features)
4. [How It Works](#how-it-works)
5. [Installation Methods](#installation-methods)
6. [Quick Start: macOS](#quick-start-macos)
7. [Quick Start: Windows](#quick-start-windows)
8. [Bark Setup](#bark-setup)
9. [Claude Code Hooks](#claude-code-hooks)
10. [Notification Policy](#notification-policy)
11. [Persona Themes](#persona-themes)
12. [macOS Menu Bar App](#macos-menu-bar-app)
13. [Windows Tray App](#windows-tray-app)
14. [Common Commands](#common-commands)
15. [Testing](#testing)
16. [Troubleshooting](#troubleshooting)
17. [Privacy & Security](#privacy--security)
18. [Roadmap](#roadmap)
19. [License](#license)
20. [Contributing](#contributing)

---

## Why AgentWatch?

Claude Code is powerful — but you don't want to watch every command. You only need to know when:
- A real "Allow this bash command?" permission dialog appears
- The agent needs your approval or input
- A task finishes and needs your review
- Something went wrong that requires your attention

**The problem**: You start a long task, walk away for coffee, come back 20 minutes later and realize Claude Code has been waiting on a permission prompt for 19 of those minutes.

**The solution**: AgentWatch hooks into Claude Code's event system, filters out the noise, and pushes only truly actionable alerts to your wrist. Your watch vibrates → you glance → you know whether to rush back or stay at the coffee machine.

### What separates AgentWatch from other solutions?

| | AgentWatch | Terminal bell | Claude Code mobile push |
|---|---|---|---|
| Works when you're away from desk | ✅ | ❌ (out of earshot) | ✅ |
| No subscription | ✅ | ✅ | ❌ (requires paid plan) |
| Filters noise automatically | ✅ | ❌ | ❌ |
| Watch vibration + event card | ✅ | ❌ | ❌ |
| Persona themes | ✅ | ❌ | ❌ |
| macOS menu bar + Windows tray | ✅ | ❌ | ❌ |
| Open source | ✅ | N/A | N/A |

---

## Screenshots

*(Coming soon via GitHub Releases — screenshots will be added here.)*

**macOS menu bar app**: Status at a glance — Bark OK, hooks installed, persona theme, recent events.

**Windows tray app**: Right-click for full status, persona switching, test push, task boundaries.

**Apple Watch / Android band notification**: Title + risk level + suggested action in a compact card format.

**Phone notification**: Same card syncs to Notification Center.

---

## Features

### Core

| Feature | Description |
|---------|-------------|
| **Apple Watch / Android notifications** | Via [Bark](https://apps.apple.com/app/bark/id1403753865) (free, iOS & Android) |
| **PermissionRequest hook** | Reliable signal for real "Allow this bash command?" dialogs |
| **PermissionDenied hook** | Logs when you explicitly deny an operation |
| **Actionable notification mode** | Only pushes when user interaction is genuinely needed |
| **Stop hook** | Task completion reminders when Claude stops |
| **PreToolUse timeout log-only** | Detects possible permission waits without false alerts from slow builds |
| **Persona Themes** | Six fun notification styles |
| **Task boundaries** | Set allowed/forbidden paths; drift is logged silently, not pushed |
| **Local-first** | No extra LLM calls, no analytics, no cloud beyond Bark |

### Desktop Apps

| Platform | App | Tech |
|----------|-----|------|
| macOS | Menu bar app (no Dock icon) | Swift + AppKit |
| Windows | System tray app | C# / .NET 8 WinForms |
| CLI | Cross-platform terminal | Python 3.10+, zero extra deps |

### Persona Themes

| Theme | Key | Style |
|-------|-----|-------|
| Off | `off` | Default AgentWatch text |
| 总裁版 | `boss` | Dramatic CEO alerts |
| 少爷版 | `heir_male` | Estate manager reports |
| 大小姐版 | `heir_female` | Estate manager reports |
| 皇上版 | `emperor` | Imperial court style |
| 甄嬛版 | `palace` | Palace intrigue style |

---

## How It Works

```
Claude Code hooks           AgentWatch Python CLI
─────────────────         ─────────────────────────
PreToolUse         ──▶     danger / drift detection
PostToolUse        ──▶     failure counting
Notification      ──▶     attention classification
Stop              ──▶     task completion
PermissionRequest ──▶     ✓ PUSH to Watch (reliable)
PermissionDenied  ──▶     log only (no push)
                           │
                           ├── notification policy (actionable by default)
                           ├── persona message builder
                           ├── Bark push ──▶ phone ──▶ Apple Watch / Android band
                           └── logs/agentwatch_events.jsonl
```

**Key design decisions:**
- `PermissionRequest` is the **most reliable** signal for real "Allow this command?" prompts. It fires exactly when the Claude Code permission dialog appears.
- `Notification` is a fallback for general attention events.
- `Stop` handles task completion.
- `PreToolUse` timeout defaults to **log-only** — a 4-second gap between PreToolUse and PostToolUse could just be a slow Bash command, not a permission prompt.

---

## Installation Methods

You have three options, from simplest to most advanced:

### Option 1 — CLI Only (fastest)

No GUI apps needed. The core functionality (hooks → watch notifications) works entirely via CLI. Install Python, clone the repo, `pip install -e .`, configure Bark, install hooks. Done. See [Quick Start](#quick-start-macos).

**This is all you need for notifications to work.** The GUI apps are convenience layers.

### Option 2 — Download Pre-Built Apps (recommended)

| Platform | Download | Size |
|----------|----------|------|
| macOS (Apple Silicon) | [AgentWatch-macOS-arm64.zip](https://github.com/dongxutang918-afk/agentwatch/releases/download/v0.8.0/AgentWatch-macOS-arm64.zip) | 42 KB |
| Windows (x64) | [AgentWatch-Windows-x64.zip](https://github.com/dongxutang918-afk/agentwatch/releases/download/v0.8.0/AgentWatch-Windows-x64.zip) | 96 KB |

Download, unzip, double-click. No terminal needed.

**macOS:**
1. Double-click `AgentWatch.app` (menu bar top-right, no Dock icon)
2. `● AW` → `Add / Update Bark Key...` → paste your Bark key
3. `● AW` → `Test Push` → verify your watch receives it

**Windows:**
1. Double-click `AgentWatchTray.exe` (system tray bottom-right)
2. First run picks project directory (auto-remembered)
3. Right-click → **Setup Python Environment** (auto-prompted if .venv missing)
4. Right-click → **Add / Update Bark Key...** → paste your Bark key
5. Right-click → **Install / Update Claude Code Hooks** (one click)

Done. The app and hooks run independently — close the app, notifications still fire.

### Option 3 — CLI + Build from Source

Clone the repo and build the desktop apps yourself with a single command (requires Xcode Command Line Tools / .NET 8 SDK).

---

## Quick Start: macOS

### Prerequisites
- macOS (Apple Silicon or Intel)
- Python 3.10+
- Claude Code (CLI or VS Code extension)
- iPhone / Android phone with [Bark](https://apps.apple.com/app/bark/id1403753865) installed

### Install

```bash
# Clone
git clone https://github.com/dongxutang918-afk/agentwatch.git ~/Projects/agentwatch
cd ~/Projects/agentwatch

# Setup Python environment
python3 -m venv .venv
source .venv/bin/activate
pip install -e .

# Initialize (creates config and logs directory)
agentwatch init

# Configure Bark key
agentwatch config bark        # paste your Bark URL or key
agentwatch config test        # verify notifications reach your watch

# Install hooks for Claude / Grok / Codex / Gemini (manual, one-time)
agentwatch hooks install
# Or Claude-only (legacy): bash install_claude_hooks.sh

# Verify
agentwatch doctor             # should show hooks Installed per detected agent
```

### Optional: Build macOS Menu Bar App

```bash
bash macos/build_app.sh       # requires Xcode Command Line Tools (swift)
open build/AgentWatch.app     # runs in menu bar, no Dock icon
```

Double-click alternatives (no terminal needed):
- `AgentWatch Setup.command` — first-time environment setup
- `AgentWatch.command` — everyday launcher
- `Open AgentWatch App.command` — launch the menu bar app

---

## Quick Start: Windows

### Prerequisites
- Windows 10/11
- Python 3.10+
- Claude Code (CLI or VS Code extension)
- Phone with [Bark](https://apps.apple.com/app/bark/id1403753865) installed (iOS/Android)

### Install

**Recommended (download + run):**

1. Download [AgentWatch-Windows-x64.zip](https://github.com/dongxutang918-afk/agentwatch/releases/download/v0.8.0/AgentWatch-Windows-x64.zip)
2. Unzip anywhere
3. Double-click `AgentWatchTray.exe`
4. If asked, select your AgentWatch project directory (e.g. `C:\Users\dongx\agentwatch`)
5. Right-click the tray icon → **Setup Python Environment** (one-click)
6. Right-click the tray icon → **Add / Update Bark Key...** → paste your Bark key
7. Right-click the tray icon → **Install / Update Claude Code Hooks** (one-click)

Done. The tray app shows status, and hooks work independently in the background.

**Manual Setup (CLI):**

```powershell
# Clone
git clone https://github.com/dongxutang918-afk/agentwatch.git
cd agentwatch

# Setup
powershell -ExecutionPolicy Bypass -File windows\setup_windows.ps1

# Configure
.\.venv\Scripts\agentwatch.exe config bark
.\.venv\Scripts\agentwatch.exe config test

# Hooks (or use tray menu: "Install / Update Claude Code Hooks")
powershell -ExecutionPolicy Bypass -File windows\install_claude_hooks_windows.ps1

# Verify
.\.venv\Scripts\agentwatch.exe doctor
```

### Optional: Build from Source

```powershell
# Requires .NET 8 SDK
powershell -ExecutionPolicy Bypass -File windows\build_app.ps1
build\windows\AgentWatchTray\AgentWatchTray.exe
```

Or double-click `Open AgentWatch Windows App.bat`.

---

## Bark Setup

AgentWatch sends notifications through [Bark](https://apps.apple.com/app/bark/id1403753865), a free open-source push app for iOS and Android.

### Step-by-Step

1. **Install Bark** from the App Store (iOS) or Google Play (Android)
2. **Open Bark** → the URL at the top shows your key:
   ```
   https://api.day.app/YOUR_KEY/
                          ^^^^^^^^ this is your Bark key
   ```
3. **Copy** the full URL or just the key part
4. **Paste** it into AgentWatch:

   | Method | How |
   |--------|-----|
   | CLI | `agentwatch config bark` then paste |
   | macOS menu bar | `● AW` → `Add / Update Bark Key...` → paste |
   | Windows tray | Right-click → `Add / Update Bark Key...` → paste |

5. **Test**: `agentwatch config test` (or click "Test Push" in the GUI)

You should receive "AgentWatch Bark 测试" on your phone and wearable device.

### Verify Phone & Wearable Sync
- iPhone: Settings → Notifications → Bark → Allow ✅
- Android: Settings → Notifications → Bark → Allow ✅
- Apple Watch: Watch app → Notifications → Mirror iPhone Alerts from Bark ✅
- Android band/watch (Huawei/Xiaomi/Samsung): enable Bark notification sync in your companion app (e.g., Huawei Health, Mi Fitness, Galaxy Wearable)

---

## Agent Hooks (Claude / Grok / Codex / Gemini)

Hooks are **manual, opt-in** — AgentWatch never rewrites your CLI configs unless you run the installer. Backups are created before modification. Notification titles are prefixed with the source agent, e.g. `[Grok] 任务完成`.

### Supported agents

| Agent | Config written by installer | Core events |
|-------|----------------------------|-------------|
| **Claude Code** | `~/.claude/settings.json` | PreToolUse, PostToolUse, Notification, Stop, PermissionRequest, PermissionDenied |
| **Grok Build** | `~/.grok/hooks/agentwatch.json` | PreToolUse, PostToolUse, Notification, Stop, SessionEnd, PermissionDenied |
| **Codex CLI** | `~/.codex/hooks.json` (+ enables `features.hooks`) | PreToolUse, PostToolUse, Notification, Stop, PermissionRequest |
| **Gemini CLI** | `~/.gemini/settings.json` | BeforeTool, AfterTool, Notification, AfterAgent (mapped internally) |

| Hook (canonical) | Fires When | AgentWatch Action |
|------------------|-----------|-------------------|
| `PreToolUse` | Agent is about to call a tool | Danger/drift detection + register pending action |
| `PostToolUse` | Agent finishes a tool call | Clear pending action, track failures |
| `Notification` | Agent sends a notification | Classify as attention_required (fallback) |
| `Stop` / turn complete | Agent turn or session ends | Push "task done" to watch |
| `PermissionRequest` | Permission / approval dialog | Push "needs permission" to watch |
| `PermissionDenied` | User denies an operation | Log only |

### Install / status / uninstall

```bash
agentwatch hooks install                    # all supported agents
agentwatch hooks install --agent grok,codex # subset
agentwatch hooks status
agentwatch hooks uninstall --agent gemini
agentwatch doctor                           # per-agent hook status
```

**Legacy Claude-only scripts** (still work):

```bash
# macOS
bash install_claude_hooks.sh
bash uninstall_claude_hooks.sh

# Windows
powershell -ExecutionPolicy Bypass -File windows\install_claude_hooks_windows.ps1
powershell -ExecutionPolicy Bypass -File windows\uninstall_claude_hooks_windows.ps1
```

> ⚠️ **Session reload:** After installing, **start a new session** in each CLI (or reload hooks, e.g. Grok `/hooks` → `r`). Hooks are loaded at session start; an already-open session will not pick them up automatically.
>
> ⚠️ **Upgrade note:** If you installed Claude hooks before v0.8.0, re-run install to add `PermissionRequest` / `PermissionDenied`.

---

## Notification Policy

AgentWatch uses **actionable mode** by default — only truly interactive events push to your watch.

### ✅ Pushed to Apple Watch

| Event | Source Hook | Example |
|-------|------------|---------|
| Real "Allow this command?" dialog | PermissionRequest | "Claude needs your approval to run: rm -rf build/" |
| Agent needs your attention | Notification (fallback) | "Claude is waiting for your input" |
| Task completed | Stop | "Task done, review results" |

### ❌ Logged Only (no watch push)

| Event | Source | Reason |
|-------|--------|--------|
| You denied a permission | PermissionDenied | No action needed |
| Tool call still open | PreToolUse timeout | Could be a slow command, not a prompt |
| Dangerous operation | PreToolUse danger keywords | Logged as danger; silent in actionable mode |
| Task boundary drift | PreToolUse forbidden paths | Logged as drift |
| Consecutive failures | PostToolUse error count | Logged as failure |

### Switching Modes

To push **all** events (verbose mode, legacy behavior):
```json
"notification_policy": { "mode": "verbose" }
```

To enable PreToolUse timeout push (accepts false-positive risk):
```json
"approval_detection": { "timeout_watch_notify": true }
```

---

## Persona Themes

Switch notification style from the GUI or CLI. No restart needed. Six themes available:

| Theme | Key | Example Notification |
|-------|-----|---------------------|
| Off | `off` | "需要权限 / Agent 正在等待你允许操作" |
| 总裁版 | `boss` | "总裁快签字 / 总裁！没有您的签字，整个项目组..." |
| 少爷版 | `heir_male` | "待您过目 / 少爷，这一步管家不敢擅自处理..." |
| 大小姐版 | `heir_female` | "待您过目 / 大小姐，这一步管家不敢擅自处理..." |
| 皇上版 | `emperor` | "奏请御批 / 皇上，奴才这儿有道折子..." |
| 甄嬛版 | `palace` | "请主子示下 / 主子，这一步内务府不敢擅自做主..." |

**CLI:**
```bash
agentwatch persona show               # show current theme
agentwatch persona set boss           # switch to 总裁版
agentwatch persona set emperor        # switch to 皇上版
agentwatch persona off                # disable persona
agentwatch persona test permission    # preview (no push)
agentwatch persona test done          # preview (no push)
```

**macOS:** `● AW` → `Persona Theme` → choose theme

**Windows:** Right-click tray icon → `Persona Theme` → choose theme

Personas only change notification **wording** — the notification **policy** (which events push) is unchanged.

---

## macOS Menu Bar App

A native Swift + AppKit app that lives in your menu bar (no Dock icon). Look for `● AW` in the top-right.

### Build & Launch

```bash
bash macos/build_app.sh          # build (requires Xcode CLT: swift)
open build/AgentWatch.app        # launch
# or double-click: Open AgentWatch App.command
```

### Features

| Action | Description |
|--------|-------------|
| Bark config | Add / update Bark key, show current config (key redacted) |
| Test Push | Send a test notification to verify the link |
| Persona Theme | Switch between all 6 themes with a checkmark |
| Recent Events | Last 5 non-info events with icons, timestamps, and notified/logged tags |
| Hook status | Per-agent status (Claude / Grok / Codex / Gemini) |
| Install / Update Hooks | One-click multi-agent hook install (with confirmation) |
| Approval Timeout Notify | Shows whether PreToolUse timeout push is On or Off |
| Task boundary | Manage allowed/forbidden paths |
| Quick access | Open Logs folder, config.json, README |
| Monitor | Open the ANSI live dashboard in Terminal |

---

## Windows Tray App

A native C# / .NET 8 WinForms app that lives in your system tray (bottom-right).

### Build & Launch

```powershell
# Requires .NET 8 SDK
powershell -ExecutionPolicy Bypass -File windows\build_app.ps1
build\windows\AgentWatchTray\AgentWatchTray.exe
# or double-click: Open AgentWatch Windows App.bat
```

### Features

Same as macOS menu bar app, plus:
- **Setup Python Environment** — one-click .venv setup
- **Install / Update Claude Code Hooks** — one-click hooks installation (with confirmation)
- **Preview Current Persona** — see what your notifications will look like without sending a push
- **Test Permission Request / Denied** — simulate specific hook events

---

## Common Commands

| Command | Description |
|---------|-------------|
| `agentwatch doctor` | Full health check (config, Bark, multi-agent hooks, logs, task) |
| `agentwatch monitor` | Live ANSI dashboard (Ctrl+C to exit) |
| `agentwatch start` | Doctor check → monitor |
| `agentwatch init` | Create config.json and logs/ directory |
| `agentwatch hooks install` | Install hooks for Claude / Grok / Codex / Gemini |
| `agentwatch hooks status` | Show per-agent hook install status |
| `agentwatch hooks uninstall` | Remove AgentWatch hooks |
| `agentwatch config bark` | Set Bark key (accepts full URL or bare key) |
| `agentwatch config show` | Show Bark config (key is redacted) |
| `agentwatch config test` | Send a test notification |
| `agentwatch persona show` | Show current persona theme |
| `agentwatch persona set <theme>` | Switch persona (boss/emperor/palace/heir_male/heir_female) |
| `agentwatch persona off` | Disable persona, use default text |
| `agentwatch persona test <event>` | Preview persona text for an event (no push) |
| `agentwatch simulate permission-request` | Simulate "Allow this command?" → should push |
| `agentwatch simulate permission-denied` | Simulate user denying → should log only |
| `agentwatch simulate done` | Simulate task complete → should push |
| `agentwatch simulate approval-pending` | Simulate tool timeout → should log only |
| `agentwatch task quick` | Interactive task boundary setup |
| `agentwatch task clear` | Remove current task boundary |
| `agentwatch logs --tail 20` | View last 20 event log entries |

---

## Testing

After setup, verify everything works:

```bash
# 1. Health check
agentwatch doctor
# Expected: Status: Ready; hooks Installed for each detected agent

# 2. Test notification chain
agentwatch config test
# Expected: Notification appears on iPhone / Apple Watch

# 3. Simulate a real permission dialog
agentwatch simulate permission-request
# Expected: Watch notification with your current persona theme

# 4. Simulate task completion
agentwatch simulate done
# Expected: Watch notification "task done"

# 5. These should NOT push (log-only by default):
agentwatch simulate approval-pending    # timeout → log only
agentwatch simulate permission-denied   # deny → log only
```

---

## Troubleshooting

### Phone / watch not vibrating
1. Confirm Bark is installed and working on your phone (send a test from the Bark app itself)
2. Run `agentwatch config test` — should say "Notification sent"
3. iPhone: Settings → Notifications → Bark → Allow ✅
4. Android: Settings → Notifications → Bark → Allow ✅
5. Apple Watch: Watch app → Notifications → Mirror iPhone Alerts from Bark ✅
6. Android band/watch: enable Bark notification sync in your companion app (Huawei Health, Mi Fitness, Galaxy Wearable, etc.)

### Bark returns "device token not found"
- Your Bark key is incorrect or expired
- Open the Bark iOS app → copy the current URL
- Ensure `bark_server` in config.json is `https://api.day.app`

### "Allow this bash command?" appears but Watch didn't vibrate
1. Run `agentwatch doctor` — does it say `Missing PermissionRequest`?
2. If yes, reinstall hooks:
   - macOS: `bash install_claude_hooks.sh`
   - Windows: `powershell -File windows\install_claude_hooks_windows.ps1`
3. Test: `agentwatch simulate permission-request`
4. **Restart your Claude Code session** — new hooks only take effect in new sessions

### Too many false alerts from slow Bash commands
- This is the **default** — PreToolUse timeouts are log-only (`timeout_watch_notify: false`)
- Verify config: `approval_detection.timeout_watch_notify` is `false`
- Long-running commands (builds, tests) will not trigger watch notifications

### macOS app double-click has no window
- It's a **menu bar app** — look for `● AW` in the top-right corner of your screen
- No Dock icon, no window. Click the icon to open the menu.

### Windows tray app doesn't start
- Ensure .NET 8 SDK is installed: `dotnet --version`
- Rebuild: `powershell -File windows\build_app.ps1`
- Check `build\windows\AgentWatchTray\AgentWatchTray.exe` exists

### Hooks installed but doctor says "Missing"
- Check the Python path in `~/.claude/settings.json` points to the correct `.venv`
- If you moved the project, re-run the install script

---

## Privacy & Security

| Concern | Status |
|---------|--------|
| Bark key in git | ❌ Blocked (`config.json` is gitignored) |
| Logs in git | ❌ Blocked (`logs/` and `diagnostics/` are gitignored) |
| Source code sent to external LLM | ❌ No — AgentWatch never calls AI APIs |
| Notification content to Bark server | ✅ Title + body only. Self-host option available. |
| Bark key in log files | ❌ Automatically redacted before writing |
| Claude Code settings modified | ✅ Only when you manually run install script |

See [SECURITY.md](SECURITY.md) for full details.

---

## Roadmap

- [ ] GitHub Release binaries (pre-built `.app` and `.exe`)
- [ ] Away mode — auto-detect when you step away and enable aggressive monitoring
- [ ] Session summary notifications — what was accomplished
- [ ] Guard mode — auto-block dangerous operations before execution
- [ ] More persona themes
- [ ] Pushover / ntfy notification backend support
- [ ] Native iOS / watchOS actions (approve/deny from wrist)

---

## License

MIT — see [LICENSE](LICENSE).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
