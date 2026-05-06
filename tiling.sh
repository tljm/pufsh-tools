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
# Tiling script to resize and move the active window using wmctrl and xprop.
# ==============================================================================
# 
# Usage Examples:
#
#   1. Static Tiling (Place window in specific segments):
#      tiling.sh -h 3 1       # Place in first 1/3 (left)
#      tiling.sh -h 3 1 2     # Place in first two 1/3 segments (left 2/3)
#      tiling.sh -h 6 2 5     # Place in middle 4/6 (leaves 1/6 on each side)
#      tiling.sh -h 2 1 -v 2 1 # Place in top-left quarter
#
#   2. Progressive Tiling (Grow/Shrink windows toward edges):
#      tiling.sh -h 3 -r      # Grow right edge to next 1/3; then move left edge
#      tiling.sh -v 4 -b      # Grow bottom edge to next 1/4; then move top edge
#
#   3. Slide Tiling (Move window by exactly one segment width/height):
#      tiling.sh -h 3 -move-r # Shift window right by 1/3 of screen width
#      tiling.sh -v 4 -move-t # Shift window up by 1/4 of screen height
#
#   4. Configuration Overrides:
#      tiling.sh -M 10 -h 2 1 # Use a 10px margin for this command
#      tiling.sh -TOL 1 -h 3 -r # Use a 1px snap tolerance
#      tiling.sh -nf -h 2 2   # Tile but DO NOT track focus with mouse (No Focus)
#
# ==============================================================================

# --- Default Configuration ---
M=1           # Default Margin (gap between windows)
TOL=5         # Default Tolerance in pixels for edge snapping
FOCUS_TRACK=1 # Default: Warps mouse to maintain focus (1=on, 0=off)

# --- Dependency Check ---
# Ensure all REQUIRED external tools are available on the system.
# xdotool is optional (used for focus tracking if available).
for tool in wmctrl xprop xwininfo jot; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Error: Required tool '$tool' not found. Please install it." >&2
        exit 1
    fi
done

# --- Helper Functions ---

# Prints usage instructions and examples.
show_help() {
    cat << EOF
Usage: $(basename "$0") [options] [-h splits [mode]] [-v splits [mode]]

Options:
  -M pixels       Override the default window margin (gap). Default: $M
  -TOL pixels     Override the default snap tolerance. Default: $TOL
  -nf, -no-focus  Disable mouse-based focus tracking for this command.
  --help, -help   Show this help message.

Tiling Modes:
  -h splits [start [end]]  Horizontal tiling. Split screen into 'splits' parts.
                           Optional 'start' and 'end' segments (1-indexed).
  -v splits [start [end]]  Vertical tiling. Split screen into 'splits' parts.

Special Modes (used with -h or -v):
  -l, -r, -t, -b           Progressive "Snap and Grow" toward edge.
  -move-l, -move-r, ...    Slide window by exactly one segment width/height.

Examples:
  $(basename "$0") -h 3 1              # Left 1/3
  $(basename "$0") -h 6 2 5            # Middle 4/6
  $(basename "$0") -h 3 -r             # Progressive grow right
  $(basename "$0") -h 3 -move-r        # Slide right 1/3
  $(basename "$0") -h 2 1 -v 2 1       # Top-left quarter
  $(basename "$0") -M 10 -h 2 1        # Left half with 10px margin
EOF
}

# Retrieves the hex ID of the currently focused window.
get_active_window_id() {
    id=$(xprop -root _NET_ACTIVE_WINDOW | awk '{print $NF}')
    if [ "$id" = "0x0" ] || [ -z "$id" ]; then
        echo "Error: No active window detected." >&2
        exit 1
    fi
    echo "$id"
}

