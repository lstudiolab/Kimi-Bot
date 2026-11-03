#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPOSITORY="$(printenv KIMI_REPOSITORY || printf 'lstudiolab/Kimi-Bot')"
CHANNEL="$1"
API="https://api.github.com/repos/$REPOSITORY"
LOCK_DIR="$ROOT/data/updates/update.lock"
STATE_DIR="$ROOT/data/updates"
TMP_ROOT="$(printenv TMPDIR || printf '/tmp')"
fail() { printf 'Kimi updater: %s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'USAGE'
Usage:
  ./scripts/kimi-update.sh check
  ./scripts/kimi-update.sh stable
  ./scripts/kimi-update.sh beta

check   Check the latest stable release and beta commit.
stable  Stage and install the latest published stable release.
beta    Stage and install the latest main-branch build.

The updater tests and builds in a detached worktree, then atomically
replaces only the executable. The current running process is not stopped.
USAGE
}
[[ -n "$CHANNEL" ]] || { usage; exit 2; }
for tool in git swift curl jq install; do command -v "$tool" >/dev/null || fail "$tool is required."; done
git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "Run this inside a Kimi Git checkout."
git -C "$ROOT" remote get-url origin >/dev/null 2>&1 || fail "The origin Git remote is not configured."
git -C "$ROOT" status --porcelain | grep -q . && fail "The working tree has uncommitted changes. Commit or safely stash them first."
release_json="$(curl --fail --silent --show-error --location --retry 3 --retry-delay 2 \
  -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' \
  "$API/releases/latest")" || fail "Could not retrieve the latest stable release. Publish a stable release first."
stable_tag="$(jq -er '.tag_name | select(type == "string" and length > 0)' <<<"$release_json")" \
  || fail "The stable release response has no valid tag."
git -C "$ROOT" fetch --quiet --tags origin "$stable_tag" || fail "Could not fetch stable tag $stable_tag."
git -C "$ROOT" fetch --quiet origin main || fail "Could not fetch beta branch main."
beta_sha="$(git -C "$ROOT" rev-parse FETCH_HEAD^{commit})" || fail "Could not resolve beta commit."
stable_sha="$(git -C "$ROOT" rev-parse "$stable_tag^{commit}")" || fail "Stable tag does not resolve to a commit."
current_sha="$(git -C "$ROOT" rev-parse HEAD)"
printf 'Current checkout: %s\nStable release:  %s (%s)\nBeta main:       %s\n' "$current_sha" "$stable_tag" "$stable_sha" "$beta_sha"
if [[ "$CHANNEL" == "check" ]]; then
  [[ "$current_sha" == "$stable_sha" ]] && printf 'Stable source matches current checkout.\n' || printf 'A stable release is available; nothing was installed.\n'
  [[ "$current_sha" == "$beta_sha" ]] && printf 'Current checkout matches beta main.\n' || printf 'A beta build is available; nothing was installed.\n'
  exit 0
fi
case "$CHANNEL" in
  stable) TARGET_SHA="$stable_sha"; TARGET_LABEL="$stable_tag" ;;
  beta) TARGET_SHA="$beta_sha"; TARGET_LABEL="beta-$(printf %.12s "$beta_sha")" ;;
  *) usage; fail "Unknown update channel: $CHANNEL" ;;
esac
[[ "$TARGET_SHA" != "$current_sha" ]] || { printf 'Kimi is already at %s.\n' "$TARGET_LABEL"; exit 0; }
mkdir -p "$STATE_DIR"
mkdir "$LOCK_DIR" 2>/dev/null || fail "Another update or rollback is already running."
TMP_DIR="$(mktemp -d "$TMP_ROOT/kimi-update.XXXXXX")"
WORKTREE="$TMP_DIR/source"
cleanup() {
  git -C "$ROOT" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
  rmdir "$LOCK_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM
printf '\nPreparing %s (%s).\nThe running Kimi process will not be stopped.\n' "$CHANNEL" "$TARGET_LABEL"
printf 'Install this update? [y/N] '
read -r answer
case "$answer" in y|Y|yes|YES) ;; *) printf 'Update cancelled. No files changed.\n'; exit 0 ;; esac
git -C "$ROOT" worktree add --quiet --detach "$WORKTREE" "$TARGET_SHA" || fail "Could not create isolated source worktree."
printf '\nRunning tests in isolated worktree...\n'
swift test --package-path "$WORKTREE" || fail "Tests failed. Installed executable was not changed."
printf '\nBuilding release executable...\n'
swift build -c release --package-path "$WORKTREE" || fail "Release build failed. Installed executable was not changed."
STAGED_DIR="$(swift build -c release --show-bin-path --package-path "$WORKTREE" 2>/dev/null | tail -n 1)"
STAGED_BIN="$STAGED_DIR/kimi"
[[ -x "$STAGED_BIN" ]] || fail "No executable was produced."
DEST_DIR="$(swift build -c release --show-bin-path --package-path "$ROOT" 2>/dev/null | tail -n 1)"
[[ -n "$DEST_DIR" ]] || fail "Could not resolve current executable directory."
DEST_BIN="$DEST_DIR/kimi"
mkdir -p "$DEST_DIR" "$STATE_DIR/backups"
BACKUP=""
if [[ -x "$DEST_BIN" ]]; then
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  BACKUP="$STATE_DIR/backups/kimi-$stamp"
  install -m 700 "$DEST_BIN" "$BACKUP"
fi
STAGED_INSTALL="$DEST_DIR/kimi.next.$$"
install -m 700 "$STAGED_BIN" "$STAGED_INSTALL"
mv -f "$STAGED_INSTALL" "$DEST_BIN"
{
  printf 'channel=%s\n' "$CHANNEL"
  printf 'label=%s\n' "$TARGET_LABEL"
  printf 'commit=%s\n' "$TARGET_SHA"
  printf 'installed_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'binary=%s\n' "$DEST_BIN"
  printf 'backup=%s\n' "$BACKUP"
} > "$STATE_DIR/update-state.tmp"
mv -f "$STATE_DIR/update-state.tmp" "$STATE_DIR/update-state"
printf '\nUpdate staged: %s\n' "$TARGET_LABEL"
[[ -z "$BACKUP" ]] || printf 'Previous executable backup: %s\n' "$BACKUP"
printf 'The running process is still using its previous in-memory executable.\n'
printf 'Restart Kimi when convenient. If the new version fails, run ./scripts/kimi-rollback.sh\n'
