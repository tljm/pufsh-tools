# pufsh-tools
Advanced window tiling and productivity scripts for OpenBSD.

This repository contains a collection of shell scripts designed to enhance the OpenBSD desktop experience, with a focus on advanced window management and "push" logic.

## tiling.sh
A powerful, state-aware window tiling script that supports generalized grids, progressive expansion, and segment-based sliding.

### Prerequisites
The script depends on standard X11 utilities and `wmctrl`.

**Mandatory:**
- `wmctrl`
- `xprop`
- `xwininfo`
- `jot` (standard on OpenBSD)

**Optional:**
- `xdotool` (Required for focus-tracking / mouse warping)

### Installation
1. Copy the script to your local `bin` directory:
   ```sh
   cp tiling.sh ~/bin/
   ```
2. Make it executable:
   ```sh
   chmod +x ~/bin/tiling.sh
   ```

### Usage
The script supports three main operational modes:

1. **Static Tiling**: Place windows in specific grid segments.
   - Example: `tiling.sh -h 3 1` (Left 1/3)
2. **Progressive Tiling**: "Snap and Grow" windows toward edges.
   - Example: `tiling.sh -h 3 -r` (Grow right edge to next 1/3; then follow with left edge)
3. **Slide Tiling**: Move windows by exactly one segment width/height.
   - Example: `tiling.sh -h 3 -move-r` (Shift window right by 1/3)

### Integration with cwm
The `tiling.sh` script is designed to work seamlessly with the `cwm` window manager. Below are suggested keybindings based on a production configuration:

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
MIT License
