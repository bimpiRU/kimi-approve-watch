# Kimi Approve Watch

![Version](https://img.shields.io/badge/version-0.3.0-blue)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE?logo=powershell&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-10%2F11-0078D6?logo=windows&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green)

**[Русская версия → README.md](README.md)**

> A lightweight, gentle auto-approver for [Kimi CLI](https://github.com/MoonshotAI/kimi-cli) permission dialogs, plus a PC stabilizer for long agent sessions in terminals. One command to install — your machine stays under control while AI agents code and build.

---

## One-liner install — from any terminal

**PowerShell / Windows Terminal / pwsh 7:**

```powershell
powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/bimpiRU/kimi-approve-watch/main/quickstart.ps1 | iex"
```

**CMD:**

```cmd
curl -L -o "%TEMP%\kaw-quickstart.ps1" https://raw.githubusercontent.com/bimpiRU/kimi-approve-watch/main/quickstart.ps1 && powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\kaw-quickstart.ps1"
```

**Git Bash / MSYS2 / WSL:**

```bash
curl -sL https://raw.githubusercontent.com/bimpiRU/kimi-approve-watch/main/quickstart.sh | bash
```

Installs to `%USERPROFILE%\kimi-approve-watch` (via `git clone`, or ZIP if git is missing). Re-running the command updates to the latest version. Overrides: `KAW_MODE=gate|startup|none`, `KAW_DIR=<path>`.

## What it does

### Approval watcher — fast and gentle

Kimi CLI shows an interactive dialog (`Run this command? 1. Approve once ...`) before risky actions. The watcher scans all Windows Terminal windows every 5 seconds and presses the chosen option for you.

- **fast**: `FastMode` lowers delays; `-ApproveKey auto` finds the "Approve once" option number from the dialog text
- **gentle**: restores focus to the window you were working in after each keypress; runs its own process at BelowNormal priority
- **light**: reads only `TermControl` UI Automation elements (not the whole window tree), inspects only the buffer tail
- **configurable choice**: `-ApproveKey 1|2|3|auto` picks which dialog option to press (default `1` — approve once)
- **self-approval**: `-AutoApproveSelf` — approve in the watcher window itself (main terminal); `-NoSelfSkip` — also approve in the window that is talking about this bot
- cleans up the stray character the TUI sometimes leaves in the input line
- skips minimized windows and any hwnd in `-ExcludeHwnd`
- agent profiles: `kimi` (default), `claude` (experimental), `generic` (any similar dialog)

### PC stabilizer

- **keep-awake** — no sleep, no display timeout
- **High performance** — max power plan while running, previous plan restored on exit
- **terminal priority** — keeps WindowsTerminal at AboveNormal
- **inactive agent priority** — `kimi` processes silent for more than 2 hours are automatically downgraded to `BelowNormal` and restored to `Normal` when activity appears (`ManageAgentPriority`)
- **prompt tips** — every N minutes a cross-platform notification suggests how to phrase a request to the agent (`PromptTips`, `PromptTipIntervalMinutes`)
- **quiet hours** — `QuietHours = "23-07"` disables notifications at night
- **auto temp cleanup** — cleans `%TEMP%` when disk space is low (`AutoCleanTemp`)
- **RAM** — logs top-5 memory hogs when memory runs low
- **disk** — low-space alerts (builds eat gigabytes)
- **network** — records outage windows (AI APIs are unreachable then)
- **pending reboot** — warns about a Windows reboot waiting to happen
- **terminal crash** — alerts if Windows Terminal dies mid-session

### Reliability

- **logon gate** — nothing runs until you click "Yes" after signing in
- **background service** — `install-service.ps1` starts a runner at boot, but watcher/stabilizer start only after you confirm at logon
- **no duplicates** — mutexes prevent double starts
- **self-healing** — the launcher restarts a crashed module
- event-only logs, no spam

## Requirements

- Windows 10/11, Windows Terminal, PowerShell 5.1 (all built-in)

## Autostart modes

| Mode | Behaviour | Admin |
|---|---|---|
| `gate` | Confirmation dialog at logon — starts only after "Yes" | Yes (UAC at install) |
| `startup` | Silent shortcut in the Startup folder | No |
| `none` | No autostart, just run now | No |
| `service` | `install-service.ps1` — background runner before logon + confirmation at logon | Yes |

## Management — `kaw.ps1`

```powershell
.\kaw.ps1 start               # start everything
.\kaw.ps1 stop                # gracefully stop everything
.\kaw.ps1 restart             # restart
.\kaw.ps1 status              # module state + log tails
.\kaw.ps1 log stabilizer      # log tail (watcher|stabilizer)
.\kaw.ps1 enable stabilizer   # enable stabilizer in autostart
.\kaw.ps1 disable stabilizer  # disable it
.\kaw.ps1 config              # show effective config
.\kaw.ps1 windows             # terminal window hwnds
.\kaw.ps1 uninstall           # full removal
```

The individual scripts (`status.ps1`, `stop-watcher.ps1`, `show-windows.ps1`...) still work — `kaw.ps1` is just a convenient wrapper.

## Configuration — `kaw.config.psd1`

Copy `kaw.config.example.psd1` → `kaw.config.psd1` and edit. The config applies both to autostart and manual runs; command-line parameters take precedence.

```powershell
@{
  Watcher = @{
    IntervalSeconds = 5           # scan period
    Agents          = 'kimi'      # 'kimi' or 'kimi,claude,generic'
    ApproveKey      = ''          # '' = 1 (approve once); '1'|'2'|'3' override; 'auto'
    ExcludeHwnd     = @()         # @(3344318) — never touch these windows
    FocusRestore    = $false      # $true — return focus to previous window (experimental)
    NoSelfSkip      = $true       # $true — also approve in the window managing this bot
    AutoApproveSelf = $true       # $true — approve in the watcher window itself
    FastMode        = $true       # $true — faster, slightly more CPU
  }
  Stabilizer = @{
    MinFreeRamGB = 1.5; MinFreeDiskGB = 5; WatchDrives = @('C:')
    HighPerformance = $true; BoostTerminalPriority = $true
    ManageAgentPriority = $false   # $true — manage priority of inactive agents
    PromptTips = $false            # $true — prompt-advice notifications
    PromptTipIntervalMinutes = 30
    AutoCleanTemp = $false         # $true — clean %TEMP% when disk is low
    QuietHours = ''                # "23-07" — silent period
  }
}
```

Direct runs with parameters work too:

```powershell
.\watch-approve.ps1 -IntervalSeconds 5 -ApproveKey auto -ExcludeHwnd 3344318 -FastMode -Once
.\stabilize.ps1 -MinFreeRamGB 2 -WatchDrives 'C:','D:' -AutoCleanTemp -Once
```

Use `.\kaw.ps1 windows` to find your own window's hwnd and exclude it if you don't want auto-approval in your personal session.

### Personal tabs and self-approval

Tab titles differ for everyone, so exclusions use **hwnd** instead of names:

1. Open the tabs you want to exclude and run `.\kaw.ps1 windows`.
2. Copy their hwnds into `kaw.config.psd1` → `Watcher.ExcludeHwnd`.
3. If you want approvals in the watcher session too, set `NoSelfSkip = $true` and `AutoApproveSelf = $true`.

```powershell
@{
  Watcher = @{
    ExcludeHwnd   = @(328372, 1377268)   # personal tabs
    NoSelfSkip    = $true                # approve in windows that mention this bot
    AutoApproveSelf = $true              # approve in the watcher window itself
  }
}
```

## How it works

1. Every `IntervalSeconds`, windows of class `CASCADIA_HOSTING_WINDOW_CLASS` (Windows Terminal) are enumerated.
2. UI Automation reads only `TermControl` elements — cheap even on huge buffers.
3. All dialog strings from a profile present in the tail (15 lines) → focus the window, `SendKeys` with the chosen option, **focus returns** to your window.
4. A stray character left in the input line is removed with Backspace.
5. Meanwhile the stabilizer polls CIM (RAM/disk/CPU), pings the network, checks the registry for pending reboots — and logs only state transitions.

## Why not a classic Windows service?

Classic services live in session 0 and **cannot see user windows** — UI Automation and SendKeys are useless there. The default modes use an interactive scheduled task at logon (`gate`) or the Startup folder (`startup`).

For users who want a background runner before logon, `install-service.ps1` creates `KAWService` (runs at boot) and `KAWGate` (confirmation at logon). The runner waits for a signal and only after your "Yes" starts watcher and stabilizer in the interactive session.

## Files

| File | Purpose |
|---|---|
| `kaw.ps1` | Single management command (start/stop/status/log/config/...) |
| `watch-approve.ps1` | Approval core: agent profiles, key choice, focus restore |
| `stabilize.ps1` | Stabilizer: power plan, RAM/disk/network/CPU, alerts, notifications |
| `watch-approve-launcher.ps1` | Restarts crashed modules, no duplicates |
| `start-all.ps1` | Entry point for both modules (args from config) |
| `watcher-gate.ps1` | Logon confirmation dialog |
| `service-runner.ps1` | Background runner for `service` mode |
| `install.ps1` / `install-service.ps1` / `uninstall.ps1` | Autostart setup / removal |
| `quickstart.ps1` / `quickstart.sh` | One-liner bootstrap (PowerShell / bash) |
| `kaw.config.example.psd1` | Config template |
| `stop-watcher.ps1`, `status.ps1`, `show-windows.ps1` | Utility scripts |

Runtime files (`*.log`, `*.pid`, `STOP`, `stabilizer.enabled`, `kaw.config.psd1`, `.service-go`) are git-ignored.

## Security

- By default only the one-time approval (`1`) is pressed; option `2` ("approve always") exists but enable it deliberately.
- Dialogs are detected from the buffer tail — no false positives from scrollback.
- The stabilizer only observes; active changes (power plan, priority) roll back.
- The `claude` profile is experimental — verify it against your Claude Code version.
- No network calls (except quickstart) and no external dependencies.

## License

[MIT](LICENSE) · [Changelog](CHANGELOG.md)
