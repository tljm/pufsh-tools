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
# screen-daemon.sh - Background daemon for screen events and power management
# ==============================================================================
# 
# This script is intended to be run from your .xsession file:
#   screen-daemon.sh &
#
# It performs three main functions:
#   1. Signal Handling:
#      - SIGHUP (1):  Manual check for "ghost" (disconnected but active) screens.
#      - SIGUSR1 (30): Triggers a UI reinitialization.
#   2. Ghost Screen Cleanup:
#      - Automatically checks for and cleans up ghost screens every 30 seconds.
#   3. xscreensaver Inhibition:
#      - Prevents screen blanking when audio is playing (via sndio) and the
#        active window is in Fullscreen mode.
#
# ==============================================================================

# --- Defaults ---
GHOST_PERIOD=10
INHIBIT_PERIOD=60

# --- Helper Functions ---

# Simple numeric check for argument validation.
is_numeric() {
    case $1 in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

show_help() {
    cat << EOF
Usage: $(basename "$0") [options]

Background daemon for screen state, UI reinitialization, and power management.

Options:
  -h            Show this help message and exit.
  -g seconds    Interval for periodic ghost screen checks (default: $GHOST_PERIOD).
  -i seconds    Interval for xscreensaver inhibition checks (default: $INHIBIT_PERIOD).

Signals:
  SIGHUP (1)    Trigger a manual 'ghost screen' check.
  SIGUSR1 (30)  Trigger a UI component refresh via screen-reinit.sh.

Note: This script is typically started in the background from .xsession.
EOF
}

# --- Argument Parsing ---

while getopts "hg:i:" opt; do
    case "$opt" in
        h) show_help; exit 0 ;;
        g) 
            if is_numeric "$OPTARG"; then
                GHOST_PERIOD=$OPTARG
            else
                echo "Error: -g requires a numeric argument." >&2; exit 1
            fi
            ;;
        i) 
            if is_numeric "$OPTARG"; then
                INHIBIT_PERIOD=$OPTARG
            else
                echo "Error: -i requires a numeric argument." >&2; exit 1
            fi
            ;;
        *) show_help; exit 1 ;;
    esac
done

# --- Initialization ---

# Ensure standard and common local paths are available
for path in /usr/local/bin /usr/X11R6/bin "$HOME/bin" "$HOME/.local/bin"; do
    case ":$PATH:" in
        *":$path:"*) ;;
        *) [ -d "$path" ] && PATH="$PATH:$path" ;;
    esac
done
export PATH

# Resolve absolute paths to helper scripts
# Find where this script is located
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

SELECT_SCRIPT=$(find_script screen-select.sh)
REINIT_SCRIPT=$(find_script screen-reinit.sh)

# Detect built-in display (eDP, LVDS, DSI)
BUILTIN_SCREEN=$(xrandr | grep -E "^(eDP|LVDS|DSI)" | awk '{print $1}' | head -n 1)

# Detect lid sensor
LID_SENSOR=$(sysctl hw.sensors 2>/dev/null | grep -i "lid" | cut -d= -f1 | head -n 1)

# Dependency Check
MISSING=""
for tool in xrandr sndioctl xprop xscreensaver-command; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        MISSING="$MISSING $tool"
    fi
done

if [ -n "$MISSING" ]; then
    echo "Error: Required tools not found in PATH:$MISSING" >&2
    exit 1
fi

if [ -z "$SELECT_SCRIPT" ] || [ -z "$REINIT_SCRIPT" ]; then
    echo "Error: Required helper scripts (screen-select.sh or screen-reinit.sh) not found." >&2
    exit 1
fi

# --- Core Logic ---

