# Specification: `screen-select.sh` (next version)

A POSIX-sh display manager for OpenBSD with X11. It selects which outputs are
active, at what resolution, which is primary, and sets the X11 framebuffer size.

Status: *spec only*. The current `screen-select.sh` is known to be broken and is
**not** a reference implementation. This document is the source of truth for the
next version.

---

## 1. Purpose

One-shot, non-interactive command to configure the display. Typical callers:
window managers, the `screen-daemon.sh` hotplug handler, or a user keybinding.

## 2. Scope

### In scope
- Detect the built-in (internal laptop) screen.
- `auto` mode (all connected screens on at default resolution; framebuffer =
  built-in resolution; lid-closed special case).
- Named-screen mode (`<display_name>`: that screen on at its max resolution,
  everything else off, it becomes primary, framebuffer = that max resolution).
- Named-screen mode covers "only this display"; to turn the built-in off, select
  another output by name.
- `--dry-run` (print the `xrandr` command, do not execute).
- Strict POSIX-sh portability; minimal external dependencies.

### Out of scope
- Ghost-screen cleanup, suspend mode, screensaver inhibition — that is
  `screen-daemon.sh`'s job.
- Wallpapers, battery bars, console repositioning — that is `screen-reinit.d`.
- Multi-monitor tiling — that is `tiling.sh`.
- Long-running daemons or signal handling.

## 3. Target environment

- **OS**: OpenBSD.
- **Shell**: `/bin/sh` (POSIX). No bashisms.
- **X server**: X11 via `xrandr`. The `--fb WxH` option is required and assumed
  to be supported by the installed `xrandr`.
- **Tools assumed present**: `xrandr`, `awk`, `sed`, `grep`, `cut`, `head`,
  `tail`, `date`, `printf`, `basename`, `dirname`. `sysctl` is required for lid
  detection. `command -v` is used for discovery (never `which`).

## 4. Design principles

- **KISS** — each mode is a small, linear set of `xrandr` arguments. No
  configuration tables, no plugins, no heuristics beyond what is stated below.
  Prefer the simplest rule that satisfies the requirement.
- **POSIX-first** — write to POSIX sh; only use a non-POSIX utility if it is
  guaranteed on OpenBSD and nothing simpler works.
- **One `xrandr` call per invocation** — gather data first, then build and run a
  single command in a subshell (`set --`), so the parent shell state is untouched.
- **Fail closed** — if a required display cannot be resolved, print an error to
  stderr and exit non-zero. Do not silently produce a partial configuration.

## 5. Command-line interface

```
screen-select.sh [--dry-run] [MODE]
```

`MODE` is one of: `auto` or a `<display_name>`.

| Argument        | Meaning                                                        |
|-----------------|----------------------------------------------------------------|
| `auto`          | All connected screens on at default resolution.                |
| `<display_name>`| That screen on at max resolution; all others off; it is primary.|
| `--dry-run`     | Print the resulting `xrandr` command; execute nothing.         |
| `-h`, `--help`  | Print usage and the list of detected displays.                 |

If no `MODE` is given, print help and exit 0. `--dry-run` alone defaults to
`auto`. `--dry-run` may be combined with a mode: `--dry-run <MODE>`.

`<display_name>` is a bare xrandr output token (e.g. `eDP-1`, `HDMI-1`). It is
matched exactly against detected output names; no shell globbing or wildcards.

## 6. Display and built-in detection

Run `xrandr` **once** and parse it. From the header line of each output
(`eDP-1 connected primary 1920x1080+0+0 ...`):

- **name** — first field.
- **status** — `connected` or `disconnected` (second field).
- **default (active) resolution** — the mode marked `*+` (the currently applied
  mode). `xrandr --auto` restores this automatically, so "default resolution" is
  obtained by simply using `--auto`.

**Built-in screen** — the internal laptop display. Detect it as the first output
whose name begins with `eDP`, `LVDS`, or `DSI`. If none matches, `BUILTIN_SCREEN`
is empty and modes that depend on it (`auto` framebuffer) degrade gracefully
(see §8).

Detection is best-effort and read-only; it never changes the display.

## 7. Resolution selection

- **Default resolution** (used by `auto`): the
  currently-applied mode, i.e. what `--auto` would select. Never the maximum.
- **Max resolution** (used by named-screen mode): the supported mode with the
  greatest **width**; ties broken by greatest **height**. This is the largest
  resolution the driver advertises for that output; it may differ from the
  default. The same value is used for both the mode and the framebuffer.

## 8. Behaviour per mode

### `auto`
Turn on every `connected` output at its default resolution (`--auto`).
Set the framebuffer to the built-in screen's default resolution.

