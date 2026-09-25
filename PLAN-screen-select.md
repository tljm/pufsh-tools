# Implementation Plan — New `screen-select.sh`

Driven by `SPEC-screen-select.md`. The current `screen-select.sh` is broken and is
**not** a reference implementation. This document is the detailed plan for the next
version.

---

## 1. What this replaces

The current `screen-select.sh` is broken and must **not** be used as a template. Its
confirmed defects (from SPEC §14, all verified in the current file):

| # | Defect | Location | Fix |
|---|--------|----------|-----|
| 1 | `xrandr`/`awk` called at lines 50–66 **before** PATH is set at line 392 | data-gather before PATH | Move PATH setup to the very top |
| 2 | Non-POSIX `local` (lines 79, 82–85) and `mktemp` (line 217) | log + PID guard | Remove `local`; use temp-free POSIX patterns |
| 3 | Dead code `get_current_geometry` (lines 89–120) | — | Delete |
| 4 | Fragile `pgrep -f "screen-select.sh$|screen-reinit.sh$"` race guard | lines 218–224 | Two explicit `pgrep -x` checks (or drop entirely — see §12) |
| 5 | `--fb` treated as assumed | — | Keep as hard dependency, document it |

The new script is a clean-room POSIX-sh rewrite driven by SPEC-screen-select.md.

## 2. Scope (verbatim from spec)

**In**: built-in detection; `auto`; named-screen mode (`<display_name>` at max res,
primary, others off); `--dry-run`; `--help`; strict POSIX-sh; minimal deps.

