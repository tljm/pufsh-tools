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
# screen-select.sh - Manually select or auto-configure display outputs
# ==============================================================================
#
# This script allows you to quickly switch between connected monitors or
# auto-configure the display setup using xrandr.
#
# ==============================================================================

# --- Data Gathering ---

# Get all outputs, their status (connected/disconnected), and if they have an active resolution (on/off)
# Example xrandr output line: "eDP-1 connected primary 1920x1080+0+0 ..."
ALL_OUTPUTS_INFO=$(xrandr | awk '/connected/ {
    name=$1;
    status=$2;
    active="off";
    for(i=3; i<=NF; i++) {
        if($i ~ /^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+$/) {
            active="on";
            break;
        }
    }
    print name, status, active;
}')
CONNECTED_OUTPUTS=$(echo "$ALL_OUTPUTS_INFO" | awk '$2 == "connected" {print $1}')
DISCONNECTED_OUTPUTS=$(echo "$ALL_OUTPUTS_INFO" | awk '$2 == "disconnected" {print $1}')

# Detect built-in display (eDP, LVDS, DSI)
BUILTIN_SCREEN=$(xrandr | grep -E "^(eDP|LVDS|DSI)" | awk '{print $1}' | head -n 1)

# --- Configuration ---
LOG_TS_FORMAT='+%Y-%m-%d %H:%M:%S'

# --- Helper Functions ---

# Centralized logging with timestamps.
log() {
    echo "[$(date "$LOG_TS_FORMAT")] $*"
}

