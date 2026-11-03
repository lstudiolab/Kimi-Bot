#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077
readonly ROOT="$(cd -- "$(dirname -- "\${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly STATE_DIR="$ROOT/data/updates"
readonly BACKUP_DIR="$STATE_DIR/backups"
readonly LOCK_DIR="$STATE_DIR/update.lock"
readonly REPOSITORY="\${KIMI_REPOSITORY:-lstudiolab/Kimi-Bot}"
readonly API="https://api.github.com/repos/$REPOSITORY"
readonly TMP_BASE="\${TMPDIR:-\${PREFIX:-/tmp}/tmp}"
WORKTREE=""
TMP_DIR=""
NEXT_BIN=""
STATE_TMP=""
LOCKED=0
fail() { printf 'Kimi updater: %s\n' "$*" >&2; exit 1; }
info() { printf '\n[Kimi] %s\n' "$*"; }
need() { command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"; }
sha256() { sha256sum "$1" | awk '{print $1}'; }
usage() {
  cat <<'USAGE'
Kimi updater
  bash scripts/kimi-update.sh check
  bash scripts/kimi-update.sh stable
  bash scripts/kimi-update.sh beta
check   Inspect stable and beta revisions; never changes the binary.
stable  Install the latest published GitHub release.
beta    Install the latest commit on main.
Builds and tests in an isolated worktree. Replaces only the local executable.
Does not stop or restart the running Kimi process.
USAGE
}
cleanup() {
  local status=$?
  if [[ -n "$WORKTREE" && -d "$WORKTREE" ]]; then
    git -C "$ROOT" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
  fi
  [[ -z "$NEXT_BIN" ]] || rm -f -- "$NEXT_BIN"
  [[ -z "$STATE_TMP" ]] || rm -f -- "$STATE_TMP"
  [[ -z "$TMP_DIR" ]] || rm -rf -- "$TMP_DIR"
  if (( LOCKED )); then rmdir "$LOCK_DIR" >/dev/null 2>&1 || true; fi
  exit "$status"
}
[[ $# -eq 1 ]] || { usage; exit 2; }
CHANNEL="$1"
case "$CHANNEL" in check|stable|beta) ;; *) usage; fail "Unknown channel: $CHANNEL";; esac
for command_name in git swift curl jq awk sha256sum install; do need "$command_name"; done
git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "Run inside the Kimi Git checkout."
git -C "$ROOT" remote get-url origin >/dev/null 2>&1 || fail "Git remote 'origin' is not configured."
[[ -f "$ROOT/Package.swift" ]] || fail "Package.swift is missing."
[[ "$REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail "KIMI_REPOSITORY must be owner/repository."
if [[ "$CHANNEL" != "check" ]]; then
  mkdir -p "$STATE_DIR"
  mkdir "$LOCK_DIR" 2>/dev/null || fail "An update or rollback is already running."
  LOCKED=1
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
fi
release_response="$(curl --silent --show-error --location --retry 2 --retry-all-errors \
  --connect-timeout 10 --max-time 45 \
  --write-out $'\n%{http_code}' \
  -H 'Accept: application/vnd.github+json' \
  -H 'X-GitHub-Api-Version: 2022-11-28' "$API/releases/latest")" \
  || fail "GitHub release lookup failed. Check the network and try again."
release_status="\${release_response##*$'\n'}"
release_json="\${release_response%$'\n'*}"
stable_tag=""
stable_sha=""
if [[ "$release_status" == "200" ]]; then
  stable_tag="$(jq -er '.tag_name | select(type == "string" and length > 0)' <<<"$release_json")" \
    || fail "GitHub returned release data without a valid tag."
  git -C "$ROOT" fetch --quiet --no-tags origin "refs/tags/$stable_tag" \
    || fail "Could not fetch stable tag '$stable_tag'."
  stable_sha="$(git -C "$ROOT" rev-parse 'FETCH_HEAD^{commit}')" \
    || fail "Stable tag '$stable_tag' does not resolve to a commit."
elif [[ "$release_status" != "404" ]]; then
  fail "GitHub release lookup returned HTTP $release_status."
fi
git -C "$ROOT" fetch --quiet --no-tags origin refs/heads/main || fail "Could not fetch origin/main."
beta_sha="$(git -C "$ROOT" rev-parse 'FETCH_HEAD^{commit}')" || fail "Could not resolve latest beta commit."
current_sha="$(git -C "$ROOT" rev-parse HEAD)"
printf 'Installed checkout  %s\n' "$current_sha"
if [[ -n "$stable_sha" ]]; then printf 'Latest stable       %s  %s\n' "$stable_tag" "$stable_sha"; else printf 'Latest stable       no release published\n'; fi
printf 'Latest beta         %s\n' "$beta_sha"
if [[ "$CHANNEL" == "check" ]]; then
  if [[ -n "$stable_sha" ]]; then
    [[ "$current_sha" == "$stable_sha" ]] && printf 'Stable status       current\n' || printf 'Stable status       update available\n'
  fi
  [[ "$current_sha" == "$beta_sha" ]] && printf 'Beta status         current\n' || printf 'Beta status         update available\n'
  exit 0
fi
case "$CHANNEL" in
  stable)
    [[ -n "$stable_sha" ]] || fail "No stable release has been published yet."
    TARGET_SHA="$stable_sha"; TARGET_LABEL="$stable_tag" ;;
  beta)
    TARGET_SHA="$beta_sha"; TARGET_LABEL="beta-\${beta_sha:0:12}" ;;
esac
[[ "$TARGET_SHA" != "$current_sha" ]] || { info "Already at $TARGET_LABEL. No build needed."; exit 0; }
mkdir -p "$BACKUP_DIR" "$TMP_BASE"
TMP_DIR="$(mktemp -d "$TMP_BASE/kimi-update.XXXXXXXX")" || fail "Could not create temporary build directory."
WORKTREE="$TMP_DIR/source"
BUILD_LOG="$TMP_DIR/build.log"
info "Preparing $CHANNEL revision $TARGET_LABEL"
printf 'The running Kimi process will not be stopped.\nContinue? [y/N] '
IFS= read -r answer || answer=""
case "$answer" in y|Y|yes|YES) ;; *) info "Cancelled. No files changed."; exit 0;; esac
git -C "$ROOT" worktree add --quiet --detach "$WORKTREE" "$TARGET_SHA" || fail "Could not create isolated worktree."
info "Running optimized release tests"
if ! swift test -c release --package-path "$WORKTREE" >"$BUILD_LOG" 2>&1; then
  cat "$BUILD_LOG" >&2
  fail "Release tests failed. Installed executable was not touched."
