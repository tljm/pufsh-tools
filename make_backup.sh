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
# make_backup.sh - Create a compressed archive of the current directory
# ==============================================================================
#
# This script creates a timestamped archive of the directory it is invoked from.
# Supports multiple formats and compression levels.
#
# Usage:
#   make_backup.sh [options]
#
# ==============================================================================

# --- Initialization ---

# Ensure standard and common local paths are available
for path in /usr/local/bin /usr/X11R6/bin "$HOME/bin" "$HOME/.local/bin"; do
    case ":$PATH:" in
        *":$path:"*) ;;
        *) [ -d "$path" ] && PATH="$PATH:$path" ;;
    esac
done
export PATH

# Resolve script directory to use as default destination
# We want the directory where the script *appears* to be (respecting symlinks)
SELF_PATH=$(command -v "$0" 2>/dev/null)
[ -z "$SELF_PATH" ] && SELF_PATH="./$0"
SCRIPT_DIR=$(cd "$(dirname "$SELF_PATH")" && pwd)

# --- Helper Functions ---

show_help() {
    cat << EOF
Usage: $(basename "$0") [options]

Creates a timestamped archive of the current directory.

Options:
  -h, --help    Show this help message and exit.
  -d dir        Destination directory for the backup (default: the directory
                where this script is located, or value of BACKUP_DIR).
  -t type       Archive type: tar, tar.gz, tar.bz2, tar.xz, tar.bz3, 7z, tar.7z (default: tar.gz).
  -l level      Compression level: 1-9 (default: 6).
  -p            Parallel: use multiple CPU cores if supported (xz, 7z, bzip3, pigz, pbzip2).
  -n            Dry run: print the command that would be executed and exit.
  -v            Verbose: show progress/files during archive creation.
  -S, --no-stats Disable statistics calculation (original vs archive size).

Environment:
  BACKUP_DIR    Default destination directory if -d is not specified.
EOF
}

# --- Argument Parsing ---

DEST_DIR="${BACKUP_DIR:-$SCRIPT_DIR}"
TYPE="tar.gz"
LEVEL=6
PARALLEL=0
DRY_RUN=0
VERBOSE=0
SHOW_STATS=1

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) show_help; exit 0 ;;
        -d) DEST_DIR="$2"; shift 2 ;;
        -t) TYPE="$2"; shift 2 ;;
        -l) LEVEL="$2"; shift 2 ;;
        -p) PARALLEL=1; shift ;;
        -n) DRY_RUN=1; shift ;;
        -v) VERBOSE=1; shift ;;
        -S|--no-stats) SHOW_STATS=0; shift ;;
        *) echo "Error: Unknown option '$1'"; show_help; exit 1 ;;
    esac
done

# Validate Type
case "$TYPE" in
    tar|tar.gz|tar.bz2|tar.xz|tar.bz3|7z|tar.7z) ;;
    *) echo "Error: Invalid type '$TYPE'. Supported types: tar, tar.gz, tar.bz2, tar.xz, tar.bz3, 7z, tar.7z." >&2; exit 1 ;;
esac

# Validate Level
case "$LEVEL" in
    [1-9]) ;;
    *) echo "Error: Invalid compression level '$LEVEL'. Must be 1-9." >&2; exit 1 ;;
esac

# --- Dependency Check ---

MISSING=""
check_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        MISSING="$MISSING $1"
    fi
}

check_tool realpath

case "$TYPE" in
    tar*) check_tool tar ;;
esac

# Tools for compression
ZIP_TOOL=""
case "$TYPE" in
    tar.gz)
        if [ "$PARALLEL" -eq 1 ] && command -v pigz >/dev/null 2>&1; then
            ZIP_TOOL="pigz"
        else
            ZIP_TOOL="gzip"
        fi
        ;;
    tar.bz2)
        if [ "$PARALLEL" -eq 1 ] && command -v pbzip2 >/dev/null 2>&1; then
            ZIP_TOOL="pbzip2"
        else
            ZIP_TOOL="bzip2"
        fi
        ;;
    tar.xz)
        ZIP_TOOL="xz"
        ;;
    tar.bz3)
        ZIP_TOOL="bzip3"
        ;;
    7z|tar.7z)
        ZIP_TOOL="7z"
        ;;
esac

[ -n "$ZIP_TOOL" ] && check_tool "$ZIP_TOOL"

if [ -n "$MISSING" ]; then
    echo "Error: Required tools not found:$MISSING" >&2
    exit 1
fi

# --- Execution ---

NOW=$(date +%Y%m%d_%H%M%S)
TARGET_PATH=$(realpath ".")
PARENT_DIR=$(dirname "$TARGET_PATH")
DIR_NAME=$(basename "$TARGET_PATH")

# Clean up directory name for the filename (remove leading dots)
SAFE_NAME=$(echo "$DIR_NAME" | sed 's/^[.]//')

# Resolve destination path
if [ "$DRY_RUN" -eq 0 ] && [ ! -d "$DEST_DIR" ]; then
    echo "Creating destination directory: $DEST_DIR"
    mkdir -p "$DEST_DIR" || exit 1
fi
ABS_DEST=$(cd "$DEST_DIR" 2>/dev/null && pwd || echo "$DEST_DIR")

# Determine extension and command
V_TAR=""
V_ZIP=""
[ "$VERBOSE" -eq 1 ] && V_TAR="v" && V_ZIP="-v"

# Parallel flags
P_XZ=""
P_7Z=""
[ "$PARALLEL" -eq 1 ] && P_XZ="-T0" && P_7Z="-mmt=on"

