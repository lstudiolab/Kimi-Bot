#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$ROOT/data/updates/update-state"
LOCK="$ROOT/data/updates/update.lock"
fail() { printf 'Kimi rollback: %s\n' "$*" >&2; exit 1; }
[[ -f "$STATE" ]] || fail "No update state was found."
mkdir "$LOCK" 2>/dev/null || fail "Another update or rollback is already running."
trap 'rmdir "$LOCK" >/dev/null 2>&1 || true' EXIT
BACKUP="$(sed -n 's/^backup=//p' "$STATE" | head -n 1)"
BINARY="$(sed -n 's/^binary=//p' "$STATE" | head -n 1)"
[[ -n "$BACKUP" && -x "$BACKUP" ]] || fail "Previous executable backup is missing."
[[ -n "$BINARY" && -d "$(dirname "$BINARY")" ]] || fail "Installed executable path is invalid."
NEXT="$(dirname "$BINARY")/kimi.rollback.$$"
install -m 700 "$BACKUP" "$NEXT"
mv -f "$NEXT" "$BINARY"
printf 'Previous executable restored. Restart Kimi to activate the rollback.\n'