- **Lid-closed special case**: if the lid is closed (see §9), do **not** turn on
  the built-in screen — it stays off — but turn on all other connected screens
  at default resolution. The framebuffer then falls back to the largest default
  resolution among the screens that are actually on.
- Primary: always designate a primary (see §11). When the built-in is on it is
  primary; when the built-in is off the first connected output becomes primary.

### `<display_name>` (named screen)
Turn on only that output, at its **max** resolution, make it primary, and turn
off every other `connected` output. Set the framebuffer to that same max
resolution.

### `--dry-run`
Print exactly the `xrandr` command that would run (one line, space-separated),
then exit 0. No `screen-reinit` call, no side effects.

## 9. Lid detection

Reuse the daemon's approach, which is already proven in this codebase:

1. `LID_SENSOR=$(sysctl hw.sensors 2>/dev/null | grep -i lid | cut -d= -f1 | head -n 1)`
2. Only treat the lid as authoritative when `sysctl machdep.lidaction` equals
   `0` (lid does not trigger hardware sleep); otherwise software state is
   unreliable.
3. Lid state is `Off` (closed) or `On` (open), read via `sysctl -n "$LID_SENSOR"`.

If `hw.sensors` is unavailable or the lid sensor is absent, lid detection is
disabled and the `auto` lid-closed special case is skipped (built-in behaves
normally). Detection is read-only.

## 10. Framebuffer

- Always set `--fb WxH` on the `xrandr` command, where `WxH` is the resolution
  defined by the active mode (built-in default for `auto`; the chosen screen's
  max for named mode; largest-on when the built-in is off).
- The single exception is when **no** screen is on (e.g. lid closed and every
  other output disconnected): then omit `--fb` and let X keep its current
  framebuffer, since there is no active output to size it to.
- The framebuffer command must be part of the **same** `xrandr` invocation as
  the output changes.

## 11. Primary

- **Always** force `--primary` on the selected screen whenever at least one
  screen is on. This makes the layout deterministic and gives the window manager
  a definite primary/root screen.
- `auto` with lid closed: the first connected output becomes primary.
- The only case with no forced primary is when zero screens are on, which is not
  a configuration this tool produces.

## 12. Safety and error handling

- Extend PATH **before** gathering data or running `xrandr`.
- Validate that required tools exist before doing any work.
- Reject empty or non-token arguments (no spaces, wildcards, or shell
  metacharacters) as a named screen.
- Build the `xrandr` command inside a subshell with `set --`; never modify the
  parent shell's positional parameters.
- Turn off all *other* connected outputs when a single screen is selected; never
  leave an ambiguous mixed configuration.
- Exit non-zero with a stderr message if the required screen cannot be resolved
  or `xrandr` fails.

## 13. Logging

- Timestamped messages to stderr, format `[%Y-%m-%d %H:%M:%S]`.
- Optionally mirror to a file when `PUFSH_SCREEN_LOG` is set (same pattern as the
  other `screen-*` scripts): `pufsh-<scriptname>.log` under that directory.
- Keep logging out of the way of the printed `xrandr` command in `--dry-run`.

## 14. Known issues in the current script (must NOT be carried forward)

1. PATH is configured *after* `xrandr`/`awk` are first called — tools may be
   missing. **Fix**: set PATH first.
2. `local` and `mktemp` are non-POSIX. **Fix**: avoid `local`; replace `mktemp`
   with a POSIX-safe temp path (e.g. `/tmp/screen-select.$$`).
3. `get_current_geometry` is dead code. **Fix**: remove it.
4. The race-condition PID guard uses a fragile `pgrep -f "a$|b$"` pattern.
   **Fix**: simplify to two explicit checks.
5. `--fb` is assumed to work (recent commit confirms it does on this host); treat
   it as a hard dependency and document it.

## 15. Assumptions / decisions for confirmation

- **`auto-external` and `builtin-only` are intentionally dropped.** To turn the
  built-in off, select another output by name; to show only the built-in, use
  its name. This keeps the tool to two modes plus `--dry-run`/`--help`.
- **"Maximal resolution" = widest, then tallest.** If you prefer "largest by
  area" or "largest by height", this is a one-line change in §7.
- **`auto` framebuffer = built-in *default* resolution** (not max), so the
  framebuffer matches the actually-applied mode. Confirmed by the requirement
  wording ("turned on with default resolution" + "framebuffer is set to the
  resolution of the builtin screen").
- **Lid-closed `auto`**: built-in off, others on at default, framebuffer =
  largest-on. If you instead want the built-in *disabled but kept as primary*,
  that is a separate behaviour to add.
