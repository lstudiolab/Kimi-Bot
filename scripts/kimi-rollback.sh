#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077
readonly ROOT="$(cd -- "$(dirname -- "\${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly STATE_DIR="$ROOT/data/updates"
readonly STATE="$STATE_DIR/update-state"
readonly LOCK_DIR="$STATE_DIR/update.lock"
fail() { printf 'Kimi rollback: %s\n' "$*" >&2; exit 1; }
sha256() { sha256sum "$1" | awk '{print $1}'; }
read_value() { awk -F= -v key="$1" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$STATE"; }
for command_name in awk sha256sum install; do
  command -v "$command_name" >/dev/null 2>&1 || fail "Required command not found: $command_name"
done
[[ -f "$STATE" ]] || fail "No update state exists."
mkdir "$LOCK_DIR" 2>/dev/null || fail "An update or rollback is already running."
trap 'rmdir "$LOCK_DIR" >/dev/null 2>&1 || true' EXIT
BACKUP="$(read_value backup)"
BACKUP_SHA="$(read_value backup_sha256)"
BINARY="$(read_value binary)"
[[ -n "$BACKUP" && -n "$BACKUP_SHA" ]] || fail "Metadata has no rollback artifact."
[[ "$BACKUP" == "$STATE_DIR"/backups/* ]] || fail "Rollback artifact is outside managed backup directory."
[[ -f "$BACKUP" && -x "$BACKUP" ]] || fail "Previous executable is missing or not executable."
[[ "$(sha256 "$BACKUP")" == "$BACKUP_SHA" ]] || fail "Rollback artifact failed SHA-256 verification."
[[ "$BINARY" == "$ROOT"/.build/*/kimi ]] || fail "Executable path is outside this Kimi checkout."
[[ -d "$(dirname "$BINARY")" ]] || fail "Executable directory no longer exists."
CURRENT_SHA=""
[[ ! -f "$BINARY" ]] || CURRENT_SHA="$(sha256 "$BINARY")"
NEXT="$(dirname "$BINARY")/.kimi.rollback.$$"
install -m 700 "$BACKUP" "$NEXT" || fail "Could not stage previous executable."
mv -f -- "$NEXT" "$BINARY" || fail "Atomic rollback replacement failed."
RESTORED_SHA="$(sha256 "$BINARY")"
[[ "$RESTORED_SHA" == "$BACKUP_SHA" ]] || fail "Restored executable failed integrity verification."
STATE_TMP="$STATE_DIR/.update-state.rollback.$$"
{
  cat "$STATE"
  printf 'rolled_back_at=%s\nrolled_back_from_sha256=%s\nactive_sha256=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$CURRENT_SHA" "$RESTORED_SHA"
} >"$STATE_TMP" || fail "Executable restored, but rollback metadata could not be written."
mv -f -- "$STATE_TMP" "$STATE" || fail "Executable restored, but rollback metadata could not be committed."
printf 'Previous executable restored and verified.\nRestart Kimi when convenient to activate rollback.\n'