fi
info "Building release executable"
if ! swift build -c release --package-path "$WORKTREE" >>"$BUILD_LOG" 2>&1; then
  cat "$BUILD_LOG" >&2
  fail "Release build failed. Installed executable was not touched."
fi
STAGED_DIR="$(swift build -c release --show-bin-path --package-path "$WORKTREE" 2>/dev/null | tail -n 1)"
STAGED_BIN="$STAGED_DIR/kimi"
[[ -n "$STAGED_DIR" && -x "$STAGED_BIN" ]] || fail "Build did not produce Kimi executable."
DEST_DIR="$(swift build -c release --show-bin-path --package-path "$ROOT" 2>/dev/null | tail -n 1)"
[[ -n "$DEST_DIR" ]] || fail "Could not resolve installed executable directory."
DEST_BIN="$DEST_DIR/kimi"
mkdir -p "$DEST_DIR"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP=""
BACKUP_SHA=""
if [[ -x "$DEST_BIN" ]]; then
  BACKUP="$BACKUP_DIR/kimi-$stamp-\${current_sha:0:12}-$$"
  install -m 700 "$DEST_BIN" "$BACKUP" || fail "Could not create rollback copy."
  BACKUP_SHA="$(sha256 "$BACKUP")"
fi
STAGED_SHA="$(sha256 "$STAGED_BIN")"
NEXT_BIN="$DEST_DIR/.kimi.next.$$"
STATE_TMP="$STATE_DIR/.update-state.$$"
install -m 700 "$STAGED_BIN" "$NEXT_BIN" || fail "Could not stage new executable."
{
  printf 'channel=%s\nlabel=%s\ncommit=%s\ninstalled_at=%s\nbinary=%s\ninstalled_sha256=%s\nbackup=%s\nbackup_sha256=%s\n' \
    "$CHANNEL" "$TARGET_LABEL" "$TARGET_SHA" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$DEST_BIN" "$STAGED_SHA" "$BACKUP" "$BACKUP_SHA"
} >"$STATE_TMP" || fail "Could not prepare update metadata."
mv -f -- "$NEXT_BIN" "$DEST_BIN" || fail "Atomic executable replacement failed."
if [[ "$(sha256 "$DEST_BIN")" != "$STAGED_SHA" ]]; then
  if [[ -n "$BACKUP" && -x "$BACKUP" ]]; then
    install -m 700 "$BACKUP" "$DEST_DIR/.kimi.recovery.$$"
    mv -f -- "$DEST_DIR/.kimi.recovery.$$" "$DEST_BIN"
  fi
  fail "Post-install integrity check failed. Previous executable was restored."
fi
mv -f -- "$STATE_TMP" "$STATE_DIR/update-state" || fail "Installed, but update metadata could not be committed. Backup: $BACKUP"
info "Installed $TARGET_LABEL successfully"
[[ -z "$BACKUP" ]] || printf 'Rollback copy        %s\n' "$BACKUP"
printf 'Executable SHA-256   %s\nRestart Kimi when convenient to activate.\n' "$STAGED_SHA"
printf 'Rollback: bash scripts/kimi-rollback.sh\n'