# Simple numeric check for argument validation.
is_numeric() {
    case $1 in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

# --- Initial Data Gathering ---

# Identify the active window and its current dimensions.
ID=$(get_active_window_id)
INFO=$(xwininfo -id "$ID")
CUR_X=$(echo "$INFO" | grep 'Absolute upper-left X:' | awk '{print $NF}')
CUR_Y=$(echo "$INFO" | grep 'Absolute upper-left Y:' | awk '{print $NF}')
CUR_W=$(echo "$INFO" | grep 'Width:' | awk '{print $NF}')
CUR_H=$(echo "$INFO" | grep 'Height:' | awk '{print $NF}')

# Get screen resolution from the root window.
X_TOTAL=$(xwininfo -root | grep 'Width:' | awk '{print $2}')
Y_TOTAL=$(xwininfo -root | grep 'Height:' | awk '{print $2}')

# Initialize target variables with current window state (preservation mode).
FINAL_X=$CUR_X
FINAL_Y=$CUR_Y
FINAL_W=$CUR_W
FINAL_H=$CUR_H

# --- Argument Parsing Loop ---

if [ $# -lt 1 ]; then
    show_help
    exit 1
fi

while [ $# -gt 0 ]; do
    case $1 in
        --help|-help) # Show help and exit
            show_help; exit 0 ;;
        -M) # Override Margin
            M=$2; shift 2 ;;
        -TOL) # Override Tolerance
            TOL=$2; shift 2 ;;
        -nf|-no-focus) # Disable focus tracking for this command
            FOCUS_TRACK=0; shift ;;
        -h) # Horizontal Axis Operations
            shift
            SPLITS=$1; MODE=$2; THIRD=$3
            if ! is_numeric "$SPLITS"; then echo "Error: -h requires split count."; exit 1; fi
            
            case "$MODE" in
                -move-l|-move-r) # Slide Logic
                    SEG=$((X_TOTAL / SPLITS))
                    [ "$MODE" = "-move-r" ] && FINAL_X=$((CUR_X + SEG)) || FINAL_X=$((CUR_X - SEG))
                    # Clamp window within screen bounds
                    [ "$FINAL_X" -lt 0 ] && FINAL_X=0
                    MAX_X=$((X_TOTAL - CUR_W - 2*M))
                    [ "$FINAL_X" -gt "$MAX_X" ] && FINAL_X=$MAX_X
                    FINAL_W=$CUR_W
                    shift 2
                    ;;
                -l|-r) # Progressive Logic (Grow then Shrink)
                    L_EDGE=$CUR_X
                    R_EDGE=$((CUR_X + CUR_W + 2*M))
                    if [ "$MODE" = "-r" ]; then
                        FOUND=0
                        for i in $(jot $((SPLITS + 1)) 0); do
                            GRID=$(( i * X_TOTAL / SPLITS ))
                            if [ "$GRID" -gt "$((R_EDGE + TOL))" ]; then
                                FINAL_X=$L_EDGE; FINAL_W=$((GRID - L_EDGE - 2*M)); FOUND=1; break
                            fi
                        done
                        if [ $FOUND -eq 0 ]; then # Right edge is at boundary, move left edge
                            for i in $(jot $((SPLITS + 1)) 0); do
                                GRID=$(( i * X_TOTAL / SPLITS ))
                                if [ "$GRID" -gt "$((L_EDGE + TOL))" ] && [ "$GRID" -lt "$((X_TOTAL - TOL))" ]; then
                                    FINAL_X=$GRID; FINAL_W=$((X_TOTAL - GRID - 2*M)); break
                                fi
                            done
                        fi
                    else # Push Left
                        FOUND=0
                        for i in $(jot $((SPLITS + 1)) $SPLITS 0 -1); do
                            GRID=$(( i * X_TOTAL / SPLITS ))
                            if [ "$GRID" -lt "$((L_EDGE - TOL))" ]; then
                                FINAL_X=$GRID; FINAL_W=$((R_EDGE - GRID - 2*M)); FOUND=1; break
                            fi
                        done
                        if [ $FOUND -eq 0 ]; then # Left edge at boundary, move right edge
                            for i in $(jot $((SPLITS + 1)) $SPLITS 0 -1); do
                                GRID=$(( i * R_EDGE / R_EDGE )) # Dummy to prevent divide by zero
                                GRID=$(( i * X_TOTAL / SPLITS ))
                                if [ "$GRID" -lt "$((R_EDGE - TOL))" ] && [ "$GRID" -gt "$((0 + TOL))" ]; then
                                    FINAL_X=0; FINAL_W=$((GRID - 2*M)); break
                                fi
                            done
                        fi
                    fi
                    shift 2
                    ;;
                *) # Static Tiling Logic
                    if is_numeric "$MODE"; then
                        START=$MODE
                        if is_numeric "$THIRD" && [ $# -ge 3 ]; then END=$THIRD; shift 3; else END=$START; shift 2; fi
                        X_POS=$(( (START - 1) * X_TOTAL / SPLITS ))
                        W_SIZE=$(( (END * X_TOTAL / SPLITS) - X_POS ))
                        FINAL_X=$X_POS; FINAL_W=$(( W_SIZE - 2 * M ))
                    else
                        echo "Error: Invalid horizontal mode $MODE"; exit 1
                    fi
                    ;;
            esac
            ;;
        -v) # Vertical Axis Operations
            shift
            SPLITS=$1; MODE=$2; THIRD=$3
            if ! is_numeric "$SPLITS"; then echo "Error: -v requires split count."; exit 1; fi

            case "$MODE" in
                -move-t|-move-b) # Slide Logic
                    SEG=$((Y_TOTAL / SPLITS))
                    [ "$MODE" = "-move-b" ] && FINAL_Y=$((CUR_Y + SEG)) || FINAL_Y=$((CUR_Y - SEG))
                    [ "$FINAL_Y" -lt 0 ] && FINAL_Y=0
                    MAX_Y=$((Y_TOTAL - CUR_H - 2*M))
                    [ "$FINAL_Y" -gt "$MAX_Y" ] && FINAL_Y=$MAX_Y
                    FINAL_H=$CUR_H
                    shift 2
                    ;;
                -t|-b) # Progressive Logic
                    T_EDGE=$CUR_Y
                    B_EDGE=$((CUR_Y + CUR_H + 2*M))
                    if [ "$MODE" = "-b" ]; then
                        FOUND=0
                        for i in $(jot $((SPLITS + 1)) 0); do
                            GRID=$(( i * Y_TOTAL / SPLITS ))
                            if [ "$GRID" -gt "$((B_EDGE + TOL))" ]; then
                                FINAL_Y=$T_EDGE; FINAL_H=$((GRID - T_EDGE - 2*M)); FOUND=1; break
                            fi
                        done
                        if [ $FOUND -eq 0 ]; then
                            for i in $(jot $((SPLITS + 1)) 0); do
                                GRID=$(( i * Y_TOTAL / SPLITS ))
                                if [ "$GRID" -gt "$((T_EDGE + TOL))" ] && [ "$GRID" -lt "$((Y_TOTAL - TOL))" ]; then
                                    FINAL_Y=$GRID; FINAL_H=$((Y_TOTAL - GRID - 2*M)); break
                                fi
                            done
                        fi
                    else # Push Top
                        FOUND=0
                        for i in $(jot $((SPLITS + 1)) $SPLITS 0 -1); do
                            GRID=$(( i * Y_TOTAL / SPLITS ))
                            if [ "$GRID" -lt "$((T_EDGE - TOL))" ]; then
                                FINAL_Y=$GRID; FINAL_H=$((B_EDGE - GRID - 2*M)); FOUND=1; break
                            fi
                        done
                        if [ $FOUND -eq 0 ]; then
                            for i in $(jot $((SPLITS + 1)) $SPLITS 0 -1); do
                                GRID=$(( i * Y_TOTAL / SPLITS ))
                                if [ "$GRID" -lt "$((B_EDGE - TOL))" ] && [ "$GRID" -gt "$((0 + TOL))" ]; then
                                    FINAL_Y=0; FINAL_H=$((GRID - 2*M)); break
                                fi
                            done
                        fi
                    fi
                    shift 2
                    ;;
                *) # Static Tiling Logic
                    if is_numeric "$MODE"; then
                        START=$MODE
                        if is_numeric "$THIRD" && [ $# -ge 3 ]; then END=$THIRD; shift 3; else END=$START; shift 2; fi
                        Y_POS=$(( (START - 1) * Y_TOTAL / SPLITS ))
                        H_SIZE=$(( (END * Y_TOTAL / SPLITS) - Y_POS ))
                        FINAL_Y=$Y_POS; FINAL_H=$(( H_SIZE - 2 * M ))
                    else
                        echo "Error: Invalid vertical mode $MODE"; exit 1
                    fi
                    ;;
            esac
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# --- Execution Phase ---

# Final logging for user visibility.
echo "Screen Resolution: ${X_TOTAL}x${Y_TOTAL}"
echo "Window ID: $ID"
echo "Initial Geometry: X=$CUR_X, Y=$CUR_Y, W=$CUR_W, H=$CUR_H"
echo "Final Geometry:   X=$FINAL_X, Y=$FINAL_Y, W=$FINAL_W, H=$FINAL_H"

# Apply the calculated geometry using wmctrl.
wmctrl -i -r "$ID" -e "0,$FINAL_X,$FINAL_Y,$FINAL_W,$FINAL_H"

# Optional focus tracking: Warp mouse to the center of the window.
# Only runs if FOCUS_TRACK is enabled (default) AND xdotool is available.
if [ "$FOCUS_TRACK" = "1" ]; then
    if command -v xdotool >/dev/null 2>&1; then
        xdotool mousemove --window "$ID" $((FINAL_W / 2)) $((FINAL_H / 2))
    else
        echo "Warning: xdotool not found. Focus tracking skipped (use -nf to silence this warning)." >&2
    fi
fi

exit 0