# Helper function to get current geometry from a connected display
get_current_geometry() {
    target=$1
    geo=$(xrandr | awk -v target="$target" '
        /^[^ ]/ {
            if ($1 == target) {
                flag=1
            } else {
                flag=0
            }
            next
        }
        flag && /^[ ]+([0-9]+x[0-9]+|[a-fA-F0-9]+x[a-fA-F0-9]+)/ {
            split($1, parts, "x")
            w = parts[1]
            h = parts[2]
            found=1
            print w, h
            exit
        }
        END {
            if (found != 1) print "0 0"
        }
    ')
    if [ -n "$geo" ]; then
        echo "$geo"
    else
        echo "0 0"
    fi
}

show_help() {
    cat << EOF
Usage: $(basename "$0") [auto | auto-external | <display_name>]

Options:
  -h, --help    Show this help message and exit.

Arguments:
  auto          Automatically configure all connected displays.
  auto-external Automatically configure external displays and turn off built-in.
  builtin-only  Enable the built-in display and turn off all other displays.
  display_name  Specify a single display to enable (all others will be turned off).

Available displays:
EOF
    if [ -n "$ALL_OUTPUTS_INFO" ]; then
        echo "$ALL_OUTPUTS_INFO" | while read -r name status active; do
            INTERNAL_TAG=""
            [ "$name" = "$BUILTIN_SCREEN" ] && INTERNAL_TAG=" (internal)"
            
            if [ "$status" = "connected" ]; then
                printf "  - %-12s (connected, %s)%s\n" "$name" "$active" "$INTERNAL_TAG"
            else
                printf "  - %-12s (disconnected)%s\n" "$name" "$INTERNAL_TAG"
            fi
        done
    else
        echo "  (None detected)"
    fi
}

# --- Argument Parsing ---

MODE=$1

# If no argument or help flag, show help
if [ -z "$MODE" ] || [ "$MODE" = "-h" ] || [ "$MODE" = "--help" ]; then
    show_help
    exit 0
fi

# --- Execution ---

# Cleanup other instances of screen scripts (but not the daemon)
# This prevents race conditions if multiple selection commands are run rapidly.
# Use full command matching to avoid terminating unrelated processes.
DAEMON_PID=$(pgrep -f screen-daemon.sh)
for pid in $(pgrep -f "screen-select.sh$|screen-reinit.sh$"); do
    if [ "$pid" != "$$" ] && [ "$pid" != "$DAEMON_PID" ]; then
        kill -9 "$pid" 2>/dev/null
    fi
done

if [ "$MODE" = "auto" ]; then
    log "Auto-configuring all connected displays..."
    (
        set --
        for out in $CONNECTED_OUTPUTS; do
            set -- "$@" --output "$out" --auto
        done
        if [ "$#" -gt 0 ]; then
            xrandr "$@"
        else
            log "No connected displays found to auto-configure." >&2
        fi
    )

elif [ "$MODE" = "auto-external" ]; then
    log "Auto-configuring external displays..."
    # Find the first connected output that is NOT the built-in screen
    PRIMARY_EXTERNAL=""
    for out in $CONNECTED_OUTPUTS; do
        if [ "$out" != "$BUILTIN_SCREEN" ]; then
            PRIMARY_EXTERNAL="$out"
            break
        fi
    done

    if [ -n "$PRIMARY_EXTERNAL" ]; then
        (
            set -- --output "$PRIMARY_EXTERNAL" --primary --auto
            for out in $CONNECTED_OUTPUTS; do
                if [ "$out" = "$BUILTIN_SCREEN" ]; then
                    set -- "$@" --output "$out" --off
                elif [ "$out" != "$PRIMARY_EXTERNAL" ]; then
                    set -- "$@" --output "$out" --auto
                fi
            done
            xrandr "$@"
        )
    else
        log "Error: No external displays connected." >&2
        xrandr --auto
    fi
elif [ "$MODE" = "builtin-only" ]; then
    log "Switching to built-in screen only..."
    if [ -n "$BUILTIN_SCREEN" ]; then
        FB_GEOMETRY=$(get_current_geometry "$BUILTIN_SCREEN")
        FB_W=$(echo "$FB_GEOMETRY" | awk '{print $1}')
        FB_H=$(echo "$FB_GEOMETRY" | awk '{print $2}')
        if [ "$FB_W" -gt 0 ] && [ "$FB_H" -gt 0 ]; then
            (
                set -- --output "$BUILTIN_SCREEN" --fb "${FB_W}x${FB_H}" --primary --auto
                for out in $CONNECTED_OUTPUTS; do
                    if [ "$out" != "$BUILTIN_SCREEN" ]; then
                        set -- "$@" --output "$out" --off
                    fi
                done
                xrandr "$@"
            )
        fi
    else
        log "Error: Built-in screen not detected." >&2
        exit 1
    fi
else
    # Single display name specified
    log "Switching to display: $MODE"
    if [ -n "$MODE" ]; then
        FB_GEOMETRY=$(get_current_geometry "$MODE")
        FB_W=$(echo "$FB_GEOMETRY" | awk '{print $1}')
        FB_H=$(echo "$FB_GEOMETRY" | awk '{print $2}')
        if [ "$FB_W" -gt 0 ] && [ "$FB_H" -gt 0 ]; then
            (
                set -- --output "$MODE" --fb "${FB_W}x${FB_H}" --primary --auto
                for out in $CONNECTED_OUTPUTS; do
                    if [ "$out" != "$MODE" ]; then
                        set -- "$@" --output "$out" --off
                    fi
                done
                xrandr "$@"
            )
        fi
    else
        log "Error: No display specified." >&2
        exit 1
    fi
fi

# --- Initialization ---

# Ensure standard and common local paths are available
for path in /usr/local/bin /usr/X11R6/bin "$HOME/bin" "$HOME/.local/bin"; do
    case ":$PATH:" in
        *":$path:"*) ;;
        *) [ -d "$path" ] && PATH="$PATH:$path" ;;
    esac
done
export PATH

SELF_PATH=$(command -v "$0" 2>/dev/null)
[ -z "$SELF_PATH" ] && SELF_PATH="./$0"
SCRIPT_DIR=$(dirname "$(realpath "$SELF_PATH" 2>/dev/null || echo "$SELF_PATH")")

# Reinitialize UI components (wallpaper, bars, etc.)
REINIT_SCRIPT=""
if command -v screen-reinit.sh >/dev/null 2>&1; then
    REINIT_SCRIPT=$(command -v screen-reinit.sh)
elif [ -f "$SCRIPT_DIR/screen-reinit.sh" ]; then
    REINIT_SCRIPT="$SCRIPT_DIR/screen-reinit.sh"
fi

if [ -n "$REINIT_SCRIPT" ]; then
    # Only reinit if there's at least one active display
    if xrandr | grep -q "[0-9]x[0-9]"; then
        "$REINIT_SCRIPT"
    else
        log "All displays are off. Skipping UI refresh."
    fi
else
    log "Warning: screen-reinit.sh not found. UI refresh skipped." >&2
fi
