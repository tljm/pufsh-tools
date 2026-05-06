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
# screen-daemon.sh - Background daemon for screen events (signals/traps)
# ==============================================================================
# 
# This script is intended to be run from your .xsession file:
#   screen-daemon.sh &
#
# It performs two main functions:
#   1. Responds to signals:
#      - SIGHUP (1):  Checks for "ghost" (disconnected but active) screens.
#      - SIGUSR1 (30): Triggers a UI reinitialization.
#   2. Periodic Checks:
#      - Automatically checks for ghost screens every 30 seconds.
#
# ==============================================================================

# --- Helper Functions ---

show_help() {
    cat << EOF
Usage: $(basename "$0") [options]

Background daemon for managing screen state and UI reinitialization.

Options:
  -h, --help    Show this help message and exit.

Signals:
  SIGHUP (1)    Trigger a manual 'ghost screen' check.
  SIGUSR1 (30)  Trigger a UI component refresh via screen-reinit.sh.

Note: This script is typically started in the background from .xsession.
EOF
}

# --- Argument Parsing ---

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

# --- Initialization ---

# Resolve absolute paths to helper scripts
SELECT_SCRIPT=$(command -v screen-select.sh)
REINIT_SCRIPT=$(command -v screen-reinit.sh)

if [ -z "$SELECT_SCRIPT" ] || [ -z "$REINIT_SCRIPT" ]; then
    echo "Error: Required helper scripts (screen-select.sh or screen-reinit.sh) not found in PATH."
    exit 1
fi

# --- Core Logic ---

# Logic for "smart" reload (triggered by SIGHUP or periodic timer)
reload_config() {
    SOURCE=${1:-SIGHUP}
    echo "[$SOURCE] Checking for ghost screens..."
    
    # Identify outputs that are disconnected but still have active geometry
    GHOST_SCREENS=$(xrandr | awk '/ disconnected/ && /[0-9]+x[0-9]+/ {print $1}')

    if [ -n "$GHOST_SCREENS" ]; then
        echo "Detected disconnected screen(s): $GHOST_SCREENS"
        $SELECT_SCRIPT auto
    else
        # Only log periodic checks if a screen was actually cleaned up to keep logs quiet
        if [ "$SOURCE" = "SIGHUP" ]; then
            echo "No ghost screens detected. System state looks clean."
        fi
    fi
}

# Logic for UI refresh (SIGUSR1)
refresh_ui() {
    echo "[SIGUSR1] Received. Refreshing UI components..."
    $REINIT_SCRIPT
}

# --- Signal Registration ---

trap 'reload_config SIGHUP' HUP
trap 'refresh_ui' USR1

echo "Screen daemon started. PID: $$"

# --- Main Loop ---

# Keep the script alive and run periodic checks every 30 seconds.
# Using background sleep + wait allows the script to remain responsive to signals.
while true; do
    sleep 30 &
    wait $!
    reload_config "PERIODIC"
done
