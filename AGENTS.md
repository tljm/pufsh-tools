# AGENTS.md - pufsh-tools Developer Guide

This guide documents the essential context needed to work effectively in the pufsh-tools repository.

## Project Overview

**pufsh-tools** is a collection of shell scripts for OpenBSD that enhance the desktop experience through window management, display automation, and backup utilities. All tools are POSIX-compliant shell scripts designed to work with X11 and OpenBSD-specific features.

**Platform**: OpenBSD with X11
All tools run on OpenBSD.
**Language**: POSIX shell script (sh, not bash)
**Architecture**: Modular daemon + utility scripts

## Repository Structure

```
pufsh-tools/
├── screen-daemon.sh          # Background daemon (display management & power)
├── screen-select.sh          # Manual display switching
├── screen-reinit.sh          # Reinitialization framework
├── tiling.sh                 # Window tiling engine
├── make_backup.sh            # Backup/archive utility
├── screen-reinit.d/          # Reinitialization hooks (modular)
│   ├── 10-xphoon            # Wallpaper manager
│   ├── 20-xbattbar          # Battery indicator
│   ├── 30-xscreensaver      # Screensaver daemon
│   └── 40-console-move      # xconsole positioning
├── examples/
│   └── cwmrc                # Example CWM window manager config
├── README.md
├── LICENSE
└── .gitignore
```

## Critical Context: Code Patterns & Conventions

### Shell Script Compatibility

- **POSIX sh only** — No bash-isms. All scripts must work with OpenBSD's default `/bin/sh`.
- **No advanced features** — Avoid: `[[`, `+=`, `declare`, bashisms in variable expansion.
- **Portability first** — Use `command -v` (not `which`), `[ ]` not `[[ ]]`, arithmetic via `$(( ))`.

### PATH Initialization Pattern

Every main script starts with this block to ensure tools are discoverable:

```sh
for path in /usr/local/bin /usr/X11R6/bin "$HOME/bin" "$HOME/.local/bin"; do
    case ":$PATH:" in
        *":$path:"*) ;;
        *) [ -d "$path" ] && PATH="$PATH:$path" ;;
    esac
done
export PATH
```

**Why**: OpenBSD's X11 tools are often in `/usr/X11R6/bin`, and custom tools may be in `~/.local/bin`. This pattern prevents hardcoded paths.

### Logging Pattern

All scripts use centralized timestamped logging:

```sh
LOG_TS_FORMAT='+%Y-%m-%d %H:%M:%S'

log() {
    echo "[$(date "$LOG_TS_FORMAT")] $*"
}
```

**Gotcha**: Logs go to stdout for integration with systemd/logging. Some older daemons used syslog; this project does not. All logging output is human-readable and prefixed with timestamps.

### Script Discovery Pattern

Scripts that call other scripts in the toolkit use this pattern:

```sh
SELF_PATH=$(command -v "$0" 2>/dev/null)
[ -z "$SELF_PATH" ] && SELF_PATH="./$0"
SCRIPT_DIR=$(dirname "$(realpath "$SELF_PATH" 2>/dev/null || echo "$SELF_PATH")")

find_script() {
    name=$1
    if command -v "$name" >/dev/null 2>&1; then
        command -v "$name"
    elif [ -f "$SCRIPT_DIR/$name" ]; then
        echo "$SCRIPT_DIR/$name"
    fi
}

HELPER_SCRIPT=$(find_script helper-script.sh)
```

**Why**: Scripts are designed to work whether invoked via `PATH` or symlinks. `realpath` resolves symlinks; this pattern finds sibling scripts correctly.

### Argument Parsing Pattern

Scripts use `getopts` for clean argument handling:

```sh
while getopts "hg:i:" opt; do
    case "$opt" in
        h) show_help; exit 0 ;;
        g) GHOST_PERIOD=$OPTARG; shift ;;
        *) show_help; exit 1 ;;
    esac
done
```

**Why**: Portable across POSIX shells, handles short flags only (no long flags via getopts).

### Numeric Validation

Used before accepting numeric arguments:

```sh
is_numeric() {
    case $1 in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

if is_numeric "$OPTARG"; then
    INTERVAL=$OPTARG
else
    log "Error: -i requires a numeric argument." >&2
    exit 1
fi
```

**Why**: Avoids command injection and provides clear error messages.

### Safe Argument Passing in Subshells

When building dynamic `xrandr` commands, use subshells with `set --`:

