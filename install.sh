#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$REPO_ROOT/.opencode"
PROFILE_NAME="four-model"
DRY_RUN=0
FORCE=0

usage() {
  cat <<'EOF'
Usage:
  ./install.sh [--profile NAME] [--dry-run] global
  ./install.sh [--profile NAME] [--dry-run] project <directory>
  ./install.sh [--profile NAME] doctor
  ./install.sh [--profile NAME] [--dry-run] uninstall

Commands:
  global              Render commands + agents and symlink them into ~/.config/opencode
  project <directory> Render commands + agents and copy them into <directory>/.opencode
  doctor              Verify the symlinks, the profile, and the model IDs
  uninstall           Remove the global symlinks created by this script

Options:
  --profile NAME      Profile under profiles/ without .env (default: four-model)
  --dry-run           Print what would happen without changing anything
  --force             Accepted for compatibility; existing paths are always backed up
EOF
}

log() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

COMMAND=""
PROJECT_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE_NAME="${2:?--profile needs a value}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --force) FORCE=1; shift ;;
    global|doctor|uninstall) COMMAND="$1"; shift ;;
    project) COMMAND="project"; shift; PROJECT_DIR="${1:?project needs a directory}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[ -n "$COMMAND" ] || { usage; exit 1; }

PROFILE_FILE="$REPO_ROOT/profiles/$PROFILE_NAME.env"
[ -f "$PROFILE_FILE" ] || die "profile not found: $PROFILE_FILE"

# shellcheck disable=SC1090
set -a
. "$PROFILE_FILE"
set +a

MODEL_VARS=(
  MODEL_GRILL MODEL_SPEC MODEL_TICKETS MODEL_IMPLEMENT MODEL_IMPLEMENTER
  MODEL_REVIEW MODEL_REVIEW_STANDARDS MODEL_REVIEW_SPEC MODEL_EXPLORER
  MODEL_MERGER MODEL_SETUP MODEL_HANDOFF
)
for v in "${MODEL_VARS[@]}"; do
  [ -n "${!v:-}" ] || die "profile $PROFILE_NAME is missing $v"
done

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/opencode-workflow/$PROFILE_NAME"
WORK_DIR="$HOME/.opencode-work"

if sed --version >/dev/null 2>&1; then
  SED_INPLACE=(sed -i)
else
  SED_INPLACE=(sed -i '')
fi

backup_path() {
  local path="$1"
  [ -e "$path" ] || [ -L "$path" ] || return 0
  local backup="${path}.bak-$(date +%Y%m%d-%H%M%S)"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] would back up $path -> $backup"
  else
    mv "$path" "$backup"
    log "backed up $path -> $backup"
  fi
}

render() {
  local dest="$1"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] would render $SOURCE -> $dest (profile: $PROFILE_NAME)"
    return
  fi
  rm -rf "$dest"
  mkdir -p "$dest"
  cp -R "$SOURCE/agents" "$dest/agents"
  cp -R "$SOURCE/commands" "$dest/commands"
  cp "$SOURCE/opencode.json" "$dest/opencode.json"
  cp "$SOURCE/README.md" "$dest/README.md"

  local v value
  for v in "${MODEL_VARS[@]}"; do
    value="${!v}"
    find "$dest/agents" "$dest/commands" -name '*.md' -print0 |
      xargs -0 "${SED_INPLACE[@]}" "s|__${v}__|${value}|g"
  done

  if grep -R -n '__MODEL_' "$dest/agents" "$dest/commands" >/dev/null 2>&1; then
    die "unreplaced model placeholder remains in $dest"
  fi
}