case "$TYPE" in
    tar)
        EXT="tar"
        CMD="tar c${V_TAR}f \"\$ARCHIVE_PATH\" \"\$DIR_NAME\""
        ;;
    tar.gz)
        EXT="tar.gz"
        CMD="tar c${V_TAR}f - \"\$DIR_NAME\" | $ZIP_TOOL -$LEVEL ${V_ZIP} > \"\$ARCHIVE_PATH\""
        ;;
    tar.bz2)
        EXT="tar.bz2"
        CMD="tar c${V_TAR}f - \"\$DIR_NAME\" | $ZIP_TOOL -$LEVEL ${V_ZIP} > \"\$ARCHIVE_PATH\""
        ;;
    tar.xz)
        EXT="tar.xz"
        CMD="tar c${V_TAR}f - \"\$DIR_NAME\" | xz -$LEVEL $P_XZ ${V_ZIP} > \"\$ARCHIVE_PATH\""
        ;;
    tar.bz3)
        EXT="tar.bz3"
        P_BZ3=""
        [ "$PARALLEL" -eq 1 ] && P_BZ3="-j 0"
        # bzip3 uses -b for block size (MiB) instead of -1..-9. 
        # Mapping: Level 1-9 -> 16, 32, 48, 64, 80, 96, 112, 128, 256 MiB
        BZ3_BLOCK=$((LEVEL * 16))
        [ "$LEVEL" -eq 9 ] && BZ3_BLOCK=256
        CMD="tar c${V_TAR}f - \"\$DIR_NAME\" | bzip3 -c -b $BZ3_BLOCK $P_BZ3 ${V_ZIP} > \"\$ARCHIVE_PATH\""
        ;;
    tar.7z)
        EXT="tar.7z"
        CMD="tar c${V_TAR}f - \"\$DIR_NAME\" | 7z a -si\"\$SAFE_NAME.tar\" -t7z -m0=lzma -mx=$LEVEL -mfb=64 -md=32m -ms=on $P_7Z \"\$ARCHIVE_PATH\""
        [ "$VERBOSE" -eq 0 ] && CMD="$CMD > /dev/null"
        ;;
    7z)
        EXT="7z"
        # 7z specific settings from original script. It is verbose by default.
        CMD="7z a -t7z -m0=lzma -mx=$LEVEL -mfb=64 -md=32m -ms=on $P_7Z \"\$ARCHIVE_PATH\" \"\$DIR_NAME\""
        # If not verbose, we could potentially pipe to /dev/null but 7z is useful to see.
        [ "$VERBOSE" -eq 0 ] && CMD="$CMD > /dev/null"
        ;;
esac

ARCHIVE_PATH="$ABS_DEST/${SAFE_NAME}_${NOW}.${EXT}"

if [ "$DRY_RUN" -eq 1 ]; then
    echo "Dry run: would create $TYPE backup of: $TARGET_PATH"
    # Expand the command for display by evaluating an echo of it
    EXPANDED_CMD=$(eval "echo \"$CMD\"")
    echo "Command: cd \"$PARENT_DIR\" && $EXPANDED_CMD"
    exit 0
fi

echo "Creating $TYPE backup of: $TARGET_PATH"
echo "Compression Level: $LEVEL"
[ "$PARALLEL" -eq 1 ] && echo "Mode: Parallel (Multi-core)"
echo "Destination: $ARCHIVE_PATH"

# Move to the parent directory so archive includes the folder name
cd "$PARENT_DIR" || exit 1

if [ "$VERBOSE" -eq 0 ]; then
    printf "Creating archive... "
fi

START_TIME=$(date +%s)

# Execute the constructed command
eval "$CMD"
RET=$?

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

if [ $RET -eq 0 ]; then
    if [ "$VERBOSE" -eq 0 ]; then
        echo "done."
    fi
    echo "Backup completed successfully."
    
    # --- Statistics ---
    if [ "$SHOW_STATS" -eq 1 ]; then
        # Use du -sk for calculation as it's fast and standard.
        SRC_SIZE_KB=$(du -sk "$TARGET_PATH" | awk '{print $1}')
        ARC_SIZE_KB=$(du -sk "$ARCHIVE_PATH" | awk '{print $1}')

        if [ "$SRC_SIZE_KB" -gt 0 ]; then
            # Calculate space saved percentage: (1 - compressed/original) * 100
            SAVED_PCT=$(awk "BEGIN { printf \"%.1f\", (1 - $ARC_SIZE_KB / $SRC_SIZE_KB) * 100 }")
        else
            SAVED_PCT="0.0"
        fi

        # Human readable sizes for display
        SRC_HUMAN=$(du -sh "$TARGET_PATH" | awk '{print $1}')
        ARC_HUMAN=$(du -sh "$ARCHIVE_PATH" | awk '{print $1}')

        # Human readable duration
        H=$((DURATION / 3600))
        M=$(((DURATION % 3600) / 60))
        S=$((DURATION % 60))
        
        if [ "$H" -gt 0 ]; then
            DUR_HUMAN="${H}h ${M}m ${S}s"
        elif [ "$M" -gt 0 ]; then
            DUR_HUMAN="${M}m ${S}s"
        else
            DUR_HUMAN="${S}s"
        fi

        echo ""
        echo "--- Backup Statistics ---"
        echo "Original Size:  $SRC_HUMAN"
        echo "Archive Size:   $ARC_HUMAN"
        echo "Space Saved:    $SAVED_PCT%"
        echo "Time Taken:     $DUR_HUMAN"
    fi
else
    echo "Error: Backup failed." >&2
    exit 1
fi
