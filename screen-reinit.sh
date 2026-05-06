#!/bin/sh

# ==============================================================================
# Copyright (c) 2026 tljm
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# ==============================================================================

# ==============================================================================
# screen-reinit.sh - Reinitialize UI components after resolution/output changes
# ==============================================================================
#
# This script restarts various UI components (backgrounds, bars, savers) to
# ensure they correctly adapt to new screen dimensions or active outputs.
#
# ==============================================================================

# --- Helper Functions ---

show_help() {
    cat << EOF
Usage: $(basename "$0") [options]

Restarts UI components (xphoon, xbattbar) and ensures xscreensaver is running
to adapt to new display settings.

Options:
  -h, --help    Show this help message and exit.

Note: This script is typically called automatically by screen-select.sh or screen-daemon.sh.
EOF
}

# --- Argument Parsing ---

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

# --- Reinitialization Logic ---

echo "Refreshing UI components..."

# 1. Restart xphoon (Background/Wallpaper)
# xphoon provides a tiled moon background.
pkill xphoon
xphoon -t 10 &

# 2. Restart xbattbar (Battery Bar)
# -a: AC/Battery status, -t: thickness, -T: show on top of windows, -O: color
pkill xbattbar
xbattbar -a -t 2 -T -O yellow bottom 1>/dev/null 2>&1 &

# 3. Ensure xscreensaver is running
# We only start xscreensaver if it isn't already active.
if ! pgrep -x xscreensaver >/dev/null; then
    xscreensaver --no-splash 1>/dev/null 2>&1 &
fi

echo "UI reinitialization complete."
