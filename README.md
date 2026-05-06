# pufsh-tools

A collection of advanced productivity scripts and tools for OpenBSD, designed to enhance the desktop experience with a focus on window management, automation, and system integration.

## Tools Overview

### Window Tiling (`tiling.sh`)

A powerful, state-aware window tiling script that supports generalized grids, progressive expansion, and segment-based sliding. It is designed to work seamlessly with window managers like `cwm`.

**Features:**
- **Static Tiling**: Place windows in specific grid segments (e.g., left 1/3, middle 4/6).
- **Progressive Tiling**: "Snap and Grow" windows toward edges.
- **Slide Tiling**: Move windows by exactly one segment width/height without resizing.
- **Focus Tracking**: Optional mouse warping to keep focus on the tiled window.

---

### Display Management Suite

A set of scripts to handle monitor hotplugging, "ghost" screen cleanup, and UI reinitialization.

#### `screen-daemon.sh`
A background daemon intended to be started from your `.xsession`. It monitors screen state and handles UI refresh signals.
- **Periodic Check**: Every 30 seconds, it checks for "ghost" screens (outputs that are disconnected but still have active geometry) and cleans them up.
- **Signal Handling**: Responds to `SIGHUP` (manual ghost check) and `SIGUSR1` (UI refresh).

#### `screen-select.sh`
A manual tool for switching between displays or auto-configuring all connected monitors.
- **Usage**: `screen-select.sh [auto | <display_name>]`
- **Integration**: Automatically calls `screen-reinit.sh` after changes.

#### `screen-reinit.sh`
A helper script that restarts UI components (like `xphoon`, `xbattbar`, and `xscreensaver`) to ensure they correctly adapt to new screen resolutions or layouts.

---

## Installation

### 1. Prerequisites
Ensure the following tools are installed:
- `wmctrl`, `xprop`, `xwininfo`, `xrandr`
- `jot` (standard on OpenBSD)
- Optional: `xdotool` (for `tiling.sh` focus tracking)

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

#### Option C: Add to PATH
Clone the repository and add it directly to your shell's `PATH` in `~/.profile` or `~/.shrc`:
```sh
# Add to ~/.profile
export PATH="$PATH:$HOME/path/to/pufsh-tools"
```

---

## Configuration & Integration

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