```sh
(
    set -- --output "$MODE" --primary --auto
    for out in $CONNECTED_OUTPUTS; do
        if [ "$out" != "$MODE" ]; then
            set -- "$@" --output "$out" --off
        fi
    done
    xrandr "$@"
)
```

**Why**: Avoids shell variable pollution and correctly expands arguments. Subshell prevents modifying parent script state.

### Error Output

All error messages go to stderr with `>&2`:

```sh
log "Error: Display '$MODE' not found or not connected." >&2
exit 1
```

### Dependency Checks

Every script validates required tools early:

```sh
MISSING=""
for tool in xrandr sndioctl xprop xscreensaver-command; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        MISSING="$MISSING $tool"
    fi
done

if [ -n "$MISSING" ]; then
    log "Error: Required tools not found in PATH:$MISSING" >&2
    exit 1
fi
```

## Module Breakdown

### screen-daemon.sh

**Purpose**: Background daemon for display management and power control. Runs from `.xsession`.

**Key Responsibilities**:
- Monitor display hotplug events
- Clean up "ghost" screens (disconnected but still active in xrandr)
- Inhibit screensaver when audio is playing + window is fullscreen
- Handle lid sensor state and auto-enable external displays when lid closes
- Respond to signals:
  - SIGHUP (1) — Manual check for "ghost" screens, or exit suspend mode.
  - SIGUSR1 (30) — Trigger a UI component refresh.
  - SIGUSR2 (31) — Enter suspend mode (built-in screen only, other events ignored).

**Command Line**:
```sh
screen-daemon.sh [-g ghost_seconds] [-i inhibit_seconds]
```

**Key Variables**:
- `GHOST_PERIOD` (default 10s) — How often to check for ghost screens
- `INHIBIT_PERIOD` (default 60s) — How often to check screensaver status
- `SUSPEND_MODE` (default 0) — 0=off, 1=on. When on, daemon only keeps built-in screen active.
- `BUILTIN_SCREEN` — Detected internal display (eDP, LVDS, or DSI)
- `LID_SENSOR` — OpenBSD sysctl path to lid state

**Architecture**:
1. Initialization phase: PATH setup, dependency check, script discovery
2. Main loop: Sleeps between checks; responds to signals
3. Per-check: Detects display state, calls `screen-select.sh` or `screen-reinit.sh` as needed

**Gotchas**:
- **Lid sensor detection**: Uses `sysctl hw.sensors` to find lid state. Only active if `machdep.lidaction=0` (lid does not trigger hardware sleep).
- **Ghost screen cleanup**: Calls `xrandr --output <output> --off` to disable disconnected outputs still marked active.
- **Audio detection**: Uses `sndioctl | grep -i play` to check if audio is playing; full-screen detection via `xprop _NET_WM_STATE`.
- **Race conditions**: Rapidly running `screen-select.sh` can spawn multiple instances; daemon protects itself but screen-select terminates other screen-* scripts (not daemon).

### screen-select.sh

**Purpose**: Manual tool to switch displays or auto-configure all connected monitors.

**Command Line**:
```sh
screen-select.sh [auto | auto-external | builtin-only | <display_name>]
```

**Modes**:
- `auto` — Enable all connected displays using xrandr auto-detection
- `auto-external` — Enable external displays, disable built-in
- `builtin-only` — Enable built-in display, disable all others
- `<display_name>` — Enable one display, disable all others

**Key Variables**:
- `ALL_OUTPUTS_INFO` — Parsed xrandr output (name, status, on/off)
- `CONNECTED_OUTPUTS` — List of currently connected displays
- `BUILTIN_SCREEN` — Internal display name

**Architecture**:
1. Parse xrandr to detect displays
2. Validate requested display
3. Build xrandr command with `set --` in subshell
4. Call `screen-reinit.sh` to refresh UI components

**Gotchas**:
- **Display name format**: eDP-1, HDMI-1, etc. (exact format varies by system)
- **Built-in detection**: Looks for eDP, LVDS, or DSI prefix
- **Race condition cleanup**: Kills other screen-* processes to prevent simultaneous execution
- **Help output**: Shows "(internal)" tag only for built-in display (added in recent commit)

### screen-reinit.sh

**Purpose**: Modular hook framework for reintializing UI components after display changes.

**Command Line**:
```sh
screen-reinit.sh [-h|--help]
```

**Architecture**:
1. Resolve physical script location (handles symlinks via `realpath`)
2. Find `screen-reinit.d/` directory in same location
3. Execute all executable files in numerical order (naming convention: `NN-hookname`)
4. Log each hook execution

