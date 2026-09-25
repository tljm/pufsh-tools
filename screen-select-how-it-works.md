# screen-select.sh — How It Works

`screen-select.sh` is a POSIX shell script that lets you manually switch or auto-configure display outputs using `xrandr`. It is designed to run on OpenBSD with X11.

## Purpose

Provide a simple, one-shot way to change which displays are active and how they are arranged, without needing to manually type `xrandr` commands.

## Usage

```sh
screen-select.sh [--dry-run] [auto | auto-external | builtin-only | <display_name>]
```

| Argument             | Behaviour                                                  |
|----------------------|------------------------------------------------------------|
| `auto`               | Enable all connected displays; built-in becomes primary    |
| `auto-external`      | Enable the highest-res external display as primary; turn off built-in and other externals |
| `builtin-only`       | Enable the built-in display; turn off everything else      |
| `<display_name>`     | Enable one display by name; turn off all others            |
| `--dry-run`          | Print the resulting `xrandr` command without executing it   |
| `--dry-run auto`     | Same as `--dry-run` (defaults to `auto`)                   |
| `-h`, `--help`       | Show usage and list detected displays                      |

## Architecture

The script is structured in four phases:

### 1. Data Gathering (lines 37–66)

- **Dependency check**: Verifies `xrandr` and `awk` are available. Exits with an error if missing.
- **`ALL_OUTPUTS_INFO`**: Runs `xrandr` once and parses it with `awk` to extract every output's name, connection status (`connected` / `disconnected`), and whether it has an active resolution (`on` / `off`).
- **`CONNECTED_OUTPUTS`**: List of currently connected display names.
- **`DISCONNECTED_OUTPUTS`**: List of disconnected display names.
- **`BUILTIN_SCREEN`**: Detected by grepping for `eDP`, `LVDS`, or `DSI` prefixes — the first match is the internal laptop screen.

### 2. Configuration (lines 68–87)

- **`LOG_TS_FORMAT`**: Timestamp format (`+%Y-%m-%d %H:%M:%S`).
- **`PUFSH_SCREEN_LOG`**: Optional environment variable; if set, log messages are also appended to a file (`pufsh-<scriptname>.log`).
- **`DRY_RUN`**: Flag set to `1` when `--dry-run` is passed.

### 3. Argument Parsing (lines 186–209)

- `$1` becomes `MODE`.
- If `MODE` is `-h` or `--help`, `show_help` prints detected displays and exits 0.
- If `MODE` is `--dry-run`, `DRY_RUN=1` and `MODE` is set to `auto` (defaults to auto mode in dry-run).
- If `MODE` starts with `--dry-run` followed by a mode (e.g., `--dry-run auto-external`), the prefix is stripped and `DRY_RUN=1` is set.

### 4. Execution (lines 211–387)

#### Race-condition guard

Before any display work, the script kills any other running `screen-select.sh` or `screen-reinit.sh` processes (except the daemon). This uses a temp file to safely collect PIDs and avoids terminating unrelated processes.

#### Mode: `auto`

- Gets the **maximum available resolution** for the built-in screen via `get_max_geometry`.
- In a subshell (`set -- ...`):
  - Sets built-in screen as primary with `--fb` and `--auto`.
  - Adds `--output <name> --auto` for every connected display.
- If `DRY_RUN=1`, echoes the built `xrandr` command. Otherwise, executes it.
- Captures the exit code and logs an error if `xrandr` fails.

#### Mode: `auto-external`

- Iterates over connected outputs, skipping the built-in screen.
- For each external display, extracts its maximum available resolution.
- Picks the external display with the highest width (then highest height).
- Builds the `xrandr` command:
  - Selected external as primary with `--fb` and `--auto`.
  - Built-in screen → `--off`.
  - Other externals → `--auto`.
- Echoes or executes the command. Falls back to `xrandr --auto` if no external display is found.

#### Mode: `builtin-only`

- Gets the **maximum available resolution** for the built-in screen via `get_max_geometry`.
- Builds `xrandr`:
  - Built-in screen as primary with `--fb` and `--auto`.
  - Every other connected display → `--off`.
- Echoes or executes the command.

#### Mode: `<display_name>` (single display)

- Gets the **maximum available resolution** for that display via `get_max_geometry` (scans all modes, not just the current one).
- Builds `xrandr`:
  - Selected display as primary with `--fb` and `--auto`.
  - Every other connected display → `--off`.
- Echoes or executes the command.

#### Dry-run in error paths

In every error branch (no connected displays, no external displays, no built-in screen, no display specified), the script checks `DRY_RUN`. If set, it logs an info message instead of exiting with an error code. This ensures `--dry-run` always returns a non-error exit code.

### 5. Initialization (lines 389–424)

- Extends `PATH` with standard local directories (`/usr/local/bin`, `/usr/X11R6/bin`, `$HOME/bin`, `$HOME/.local/bin`).
- Resolves the script's own directory via `realpath` (handles symlinks).
- If `DRY_RUN=0`, runs `screen-reinit.sh` (if found) to refresh UI components (wallpaper, battery bar, screensaver, etc.). Only runs if at least one display has an active resolution. Skipped entirely in dry-run mode.

## Helper Functions

### `get_current_geometry <target>`

Parses `xrandr` output to find the **currently active** resolution for a given display. Scans lines matching `<resolution>` (e.g., `1920x1080+0+0`) under the target display section and returns `width height`. Falls back to `0 0` if not found. Used internally for fallback cases.

### `get_max_geometry <target>`

Similar to `get_current_geometry`, but scans **all** listed modes (not just the current active one) and returns the largest width and largest height combination available for that display. Used by all four modes (`auto`, `auto-external`, `builtin-only`, single display) to ensure the highest possible resolution is applied.

## Key Design Decisions

- **Subshell for xrandr**: Each mode builds the command in a subshell (`set -- ...`) before echoing or executing. This prevents variable pollution and correctly handles dynamic argument lists.
- **`--fb` flag**: All modes use the maximum available resolution for the built-in screen (via `get_max_geometry`). Externals use `--auto` to let xrandr pick the best mode.
- **Resolution preference**: `auto-external` prefers higher resolution, not higher position. Width is the primary sort key.
- **POSIX compliance**: No bashisms. Uses `command -v`, `[ ]`, `$(( ))`, `getopts`, and standard awk.
- **Symlink awareness**: `SCRIPT_DIR` uses `realpath` so hooks and other scripts are found even when the script is symlinked into `$PATH`.

## Exit Codes

| Scenario                              | Exit Code |
|---------------------------------------|-----------|
| Help requested                        | 0         |
| `--dry-run` (any mode)                | 0         |
| Successful display configuration      | 0         |
| `xrandr` fails                        | non-zero  |
| No connected displays (non-dry-run)   | 1         |
| No external displays (non-dry-run)    | 1         |
| Built-in screen not detected          | 1         |
| No display specified (non-dry-run)    | 1         |
