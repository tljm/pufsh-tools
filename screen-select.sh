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

# Get all outputs and their status (connected/disconnected)
ALL_OUTPUTS_INFO=$(xrandr | awk '/^(.*) (dis)?connected/ {print $1, $2}')
CONNECTED_OUTPUTS=$(echo "$ALL_OUTPUTS_INFO" | awk '$2 == "connected" {print $1}')

# --- Helper Functions ---

show_help() {
    cat << EOF
Usage: $(basename "$0") [auto | <display_name>]

Options:
  -h, --help    Show this help message and exit.

Arguments:
  auto          Automatically configure all connected displays.
  display_name  Specify a single display to enable (all others will be turned off).

Available displays:
EOF
    if [ -n "$ALL_OUTPUTS_INFO" ]; then
        echo "$ALL_OUTPUTS_INFO" | while read -r name status; do
            if [ "$status" = "connected" ]; then
                printf "  - %-12s (connected)\n" "$name"
            else
                printf "  - %-12s (disconnected)\n" "$name"
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
DAEMON_PID=$(pgrep -f screen-daemon.sh)
for pid in $(pgrep -f "screen-"); do
    if [ "$pid" != "$$" ] && [ "$pid" != "$DAEMON_PID" ]; then
        kill -9 "$pid" 2>/dev/null
    fi
done

if [ "$MODE" = "auto" ]; then
    echo "Auto-configuring displays..."
    xrandr --auto
else
    # Verify if the requested display is valid and connected
    FOUND=0
    for out in $CONNECTED_OUTPUTS; do
        if [ "$out" = "$MODE" ]; then
            FOUND=1
            break
        fi
    done

    if [ "$FOUND" -eq 1 ]; then
        echo "Switching to $MODE..."
        
        # Build xrandr arguments safely using positional parameters
        # We do this in a subshell to avoid overwriting our own $1, $2, etc.
        (
            set -- --output "$MODE" --primary --auto
            for out in $CONNECTED_OUTPUTS; do
                if [ "$out" != "$MODE" ]; then
                    set -- "$@" --output "$out" --off
                fi
            done
            xrandr "$@"
        )
    else
        echo "Error: Display '$MODE' not found or not connected."
        echo ""
        show_help
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
    "$REINIT_SCRIPT"
else
    echo "Warning: screen-reinit.sh not found. UI refresh skipped."
fi
