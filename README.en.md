# Kimi Approve Watch

![Version](https://img.shields.io/badge/version-0.2.0-blue)
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

### Approval watcher — light and gentle

Kimi CLI shows an interactive dialog (`Run this command? 1. Approve once ...`) before risky actions. The watcher scans all Windows Terminal windows every 10 seconds and presses the chosen option for you.

- **gentle**: restores focus to the window you were working in after each keypress; runs its own process at BelowNormal priority
- **light**: reads only `TermControl` UI Automation elements (not the whole window tree), inspects only the buffer tail
- **configurable choice**: `-ApproveKey 1|2|3` picks which dialog option to press (default `1` — approve once)
- cleans up the stray character the TUI sometimes leaves in the input line
- skips minimized windows and any hwnd in `-ExcludeHwnd`
- agent profiles: `kimi` (default), `claude` (experimental)

### PC stabilizer

- **keep-awake** — no sleep, no display timeout
- **High performance** — max power plan while running, previous plan restored on exit
- **terminal priority** — keeps WindowsTerminal at AboveNormal
- **RAM** — logs top-5 memory hogs when memory runs low
- **disk** — low-space alerts (builds eat gigabytes)
- **network** — records outage windows (AI APIs are unreachable then)
- **pending reboot** — warns about a Windows reboot waiting to happen
- **terminal crash** — alerts if Windows Terminal dies mid-session

### Reliability

- **logon gate** — nothing runs until you click "Yes" after signing in
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
    IntervalSeconds = 10        # scan period
    Agents          = 'kimi'    # 'kimi' or 'kimi,claude'
    ApproveKey      = ''        # '' = 1 (approve once); '1'|'2'|'3' to override
    ExcludeHwnd     = @()       # @(3344318) — never touch these windows
    NoFocusRestore  = $false    # $true — keep focus on the agent window
  }
  Stabilizer = @{
    MinFreeRamGB = 1.5; MinFreeDiskGB = 5; WatchDrives = @('C:')
    HighPerformance = $true; BoostTerminalPriority = $true
  }
}
```

Direct runs with parameters work too:

```powershell
.\watch-approve.ps1 -IntervalSeconds 5 -ApproveKey 1 -ExcludeHwnd 3344318 -Once
.\stabilize.ps1 -MinFreeRamGB 2 -WatchDrives 'C:','D:' -Once
```

Use `.\kaw.ps1 windows` to find your own window's hwnd and exclude it if you don't want auto-approval in your personal session.

## How it works

1. Every `IntervalSeconds`, windows of class `CASCADIA_HOSTING_WINDOW_CLASS` (Windows Terminal) are enumerated.
2. UI Automation reads only `TermControl` elements — cheap even on huge buffers.
3. All dialog strings from a profile present in the tail (15 lines) → focus the window, `SendKeys` with the chosen option, **focus returns** to your window.
4. A stray character left in the input line is removed with Backspace.
5. Meanwhile the stabilizer polls CIM (RAM/disk/CPU), pings the network, checks the registry for pending reboots — and logs only state transitions.

## Why not a Windows service?

Services live in session 0 and **cannot see user windows** — UI Automation and SendKeys are useless there. Everything runs in the interactive session instead: a scheduled task at logon (`gate` mode, with confirmation) or the Startup folder (`startup` mode). Safer, too: without your sign-in and "Yes", auto-approval stays silent.

## Files

| File | Purpose |
|---|---|
| `kaw.ps1` | Single management command (start/stop/status/log/config/...) |
| `watch-approve.ps1` | Approval core: agent profiles, key choice, focus restore |
| `stabilize.ps1` | Stabilizer: power plan, RAM/disk/network/CPU, alerts |
| `watch-approve-launcher.ps1` | Restarts crashed modules, no duplicates |
| `start-all.ps1` | Entry point for both modules (args from config) |
| `watcher-gate.ps1` | Logon confirmation dialog |
| `install.ps1` / `uninstall.ps1` | Autostart setup / removal |
| `quickstart.ps1` / `quickstart.sh` | One-liner bootstrap (PowerShell / bash) |
| `kaw.config.example.psd1` | Config template |
| `stop-watcher.ps1`, `status.ps1`, `show-windows.ps1` | Utility scripts |

Runtime files (`*.log`, `*.pid`, `STOP`, `stabilizer.enabled`, `kaw.config.psd1`) are git-ignored.

## Security

- By default only the one-time approval (`1`) is pressed; option `2` ("approve always") exists but enable it deliberately.
- Dialogs are detected from the buffer tail — no false positives from scrollback.
- The stabilizer only observes; active changes (power plan, priority) roll back.
- The `claude` profile is experimental — verify it against your Claude Code version.
- No network calls (except quickstart) and no external dependencies.

## License

[MIT](LICENSE) · [Changelog](CHANGELOG.md)