install_global() {
  render "$DATA_DIR"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] would symlink $CONFIG_DIR/commands -> $DATA_DIR/commands"
    log "[dry-run] would symlink $CONFIG_DIR/agents -> $DATA_DIR/agents"
    log "[dry-run] would create $WORK_DIR"
    return
  fi
  mkdir -p "$CONFIG_DIR"
  for item in commands agents; do
    if [ -e "$CONFIG_DIR/$item" ] || [ -L "$CONFIG_DIR/$item" ]; then
      backup_path "$CONFIG_DIR/$item"
    fi
    ln -s "$DATA_DIR/$item" "$CONFIG_DIR/$item"
    log "linked $CONFIG_DIR/$item -> $DATA_DIR/$item"
  done
  mkdir -p "$WORK_DIR"
  log "installed profile '$PROFILE_NAME' globally"
  log "next: run /setup in each repo"
}

install_project() {
  local dir="$1"
  [ -d "$dir" ] || die "project directory not found: $dir"
  local dest="$dir/.opencode"
  render "$DATA_DIR"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] would copy commands + agents + opencode.json into $dest"
    return
  fi
  mkdir -p "$dest"
  for item in commands agents; do
    if [ -e "$dest/$item" ]; then
      backup_path "$dest/$item"
    fi
    cp -R "$DATA_DIR/$item" "$dest/$item"
  done
  if [ -e "$dest/opencode.json" ]; then
    backup_path "$dest/opencode.json"
  fi
  cp "$DATA_DIR/opencode.json" "$dest/opencode.json"
  log "installed profile '$PROFILE_NAME' into $dest"
  log "next: run /setup in $dir"
}

doctor() {
  log "repo:    $REPO_ROOT"
  log "profile: $PROFILE_NAME ($PROFILE_FILE)"
  log "config:  $CONFIG_DIR"
  log "data:    $DATA_DIR"
  echo

  for item in commands agents; do
    if [ -L "$CONFIG_DIR/$item" ]; then
      local target
      target="$(readlink -f "$CONFIG_DIR/$item")"
      if [ "$target" = "$(readlink -f "$DATA_DIR/$item" 2>/dev/null || true)" ]; then
        log "ok: $CONFIG_DIR/$item -> $target"
      else
        log "warn: $CONFIG_DIR/$item -> $target (not this profile)"
      fi
    elif [ -d "$CONFIG_DIR/$item" ]; then
      log "warn: $CONFIG_DIR/$item is a directory, not a symlink"
    else
      log "missing: $CONFIG_DIR/$item"
    fi
  done

  local available
  available="$(opencode models 2>/dev/null || true)"
  if [ -z "$available" ]; then
    log "warn: could not run 'opencode models'"
  else
    local v value base
    for v in "${MODEL_VARS[@]}"; do
      value="${!v}"
      base="${value%%#*}"
      if printf '%s\n' "$available" | grep -Fxq "$base"; then
        log "ok: $v -> $value"
      else
        log "MISSING: $v -> $value"
      fi
    done
  fi

  if [ -d "$WORK_DIR" ]; then
    log "ok: $WORK_DIR"
  else
    log "warn: $WORK_DIR missing (install creates it)"
  fi

  if [ -d "$PWD/docs/agents" ]; then
    log "ok: $PWD/docs/agents"
  else
    log "note: run /setup in this repo"
  fi
}

uninstall() {
  for item in commands agents; do
    if [ -L "$CONFIG_DIR/$item" ]; then
      local target
      target="$(readlink -f "$CONFIG_DIR/$item")"
      case "$target" in
        "$(readlink -f "$DATA_DIR")"/*)
          run rm "$CONFIG_DIR/$item"
          log "removed $CONFIG_DIR/$item"
          ;;
        *)
          log "skipped $CONFIG_DIR/$item (points elsewhere: $target)"
          ;;
      esac
    else
      log "skipped $CONFIG_DIR/$item (not a symlink)"
    fi
  done
}

case "$COMMAND" in
  global) install_global ;;
  project) install_project "$PROJECT_DIR" ;;
  doctor) doctor ;;
  uninstall) uninstall ;;
  *) die "unknown command: $COMMAND" ;;
esac
