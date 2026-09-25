# kill/pkill Usage Across screen-* Scripts

## Summary

| Script | Line | Command | Purpose |
|---|---|---|---|
| `screen-select.sh` | 149 | `kill -9 "$pid" 2>/dev/null` | Kill other `screen-*` processes to prevent race conditions |
| `screen-reinit.d/10-xphoon` | 8 | `kill -9 "$XPHOON_PID" 2>/dev/null` | Kill xphoon wallpaper before restart |
| `screen-reinit.d/20-xbattbar` | 8 | `kill -9 "$BATTPID" 2>/dev/null` | Kill xbattbar battery indicator before restart |

## No `pkill` commands found

None of the `screen-*.sh` scripts use `pkill`. All process termination uses `kill -9` with an explicitly captured PID.

## Pattern Details

### screen-select.sh:141–152
```sh
SCREEN_PIDS_FILE=$(mktemp /tmp/screen_pids.XXXXXX)
pgrep -f "screen-select.sh$|screen-reinit.sh$" > "$SCREEN_PIDS_FILE" 2>/dev/null
DAEMON_PID=$(pgrep -f screen-daemon.sh)
while IFS= read -r pid; do
    if [ -n "$pid" ] && [ "$pid" != "$$" ] && [ "$pid" != "$DAEMON_PID" ]; then
        kill -9 "$pid" 2>/dev/null
    fi
done < "$SCREEN_PIDS_FILE"
rm -f "$SCREEN_PIDS_FILE"
```

Exits early via `exit 1` after cleanup (line 162).

### 10-xphoon:8
```sh
kill -9 "$XPHOON_PID" 2>/dev/null
```
Exits early via `exit 0` after cleanup (line 9).

### 20-xbattbar:8
```sh
kill -9 "$BATTPID" 2>/dev/null
```
Exits early via `exit 0` after cleanup (line 9).

## Notes

- All uses of `kill -9` suppress errors with `2>/dev/null`, since the PID may already be gone.
- No `pkill` or `killall` commands exist in the codebase.
- No `wait` commands used before `kill -9` (race condition accepted).
- No `SIGTERM`/`SIGUSR1`/`SIGUSR2` signals used for graceful shutdown — only `SIGKILL` (`-9`).
