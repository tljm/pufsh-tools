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
# This script acts as a framework that executes reinitialization hooks found
# in the screen-reinit.d directory alongside this script.
#
# ==============================================================================

# --- Configuration ---
LOG_TS_FORMAT='+%Y-%m-%d %H:%M:%S'
: "${PUFSH_SCREEN_LOG:=${PUFSH_SCREEN_LOG:-}}"

# Centralized logging with timestamps.
# If PUFSH_SCREEN_LOG is set, messages are also appended to a file.
# By default, all log output goes to stderr.
log() {
    local prefix="$*"
    echo "[$(date "$LOG_TS_FORMAT")] $prefix" >&2
    if [ -n "$PUFSH_SCREEN_LOG" ]; then
        local base="${0##*/}"
        local log_file="$PUFSH_SCREEN_LOG/pufsh-${base%.*}.log"
        mkdir -p "$(dirname "$log_file")" 2>/dev/null
        printf "[$(date "$LOG_TS_FORMAT")] %s\n" "$prefix" >> "$log_file" 2>/dev/null
    fi
}

show_help() {
    cat << EOF
Usage: $(basename "$0") [options]

Executes all reinitialization hooks in the screen-reinit.d directory.
Hooks are used to restart UI components (like backgrounds, bars, etc.)
to adapt to new display settings.

Options:
  -h, --help    Show this help message and exit.

Note: This script is typically called automatically by screen-select.sh or screen-daemon.sh.
EOF
}

# --- Initialization ---

# Ensure standard and common local paths are available
for path in /usr/local/bin /usr/X11R6/bin "$HOME/bin" "$HOME/.local/bin"; do
    case ":$PATH:" in
        *":$path:"*) ;;
        *) [ -d "$path" ] && PATH="$PATH:$path" ;;
    esac
done
export PATH

# --- Argument Parsing ---

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

# --- Framework Logic ---

# Resolve the physical location of this script to find hooks.
# We use realpath (standard on OpenBSD) to correctly handle symlinks.
# Note: Pure POSIX alternatives involve using 'cd' and 'ls -l' loops.
SELF_REAL=$(realpath "$0" 2>/dev/null || echo "$0")
SCRIPT_DIR=$(dirname "$SELF_REAL")
HOOKS_DIR="$SCRIPT_DIR/screen-reinit.d"

if [ ! -d "$HOOKS_DIR" ]; then
    # Exit gracefully if hooks directory is missing
    exit 0
fi

log "[INFO] Refreshing UI components via hooks in $HOOKS_DIR..." >&2

# Loop through all executable files in the hooks directory, sorted numerically/alphabetically
# As per AGENTS.md, non-zero exit from a hook should stop further processing.
# Use while IFS= read -r to safely handle filenames with spaces or special characters.
find "$HOOKS_DIR" -maxdepth 1 -type f | sort | while IFS= read -r hook; do
    if [ -x "$hook" ]; then
    log "[Info] [Framework] Executing hook: $(basename "$hook")" >&2
    if ! "$hook"; then
        log "[Error] [Framework] Hook $(basename "$hook") failed with exit code $?. Aborting UI reinitialization." >&2
        exit 1 # Abort further processing as per documentation
    fi
    fi
done

log "[INFO] UI reinitialization complete." >&2