**Gotchas**:
- **Symlink resolution**: Must use `realpath` to find hooks when script is symlinked to `PATH`
- **Hook ordering**: Numerical prefix determines order (10-* before 20-*, etc.)
- **Hooks are optional**: Gracefully exits if `screen-reinit.d/` doesn't exist
- **Hook failure handling**: Non-zero exit from hook stops further processing; logged with hook name

### tiling.sh

**Purpose**: State-aware window tiling for cwm (Calm Window Manager). Supports grid-based placement, progressive grow/shrink, and slide operations.

**Command Line**:
```sh
tiling.sh [-M margin] [-TOL tolerance] [-nf] [-h splits [start [end]]] [-v splits [start [end]]]
tiling.sh [-h splits -l|-r|-move-l|-move-r]
tiling.sh [-v splits -t|-b|-move-t|-move-b]
```

**Key Variables**:
- `M` (default 1px) — Window margin (gap between edges and screen)
- `TOL` (default 5px) — Snap tolerance for edge detection
- `FOCUS_TRACK` (default 1) — Mouse focus tracking (0 to disable)

**Tiling Modes**:
1. **Static**: Place window in specific grid segments
   - `-h 3 1` → left 1/3
   - `-h 6 2 5` → middle 4/6 (segments 2–5 inclusive)
2. **Progressive**: Grow window toward edge
   - `-h 3 -r` → expand right edge; then move left edge right
3. **Slide**: Move by exact segment width/height
   - `-h 3 -move-r` → shift right by 1/3 of screen

**Architecture**:
1. Get active window via `xprop -root _NET_ACTIVE_WINDOW`
2. Get dimensions via `xwininfo`
3. Calculate target coordinates based on tiling mode
4. Apply window move/resize via `wmctrl`
5. Optionally warp mouse via `xdotool` (if installed)

**Gotchas**:
- **Window ID format**: Returns as hex (e.g., `0x2800001`); xwininfo requires `-id` flag.
- **Screen resolution from root**: Uses `xwininfo -root` to get total dimensions, not per-monitor.
- **Margin application**: 1px margin means 1px gap on all sides; increases with each operation.
- **Focus tracking**: Uses `xdotool` if available (optional). Warps mouse to window center after tiling.
- **xprop parsing**: Looks for `_NET_ACTIVE_WINDOW` property; fails if no window is focused.
- **Multi-monitor**: All calculations assume single logical screen; tiling.sh does not detect individual monitors.

### make_backup.sh

**Purpose**: Create timestamped, high-compression archives of current directory.

**Design Philosophy**: Script is designed to be symlinked into a backup destination folder (e.g., `~/backups/`). When invoked from a project directory, it saves archives to the directory where the script itself is located.

**Command Line**:
```sh
make_backup.sh [-d dest] [-t type] [-l level] [-p] [-n] [-v] [-S|--no-stats]
```