**Out**: ghost cleanup, suspend, screensaver inhibition (daemon's job); wallpapers/
bars/console (screen-reinit.d's job); tiling; daemons/signals.

**Modes = exactly two** (`auto`, `<display_name>`) plus `--dry-run`/`--help`.
`auto-external` and `builtin-only` are **dropped** (§15).

## 3. CLI contract

```
screen-select.sh [--dry-run] [MODE]
MODE ∈ { auto | <display_name> }
```

| Input | Behaviour |
|-------|-----------|
| no args | print help, exit 0 |
| `--dry-run` | defaults to `auto`, print command, exit 0 |
| `--dry-run <MODE>` | dry-run for that mode |
| `auto` | all connected on at default; fb = built-in default |
| `<display_name>` | that screen on at **max** res, primary, others off; fb = that max |
| `-h`/`--help` | usage + detected displays, exit 0 |

`<display_name>` is a bare xrandr token (`eDP-1`, `HDMI-1`, `DP-2-1`); matched
**exactly**, no globbing/metacharacters. Invalid token (spaces, `*`, `?`, `;`, etc.)
→ error, exit 2.

**Exit codes**: `0` success/help; `1` runtime failure (tool missing, screen not
found/disconnected, xrandr failed); `2` usage error (bad/extra args).

## 4. Architecture — execution phases

1. **PATH** — extend the standard blocks **first** (before any tool use), including
   `/usr/sbin` so `sysctl` is discoverable for lid detection.
2. **Tool validation** — require `xrandr awk grep cut head date`. `sysctl` is
   conditional (lid only).
3. **Lid detection** — read-only, reused from the daemon (§9).
4. **Single `xrandr` parse** — run `xrandr` **once**, pipe through one awk script →
   `XRANDR_DATA` (one record per output: `name status activeW activeH maxW maxH`).
5. **Arg parsing** — loop over `$@`; handle help/dry-run/auto/name; validate token;
   default `--dry-run` → `auto`.
6. **Mode dispatch** — compute framebuffer + primary, build args, execute or print
   (dry-run).

## 5. Data model — the single `xrandr` parse (the hard part)

Run once and capture:

```sh
XRANDR_DATA=$(
    xrandr 2>/dev/null | awk '
        function flush() { if (have) print name, status, active, mw, mh }
        # Mode line: indented "WxH ..."
        /^[ ]+[0-9]+x[0-9]+/ {
            split($1, p, "x"); w=p[1]+0; h=p[2]+0
            if (w > mw || (w == mw && h > mh)) { mw=w; mh=h }
            next
        }
        # Output header: contains connected/disconnected
        /^[^ ]/ && ($2 == "connected" || $2 == "disconnected") {
            flush()
            name=$1; status=$2
            active=""
            for (i=3; i<=NF; i++)
                if ($i ~ /^[0-9]+x[0-9]+[*+]?$/) { active=$i; break }
            sub(/[*+]$/, "", active)
            mw=0; mh=0; have=1
            next
        }
        END { flush() }
    '
)
```

**Format robustness** (important): modern `xrandr` wraps headers as
`  Port 2: [eDP-1] connected primary 1920x1080+0+0 ...` while the spec's §6 shows the
classic `eDP-1 connected primary ...`. The parser above handles **both** by: skipping
the `Port N: ` prefix, stripping `[name]`, and taking the first `WxH[*+]?` token after
the status word as the active resolution. The classic format is the primary target;
the bracketed form is a transparent fallback.

**Record example** (from a realistic xrandr dump):
```
eDP-1   connected  1920x1080  2560 1440     # default 1920x1080, max 2560x1440
HDMI-1  connected  2560x1440  2560 1440     # default == max
DP-2-1  disconnected  (empty) 2560 1440     # no active mode; max still 2560x1440
```

**Lookup helpers** (scan the tiny `XRANDR_DATA`; no arrays needed in POSIX sh):
```sh
record_default() { printf '%s\n' "$XRANDR_DATA" | awk -v n="$1" '$1==n {print $3, $4; exit}'; }
record_max()     { printf '%s\n' "$XRANDR_DATA" | awk -v n="$1" '$1==n && $5>0 {print $5, $6; exit}'; }
record_exists()  { printf '%s\n' "$XRANDR_DATA" | awk -v n="$1" '$1==n {f=1; exit} END{exit !f}'; }
is_connected()   { printf '%s\n' "$XRANDR_DATA" | awk -v n="$1" '$1==n && $2=="connected" {c=1; exit} END{exit !c}'; }
```

**Built-in detection**: first record whose name matches `^(eDP|LVDS|DSI)`. Empty →
`BUILTIN_SCREEN=""`, auto framebuffer degrades gracefully (§8).

## 6. POSIX portability rules

- No `local`, no `mktemp`, no `[[`, no `+=`, no arrays, no `$() 2>/dev/null` shorthand.
- No bashisms; arithmetic via `$(( ))`; `[ ]` not `[[ ]]`.
- Temp files avoided entirely (no `mktemp`); use temp-free patterns.
- `command -v` only (never `which`).

**Logging** (no `local`):
```sh
log() {
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] $*" >&2
    if [ -n "$PUFSH_SCREEN_LOG" ]; then
        lf="$PUFSH_SCREEN_LOG/pufsh-${0##*/}.log"
        mkdir -p "$(dirname "$lf")" 2>/dev/null
        echo "[$ts] $*" >> "$lf" 2>/dev/null
    fi
}
```
> Note on §13: the spec writes the format inline as `[%Y-%m-%d %H:%M:%S]`, but the
> toolkit convention (`LOG_TS_FORMAT='+%Y-%m-%d %H:%M:%S'`, `echo "[$(date ...)] $*"`)
> produces the identical visual `[YYYY-MM-DD HH:MM:SS] msg` and matches the other
> `screen-*` scripts. Recommend the convention for consistency.

## 7. Framebuffer & primary rules (the decision table)

| Mode | Screens ON | Primary | `--fb` value | `--fb` attached to |
|------|-----------|---------|--------------|--------------------|
| `auto` (lid open) | all connected, `--auto` | built-in (if connected) else first connected | built-in **default** (fallback: largest connected default) | the primary |
| `auto` lid-closed | all connected **except** built-in | first connected **non-built-in** | largest **default** among screens on | the primary |
| `<name>` | only that screen, `--mode MAX` | that screen | that screen's **max** | that screen |
| zero-on (lid closed, only built-in connected) | none | none | **omit** `--fb` | n/a |

**`--fb` always attaches to the primary output** (the root), never to a screen that is
off.

## 8. Per-mode command construction

Build args in a subshell with `set --`; run `xrandr "$@"` (or print for dry-run).
Parent `$@` never touched.

**`auto`** (lid open, sample state above):
```
xrandr --output eDP-1 --primary --fb 1920x1080 --auto --output HDMI-1 --auto
```
(`DP-2-1` is disconnected → left untouched. Disconnected outputs are never turned off.)

**`auto --dry-run`**:
```
xrandr --output eDP-1 --primary --fb 1920x1080 --auto --output HDMI-1 --auto
```
Printed to **stdout**; logs to stderr (kept out of the way). No `screen-reinit`, no
side effects.

**`HDMI-1`** (named):
```
xrandr --output HDMI-1 --mode 2560x1440 --primary --fb 2560x1440 --output eDP-1 --off
```

**`auto` lid-closed** (built-in kept off):
```
xrandr --output HDMI-1 --primary --fb 2560x1440 --auto --output eDP-1 --off
```

**Zero-on** (lid closed, only built-in connected) — omit `--fb`, no `--primary`:
```
xrandr --output eDP-1 --off
```

**Command-builder helpers** (append to a growing `ARGS` string, word-split on
execution):
```sh
add()      { ARGS="$ARGS $1"; }
add_off()  { add "--output"; add "$1"; add "--off"; }
add_auto() { add "--output"; add "$1"; add "--auto"; }
add_pfb()  { add "--output"; add "$1"; add "--primary"; add "--fb"; add "$2"; }   # primary + fb
add_mode() { add "--output"; add "$1"; add "--mode"; add "$2"; add "--primary"; add "--fb"; add "$2"; }  # named
```

### Edge cases & fail-closed behaviour
- **Named screen not in xrandr** → `record_exists` fails → stderr error, exit 1.
- **Named screen disconnected** → `is_connected` fails → stderr error, exit 1
  (cannot turn on a disconnected screen; fail closed, don't produce a partial config).
- **Named screen has no modes** (`record_max` empty) → stderr error, exit 1.
- **`auto` with zero connected outputs** → stderr error, exit 1 (§11: "not a
  configuration this tool produces").
- **`auto` framebuffer unresolvable** (built-in disconnected / no default) → fall back
  to largest connected default; if still empty, omit `--fb`.
- **Turn off all *other connected* outputs** in named mode; never leave a mixed config.
- **xrandr fails at runtime** → capture `$?`, log, exit non-zero.

## 9. Lid detection (§9, reused from daemon)

```sh
LID_SENSOR=$(sysctl hw.sensors 2>/dev/null | grep -i lid | cut -d= -f1 | head -n 1)
LID_CLOSED=0
if [ -n "$LID_SENSOR" ] && [ "$(sysctl -n machdep.lidaction 2>/dev/null)" = "0" ]; then
    LID_STATE=$(sysctl -n "$LID_SENSOR" 2>/dev/null)
    case "$LID_STATE" in Off*) LID_CLOSED=1 ;; esac
fi
```
Read-only. If `hw.sensors` unavailable / sensor absent / `machdep.lidaction != 0` →
lid disabled, `auto` lid-closed case skipped.

## 10. Safety & error handling (§12)

- PATH extended **before** any tool use.
- Required tools validated up front.
- Named args rejected if non-token (`case "$MODE" in ''|*[!A-Za-z0-9_-]*)`).
- `xrandr` built in a subshell with `set --`.
- Single-screen mode turns off all other connected outputs.
- Non-zero exit + stderr on unresolved screen or xrandr failure.

## 11. Logging (§13)

- Timestamped to stderr: `[%Y-%m-%d %H:%M:%S]`.
- Mirrored to `$PUFSH_SCREEN_LOG/pufsh-screen-select.log` when set (same pattern as
  other scripts).
- Dry-run prints the command to **stdout**; logs stay on stderr.

## 12. Testing strategy (no test infra exists in the repo)

Since there are no automated tests, add a small, self-contained harness (a `tests/`
dir is acceptable and low-cost here):

1. **Fake `xrandr`**: a shell stub that emits a controlled xrandr dump from an env var
   (`XRANDR_STUB`), so modes/status/resolutions are deterministic.
2. **Fake `sysctl`**: stub returning `Off`/`On`/empty and `machdep.lidaction`.
3. **Assertions**: run the script, capture stdout/stderr/exit code, verify the exact
   `xrandr` line for each mode × state matrix:
   - `auto` (lid open) → correct args + fb.
   - `auto --dry-run` → printed line, exit 0, no side effects.
   - `--dry-run` alone → defaults to auto.
   - named mode → max res, primary, others off.
   - named mode: not-found / disconnected / no-modes → exit 1 + stderr.
   - invalid token → exit 2.
   - `auto` lid-closed → built-in off, others on, fb=largest-on, primary=first external.
   - zero-on → `--fb` omitted.
   - no built-in detected → graceful degradation.
   - no connected outputs → exit 1.
   - tool missing (run with PATH lacking `xrandr`) → exit 1.
4. **POSIX check**: `sh -n` syntax check + run under `/bin/sh` (dash if available) to
   catch bashisms.

Run matrix-driven tests; assert exact command strings. This gives the coverage the
current repo lacks.

## 13. Integration impact (must be addressed separately)

The daemon currently calls modes the new script **won't** support:
- `screen-daemon.sh:77` → `"$SELECT_SCRIPT" builtin-only`
- `screen-daemon.sh:269` → `"$SELECT_SCRIPT" auto-external`

These will break against the new two-mode interface. Recommended daemon updates:
- `builtin-only` → `"$SELECT_SCRIPT" "$BUILTIN_SCREEN"` (named mode reproduces
  "built-in on, others off" at max res — matches the old `builtin-only` semantics).
- `auto-external` → no direct equivalent (named mode uses **max** res, not default).
  The daemon would need new logic: e.g., select the largest external by name, or add a
  small internal helper in the daemon that turns on externals at default with the
  built-in off. Flag for the daemon's own revision (out of scope for this script, but
  required for the codebase to stay functional).

## 14. Documentation updates

- `README.md` currently doesn't document `screen-select.sh`; add a short usage section
  for the new CLI.
- `AGENTS.md` "Module Breakdown → screen-select.sh" describes the old modes
  (`auto-external`, `builtin-only`, `--fb` assumptions); update to the new two-mode
  interface and the "max resolution" rule.
- Remove/replace the now-inaccurate `screen-select-how-it-works.md` if it documents the
  old behaviour.

## 15. Decisions for confirmation (ambiguous spec points)

1. **`--fb` attachment target**: attach to the **primary** output (off screens never
   get `--fb`). Confirmed by §10/§11.
2. **Zero-on case (§10 vs §11 tension)**: §10 says omit `--fb` when no screen is on
   (implying a command runs); §11 says zero-on "is not a configuration this tool
   produces." Chosen the §10-literal behaviour: `xrandr --output <builtin> --off` (no
   `--fb`, no `--primary`). If you'd rather error out instead, that's a one-line change.
3. **`auto` lid-closed primary**: first connected **non-built-in** output (an off
   built-in can't be primary). If you want the built-in kept as primary-but-off, that's
   the separate behaviour §15 mentions.
4. **`auto` framebuffer fallback** when built-in default is unresolvable: largest
   connected default, else omit `--fb`.
5. **Max resolution tie-break**: widest, then tallest (§7). One-line change to
   "largest by area" or "largest by height" if preferred.
6. **No `screen-reinit` call** from the new script (out of scope per §2). The current
   script calls it; the new one won't. If UI refresh is desired, that's a separate
   concern.
7. **`--dry-run` arg order**: accepts both `--dry-run <MODE>` and `<MODE> --dry-run`
   (more forgiving than the spec's shown order); extra/unknown args still error.

---

**Suggested next step**: implement the script per this plan, then write the `tests/`
harness (§12) and run the matrix before touching the daemon (§13).
