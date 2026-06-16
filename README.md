# pufsh-tools

![License](https://img.shields.io/github/license/tljm/pufsh-tools)
![Platform](https://img.shields.io/badge/platform-OpenBSD-blue)
![Language](https://img.shields.io/github/languages/top/tljm/pufsh-tools)
![GitHub last commit](https://img.shields.io/github/last-commit/tljm/pufsh-tools)
![AI Generated](https://img.shields.io/badge/AI%20Generated-99%25-blueviolet)

A collection of advanced productivity scripts and tools for OpenBSD, designed to enhance the desktop experience with a focus on window management, automation, and system integration.

## Tools Overview

### Window Tiling (`tiling.sh`)

A powerful, state-aware window tiling script that supports generalized grids, progressive expansion, and segment-based sliding. It is designed to work seamlessly with window managers like `cwm`.

**Features:**
- **Static Tiling**: Place windows in specific grid segments (e.g., left 1/3, middle 4/6).
- **Progressive Tiling**: "Snap and Grow" windows toward edges.
- **Slide Tiling**: Move windows by exactly one segment width/height without resizing.
- **Focus Tracking**: Warps mouse to maintain focus (Default: Enabled).
- **Smart Defaults**: 1px Margin (gap), 5px Snap Tolerance.

---

### Display Management Suite

A set of scripts to handle monitor hotplugging, "ghost" screen cleanup, and UI reinitialization.

#### `screen-daemon.sh`
A background daemon intended to be started from your `.xsession`. It monitors screen state, handles UI refresh signals, and manages power inhibition.
- **Usage**: `screen-daemon.sh [-g ghost_seconds] [-i inhibit_seconds]`
- **Suspend Mode**: When in suspend mode (triggered by `SIGUSR2`), only the built-in screen is kept active, and other checks are paused. `SIGHUP` exits suspend mode.
- **Ghost Screen Cleanup**: Checks for outputs that are disconnected but still have active geometry. Default interval: 10 seconds (configurable with `-g`).
- **xscreensaver Inhibition**: Checks if audio is playing (via `sndio`) and the active window is fullscreen; if so, it inhibits `xscreensaver` blanking. Default interval: 60 seconds (configurable with `-i`).
- **Lid Management**: If `machdep.lidaction=0` and the lid is closed, it automatically disables the built-in screen and enables all other connected displays (periodic check every 10s).
- **Signal Handling**: Responds to `SIGHUP` (manual ghost check, exits suspend mode) and `SIGUSR1` (UI refresh). Use `SIGUSR2` (31) to enter suspend mode, which keeps only the built-in screen active and disables other checks.


#### `screen-select.sh`
A manual tool for switching between displays or auto-configuring all connected monitors.
- **Usage**: `screen-select.sh [auto | <display_name>]`
- **Integration**: Automatically calls `screen-reinit.sh` after changes.

#### `screen-reinit.sh`
A modular framework that executes reinitialization hooks to ensure UI components correctly adapt to new screen resolutions or layouts.

- **Hook System**: Executes all executable scripts found in the `screen-reinit.d/` directory.
- **Customization**: All hooks are optional and intended to be adapted or added to based on your specific desktop needs.
- **Example Hooks included**:
    - `10-xphoon`: Manages background/wallpaper.
    - `20-xbattbar`: Manages battery monitoring bar.
    - `30-xscreensaver`: Ensures screensaver daemon is active.
    - `40-console-move`: Automatically moves `xconsole` to the bottom-right corner.
- **Symlink Support**: Correctly resolves its physical location to find hooks even when invoked via a symlink in `PATH`.

---

### Backup Utility (`make_backup.sh`)
A versatile backup script that creates timestamped, high-compression archives of the current directory.

**Usage Pattern:**
This script is designed to be kept in your backup destination folder (e.g., `~/backups/`). When you want to back up a project, you invoke the script from that project's directory. By default, it saves the resulting archive in the same folder where the script itself is located.

```sh
cd ~/projects/my-cool-project
~/backups/make_backup.sh -p -t tar.xz
```

**Features:**
- **Multiple Formats**: Supports `tar`, `tar.gz` (default), `tar.bz2`, `tar.xz`, `tar.bz3`, `7z`, and `tar.7z`.
- **Parallel Compression**: Uses multiple CPU cores for `xz`, `bz3`, and `7z` (and `pigz`/`pbzip2` if available) via the `-p` flag.
- **Adjustable Compression**: Set levels 1-9 (default 6) via the `-l` flag.
- **Smart Defaults**: Defaults to the folder where the script resides, making it easy to centralize backups.
- **Statistics**: Provides original vs. compressed size, space saved, and time taken.
- **Dry Run**: Preview the exact command that will be executed with the `-n` flag.

---

## Installation

### 1. Prerequisites
Ensure the following tools are installed:
- `wmctrl`, `xprop`, `xwininfo`, `xrandr`, `realpath`
- `jot`, `du`, `awk`, `date` (standard on OpenBSD)
- Archive tools for `make_backup.sh`: `7z`, `xz`, `bzip3`, `gzip`, `bzip2`
- Optional: `xdotool` (for `tiling.sh` focus tracking), `pigz`, `pbzip2` (for parallel gzip/bzip2)

### 2. Deployment Alternatives

Choose the method that best fits your workflow:

#### Option A: Manual Copy
Copy the scripts to a directory in your `PATH` (e.g., `~/bin`):
```sh
cp *.sh ~/bin/
chmod +x ~/bin/*.sh
```

#### Option B: Clone and Link
Clone the repository and create symbolic links to a location in your `PATH`. This allows you to update the tools easily with `git pull`:
```sh
git clone https://github.com/tljm/pufsh-tools.git ~/.local/lib/pufsh-tools
ln -s ~/.local/lib/pufsh-tools/*.sh ~/bin/
```

**Tip for `make_backup.sh`:**
You can also symlink this script specifically into your dedicated backup folder. It will respect the symlink location and save archives there:
```sh
ln -s ~/.local/lib/pufsh-tools/make_backup.sh ~/backups/
```

#### Option C: Add to PATH
Clone the repository and add it directly to your shell's `PATH` in `~/.profile` or `~/.shrc`:
```sh
# Add to ~/.profile
export PATH="$PATH:$HOME/path/to/pufsh-tools"
```

---

## Configuration & Integration

### APMD Hook Integration (`/etc/apm` hooks)
On OpenBSD, `apmd` (Advanced Power Management daemon) can execute scripts in `/etc/apm` during suspend and resume events. For systems with external monitors, configuring these hooks can sometimes prevent system hangs or display issues when suspending or resuming with an external screen connected.

For example, you might use `/etc/apm/suspend` to disable external displays before suspend and `/etc/apm/resume` to re-enable them (or call `screen-select.sh auto`) after resume, ensuring a smoother transition. Consult the `apmd(8)` and `apm(4)` man pages for more details on configuring these hooks.

```sh
#!/bin/sh
# Example: /etc/apm/suspend
# This script will be executed by apmd when the system suspends.
/usr/bin/pkill -USR2 -f screen-daemon.sh
/bin/sleep 5
/usr/bin/pkill -USR1 xidle
/bin/sleep 1
```

```sh
#!/bin/sh
# Example: /etc/apm/resume
# This script will be executed by apmd when the system resumes.
/usr/bin/pkill -HUP -f screen-daemon.sh
/bin/sleep 1
/usr/bin/pkill -USR1 -f screen-daemon.sh
```

---

### .xsession Setup
To use the display management suite, add the daemon to your `.xsession` file:
```sh
# Start the screen management daemon
screen-daemon.sh &

# Initial display auto-config (optional)
screen-select.sh auto

exec cwm
```

### cwm Integration (`.cwmrc`)
The `tiling.sh` script is designed to work seamlessly with `cwm`. Below are comprehensive suggested keybindings:

```cwmrc
# Progressive Tiling (Grow/Shrink)
bind-key 4-l      "tiling.sh -h 4 -r"
bind-key 4-h      "tiling.sh -h 4 -l"
bind-key 4-j      "tiling.sh -v 4 -b"
bind-key 4-k      "tiling.sh -v 4 -t"

# Progressive Tiling (Denser Grid)
bind-key 4-o      "tiling.sh -h 6 -r"
bind-key 4-y      "tiling.sh -h 6 -l"
bind-key 4-u      "tiling.sh -v 6 -b"
bind-key 4-i      "tiling.sh -v 6 -t"

# Slide Tiling (Nudge by segment)
bind-key 4S-l     "tiling.sh -h 8 -move-r"
bind-key 4S-h     "tiling.sh -h 8 -move-l"
bind-key 4S-j     "tiling.sh -v 8 -move-b"
bind-key 4S-k     "tiling.sh -v 8 -move-t"

# Slide Tiling (Denser Grid)
bind-key 4S-o     "tiling.sh -h 12 -move-r"
bind-key 4S-y     "tiling.sh -h 12 -move-l"
bind-key 4S-u     "tiling.sh -v 12 -move-b"
bind-key 4S-i     "tiling.sh -v 12 -move-t"
```

## License
MIT License - Copyright (c) 2026 tljm