**Options**:
- `-d dest` — Destination directory (default: script's directory or `$BACKUP_DIR`)
- `-t type` — Archive type: `tar`, `tar.gz`, `tar.bz2`, `tar.xz`, `tar.bz3`, `7z`, `tar.7z` (default: tar.gz)
- `-l level` — Compression level 1–9 (default: 6)
- `-p` — Use parallel compression (xz, 7z, bzip3, pigz, pbzip2 if available)
- `-n` — Dry run (print command, don't execute)
- `-v` — Verbose (show progress)
- `-S, --no-stats` — Skip size statistics

**Key Variables**:
- `DEST_DIR` — Output directory (from `-d`, `$BACKUP_DIR`, or script directory)
- `TYPE` — Archive format
- `LEVEL` — Compression level
- `PARALLEL` — Enable multi-core compression

**Architecture**:
1. Parse arguments
2. Resolve script directory (respects symlinks)
3. Generate timestamped filename
4. Build tar/7z command with compression flags
5. Calculate statistics (original size vs. compressed, space saved)
6. Execute or dry-run

**Gotchas**:
- **Symlink-aware destination**: Uses script's directory, not `pwd`, as default backup location.
- **Parallel flags vary by tool**: xz uses `-T0`, 7z uses `-mmt`, pigz/pbzip2 use different flags. Script handles this internally.
- **Compression vs. speed**: Level 6 is reasonable default; higher levels (8–9) significantly slower for marginal gains.
- **Timestamp format**: Uses `YYYYMMDD-HHMMSS` in filename for natural sorting.

## Key Gotchas & Non-Obvious Patterns

### Built-in Screen Detection

Multiple scripts detect the internal laptop display:

```sh
BUILTIN_SCREEN=$(xrandr | grep -E "^(eDP|LVDS|DSI)" | awk '{print $1}' | head -n 1)
```

**Why**: Different systems use different names (eDP on modern Intel, LVDS on older laptops, DSI on ARM). This grep pattern catches all three prefixes.

### Lid Sensor Detection (OpenBSD-specific)

```sh
LID_SENSOR=$(sysctl hw.sensors 2>/dev/null | grep -i "lid" | cut -d= -f1 | head -n 1)
LID_STATE=$(sysctl -n "$LID_SENSOR" 2>/dev/null)
```

**Gotchas**:
- Only works on systems with a lid sensor (laptops).
- Returns path like `hw.acpi.lid0.state`.
- Lid state is "Off" (closed) or "On" (open).
- Only used if `machdep.lidaction=0` (lid doesn't auto-sleep).

### Ghost Screen Cleanup

A "ghost screen" is xrandr output that is disconnected but still has active geometry:

```sh
GHOST_SCREENS=$(xrandr | awk '/ disconnected/ && /[0-9]+x[0-9]+/ {print $1}')
```

**Why**: When you unplug a monitor, xrandr may not automatically disable it. This pattern finds them for cleanup.

### xrandr Argument Construction

To avoid shell injection and handle dynamic display lists:

```sh
(
    set -- --output "$MODE" --primary --auto
    for out in $CONNECTED_OUTPUTS; do
        [ "$out" != "$MODE" ] && set -- "$@" --output "$out" --off
    done
    xrandr "$@"
)
```

**Why**: `set --` replaces `$@` safely in a subshell. Prevents variable pollution and ensures correct word splitting for xrandr.

### Hook Execution Order

Hooks are executed by filename order (10-*, 20-*, 30-*, etc.):

1. `10-xphoon` — Start wallpaper first (background layer)
2. `20-xbattbar` — Then battery monitor
3. `30-xscreensaver` — Then screensaver
4. `40-console-move` — Then move console (top layer)

**Why**: UI components have dependencies; wallpaper must load before overlays.

### Hook Restart Pattern

Hooks that manage daemons use a robust restart pattern:

```sh
# Kill loop: Terminate and verify
while pgrep -x xphoon >/dev/null; do
    pkill xphoon
    sleep 1
done

# Start loop: Launch and verify
COUNT=0
while [ $COUNT -lt 5 ]; do
    if pgrep -x xphoon >/dev/null; then
        exit 0
    fi
    sleep 1
    COUNT=$((COUNT + 1))
done

echo "[Framework] Error: xphoon failed to start after 5 attempts."
exit 1
```

**Why**: Ensures clean restart. Some processes take time to fully terminate; verification prevents race conditions.

### Process Termination in screen-select.sh

```sh
DAEMON_PID=$(pgrep -f screen-daemon.sh)
for pid in $(pgrep -f "screen-"); do
    if [ "$pid" != "$$" ] && [ "$pid" != "$DAEMON_PID" ]; then
        kill -9 "$pid" 2>/dev/null
    fi
done
```

**Why**: Prevents multiple simultaneous display changes. Protects daemon; kills other screen-* scripts.

### Help Output Improvements

The help function uses heredoc for readability:

```sh
show_help() {
    cat << EOF
Usage: $(basename "$0") [options]
...
EOF
}
```

**Convention**: Always show available displays in help (screen-select.sh) or available options. Recent commit added "(internal)" tag to identify built-in screen.

## Testing & Verification

There are no automated tests in this repository. Verification is manual:

1. **Display changes**: Test with `xrandr` directly, then verify UI updates
2. **Daemon signals**: Send SIGHUP/SIGUSR1 and check logs
3. **Hook execution**: Manually call `screen-reinit.sh` and verify each hook runs
4. **Tiling**: Invoke from cwm keybindings, check window positioning

**Recommendation**: Add minimal shell test suite if expanding functionality (check `command -v` output, verify file existence, validate numeric arguments).

## Building, Running, Deploying

### No Build Step

Scripts are interpreted; no compilation needed.

### Running Locally

```sh
# Direct execution
./tiling.sh -h 3 1

# Via PATH (after installation)
tiling.sh -h 3 1

# Via explicit path
/usr/local/bin/tiling.sh -h 3 1
```

### Installation Options

1. **Copy to bin**:
   ```sh
   cp *.sh ~/bin/
   chmod +x ~/bin/*.sh
   ```

2. **Symlink from repo** (recommended for development):
   ```sh
   git clone https://github.com/tljm/pufsh-tools.git ~/.local/lib/pufsh-tools
   ln -s ~/.local/lib/pufsh-tools/*.sh ~/bin/
   ```

3. **Add repo to PATH**:
   ```sh
   # In ~/.profile
   export PATH="$PATH:$HOME/path/to/pufsh-tools"
   ```

### Integration with .xsession

```sh
# Start screen daemon first (runs in background)
screen-daemon.sh &

# Optional: Auto-configure displays on login
screen-select.sh auto

# Start window manager
exec cwm
```

### Integration with cwm

Add keybindings to `.cwmrc` (example in `examples/cwmrc`):

```cwmrc
# Progressive tiling
bind-key 4-l  "tiling.sh -h 4 -r"
bind-key 4-h  "tiling.sh -h 4 -l"
bind-key 4-j  "tiling.sh -v 4 -b"
bind-key 4-k  "tiling.sh -v 4 -t"

# Slide tiling
bind-key 4S-l "tiling.sh -h 8 -move-r"
bind-key 4S-h "tiling.sh -h 8 -move-l"
```

## Git Workflow & Commit Conventions

### Branch Strategy

- Main development on `main`
- No long-lived feature branches documented

### Commit Message Format

Commits use conventional-commit style:

```
feat: add timestamped logging to screen-* scripts
fix: correct xbattbar flags and documentation in hook
opt: only run screen-reinit when at least one display is active
docs: sync README with actual script defaults
security: fix command injection and argument splitting vulnerabilities
```

**Types**:
- `feat:` — New feature
- `fix:` — Bug fix
- `opt:` — Performance optimization
- `docs:` — Documentation
- `security:` — Security fix
- `refactor:` — Code refactoring (internal)

### Recent Changes (for context)

- **Timestamped logging**: Recently added to all screen-* scripts (commit 6535159)
- **Internal screen identification**: Help now shows "(internal)" tag (commit ca63f55)
- **Lid sensor support**: Auto-enable external displays when lid closes (commit f93574b)
- **Modular hooks**: Refactored from hardcoded logic to plugin framework (commit cecccdb)

## Common Tasks for Agents

### Adding a New Hook

1. Create executable file in `screen-reinit.d/` with numerical prefix (e.g., `25-my-daemon`)
2. Use restart pattern: kill, verify gone, start, verify running
3. Log with `echo "[Framework] ..."` or redirect to logger
4. Return exit code 0 on success, non-zero on failure

**Example**:

```sh
#!/bin/sh
# 25-my-daemon: Restart my UI component

while pgrep -x my-daemon >/dev/null; do
    pkill my-daemon
    sleep 1
done

my-daemon &

COUNT=0
while [ $COUNT -lt 5 ]; do
    if pgrep -x my-daemon >/dev/null; then
        exit 0
    fi
    sleep 1
    COUNT=$((COUNT + 1))
done

echo "[Framework] Error: my-daemon failed to start."
exit 1
```

### Modifying Display Detection Logic

- Edit the grep pattern in `screen-daemon.sh` and `screen-select.sh` if adding support for new display names
- Update `BUILTIN_SCREEN` detection to include new prefixes
- Test with `xrandr` output from target system

### Adding a Tiling Mode

- Add new case in argument parsing (around line 150+ in tiling.sh)
- Use existing grid calculation functions
- Call `wmctrl -ir "$ID" -b remove,maximized_vert,maximized_horz -e "..."` to move/resize

### Fixing Cross-Platform Portability

- Test with `/bin/sh` explicitly (not bash)
- Replace `[[` with `[`
- Replace `+=` with `var="$var..."` pattern
- Remove bashisms like `declare`, `>&1 2>&1` (use `> /dev/null 2>&1` instead)

## Known Limitations & Future Improvements

1. **Multi-monitor tiling**: tiling.sh treats all monitors as single logical screen; could be enhanced to detect individual monitors
2. **No test suite**: Manual verification only
3. **No installer package**: Requires manual symlink setup
4. **Limited daemon control**: No way to reload daemon without signals (could add CLI control via named pipes)
5. **Hook dependencies**: Hooks are independent; no explicit ordering or dependency system

## License & Attribution

MIT License — Copyright (c) 2026 tljm

Scripts are designed for OpenBSD; most are AI-generated (noted in README badges).