# Logic for "smart" reload (triggered by SIGHUP or periodic timer)
reload_config() {
    SOURCE=${1:-SIGHUP}
    [ "$SOURCE" = "SIGHUP" ] && echo "[$SOURCE] Checking for screen events..."
    
    # 1. Check for Lid State if machdep.lidaction is 0
    LID_CLOSED=0
    if [ -n "$LID_SENSOR" ] && [ "$(sysctl -n machdep.lidaction 2>/dev/null)" = "0" ]; then
        LID_STATE=$(sysctl -n "$LID_SENSOR" 2>/dev/null)
        # Check for 'Off' (closed) in the output
        case "$LID_STATE" in
            Off*) LID_CLOSED=1 ;;
        esac
    fi

    # 2. Identify screen events
    # Ghost Screens: disconnected but still have active geometry
    GHOST_SCREENS=$(xrandr | awk '/ disconnected/ && /[0-9]+x[0-9]+/ {print $1}')
    
    # Inactive Screens: connected but currently off (no resolution)
    # If lid is closed, we ignore the builtin screen here (it's handled specifically)
    # If lid is open, we include it so it can be auto-enabled
    if [ "$LID_CLOSED" -eq 1 ]; then
        INACTIVE_SCREENS=$(xrandr | awk -v builtin="$BUILTIN_SCREEN" \
            '$1 != builtin && / connected/ && !/[0-9]+x[0-9]+/ {print $1}')
    else
        INACTIVE_SCREENS=$(xrandr | awk '/ connected/ && !/[0-9]+x[0-9]+/ {print $1}')
    fi

    if [ "$LID_CLOSED" -eq 1 ] && [ -n "$BUILTIN_SCREEN" ]; then
        # Check if built-in is active
        BUILTIN_ACTIVE=0
        if xrandr | grep "^$BUILTIN_SCREEN" | grep -q "[0-9]x[0-9]"; then
            BUILTIN_ACTIVE=1
        fi
        
        if [ "$BUILTIN_ACTIVE" -eq 1 ] || [ -n "$GHOST_SCREENS" ] || [ -n "$INACTIVE_SCREENS" ]; then
            [ "$BUILTIN_ACTIVE" -eq 1 ] && echo "[$SOURCE] Lid is closed but built-in screen is still active."
            [ -n "$INACTIVE_SCREENS" ] && echo "[$SOURCE] Lid is closed and new external screen(s) detected: $INACTIVE_SCREENS"
            [ -n "$GHOST_SCREENS" ] && echo "[$SOURCE] Lid is closed and ghost screen(s) detected: $GHOST_SCREENS"
            
            xrandr --auto --output "$BUILTIN_SCREEN" --off
            $REINIT_SCRIPT
        fi
    elif [ -n "$GHOST_SCREENS" ] || [ -n "$INACTIVE_SCREENS" ]; then
        if [ -n "$GHOST_SCREENS" ]; then
            echo "[$SOURCE] Detected disconnected screen(s): $GHOST_SCREENS"
        else
            echo "[$SOURCE] Detected inactive connected screen(s): $INACTIVE_SCREENS"
        fi
        $SELECT_SCRIPT auto
    else
        # Only log periodic checks if a screen was actually cleaned up to keep logs quiet
        if [ "$SOURCE" = "SIGHUP" ]; then
            echo "[$SOURCE] No screen events detected. System state looks clean."
        fi
    fi
}

# Logic for xscreensaver inhibition
# Deactivates screensaver if audio is playing and active window is fullscreen.
inhibit_screensaver() {
    # 1. Check for audio via sndio
    if sndioctl | grep -q '^app/'; then
        # 2. Check for active window ID
        ACTIVE_WIN=$(xprop -root _NET_ACTIVE_WINDOW | awk '{print $5}' | sed 's/,//')
        
        if [ -n "$ACTIVE_WIN" ] && [ "$ACTIVE_WIN" != "0x0" ]; then
            # 3. Check if that window is fullscreen
            if xprop -id "$ACTIVE_WIN" _NET_WM_STATE | grep -q "FULLSCREEN"; then
                echo "[INHIBITOR] Audio + Fullscreen detected. Deactivating xscreensaver."
                xscreensaver-command -deactivate >/dev/null 2>&1
            fi
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

# --- Main Loop ---

# Use the smaller of the two intervals as our base "tick"
TICK=$INHIBIT_PERIOD
[ "$GHOST_PERIOD" -lt "$TICK" ] && TICK=$GHOST_PERIOD

echo "Screen daemon started. PID: $$ (Tick: ${TICK}s, Inhibit: ${INHIBIT_PERIOD}s, Ghost: ${GHOST_PERIOD}s)"

INHIBIT_TIMER=0
GHOST_TIMER=0

while true; do
    # Run xscreensaver inhibitor
    INHIBIT_TIMER=$((INHIBIT_TIMER + TICK))
    if [ "$INHIBIT_TIMER" -ge "$INHIBIT_PERIOD" ]; then
        inhibit_screensaver
        INHIBIT_TIMER=0
    fi

    # Run periodic ghost screen check
    GHOST_TIMER=$((GHOST_TIMER + TICK))
    if [ "$GHOST_TIMER" -ge "$GHOST_PERIOD" ]; then
        reload_config "PERIODIC"
        GHOST_TIMER=0
    fi

    # Sleep for our base tick interval
    # Use a background sleep and wait so signals can interrupt it.
    sleep "$TICK" &
    SLEEP_PID=$!
    wait $SLEEP_PID
    # If wait returns (either sleep finished or signal caught),
    # ensure we don't leave orphaned sleep processes.
    kill $SLEEP_PID 2>/dev/null
done
