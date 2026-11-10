#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$REPO_ROOT/.opencode"
PROFILE_NAME="four-model"
DRY_RUN=0

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
  doctor              Verify the symlinks, the profile, the model IDs, and the tracker CLI
  uninstall           Remove the global symlinks created by this script

Options:
  --profile NAME      Profile under profiles/ without .env (default: four-model)
  --dry-run           Print what would happen without changing anything
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
    global|doctor|uninstall) COMMAND="$1"; shift ;;
    project) COMMAND="project"; shift; PROJECT_DIR="${1:?project needs a directory}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[ -n "$COMMAND" ] || { usage; exit 1; }

# A profile name reaches a path that is rm -rf'd. Keep it boring.
[[ "$PROFILE_NAME" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid profile name: $PROFILE_NAME"

PROFILE_FILE="$REPO_ROOT/profiles/$PROFILE_NAME.env"
[ -f "$PROFILE_FILE" ] || die "profile not found: $PROFILE_FILE"

# shellcheck disable=SC1090
set -a
. "$PROFILE_FILE"
set +a

# Derive the placeholder list from the sources so it cannot drift from the profile.
MODEL_VARS=()
while IFS= read -r v; do
  MODEL_VARS+=("$v")
done < <(
  grep -rhoE '__MODEL_[A-Z_]+__' "$SOURCE/agents" "$SOURCE/commands" |
    sort -u |
    sed 's/^__//; s/__$//'
)
[ "${#MODEL_VARS[@]}" -gt 0 ] || die "no __MODEL_*__ placeholders found in $SOURCE"
for v in "${MODEL_VARS[@]}"; do
  [ -n "${!v:-}" ] || die "profile $PROFILE_NAME is missing $v"
done

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/opencode-workflow/$PROFILE_NAME"
WORK_DIR="$HOME/.opencode-work"
SKILL_RULE='{ "action": "skill", "resource": "*", "effect": "deny" }'

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

copy_tree_files() {
  local src="$1" dest="$2" f name
  mkdir -p "$dest"
  for f in "$src"/*.md; do
    [ -e "$f" ] || continue
    name="$(basename "$f")"
    if [ -e "$dest/$name" ]; then
      backup_path "$dest/$name"
    fi
    cp "$f" "$dest/$name"
  done
}

merge_project_config() {
  local dest="$1"
  if [ ! -e "$dest" ]; then
    cp "$SOURCE/opencode.json" "$dest"
    log "wrote $dest"
    return
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] would merge the skill-suppression rule into $dest"
    return
  fi
  cp "$dest" "${dest}.bak-$(date +%Y%m%d-%H%M%S)"
  if python3 - "$dest" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
if not isinstance(data, dict):
    raise SystemExit(2)

rule = {"action": "skill", "resource": "*", "effect": "deny"}
permissions = data.get("permissions")
if not isinstance(permissions, list):
    permissions = []
if rule not in permissions:
    permissions.append(rule)
data["permissions"] = permissions

with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
  then
    log "merged the skill-suppression rule into $dest"
  else
    log "warn: could not parse $dest as JSON; left it untouched."
    log "      Add this to its permissions array manually:"
    log "      $SKILL_RULE"
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
    if [ -L "$CONFIG_DIR/$item" ]; then
      local current
      current="$(readlink -f "$CONFIG_DIR/$item" 2>/dev/null || true)"
      if [ "$current" = "$(readlink -f "$DATA_DIR/$item" 2>/dev/null || true)" ]; then
        rm "$CONFIG_DIR/$item"
      else
        backup_path "$CONFIG_DIR/$item"
      fi
    elif [ -e "$CONFIG_DIR/$item" ]; then
      backup_path "$CONFIG_DIR/$item"
    fi
    ln -s "$DATA_DIR/$item" "$CONFIG_DIR/$item"
    log "linked $CONFIG_DIR/$item -> $DATA_DIR/$item"
  done
  mkdir -p "$WORK_DIR"

  if [ ! -e "$CONFIG_DIR/opencode.json" ] && [ ! -e "$CONFIG_DIR/opencode.jsonc" ]; then
    cat > "$CONFIG_DIR/opencode.json" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "permissions": [
    $SKILL_RULE
  ]
}
EOF
    log "wrote $CONFIG_DIR/opencode.json with skill suppression"
  else
    log "note: global installs cannot safely edit your opencode config."
    log "      To suppress auto-discovered skills, add this to its permissions array:"
    log "      $SKILL_RULE"
  fi

  log "installed profile '$PROFILE_NAME' globally"
  log "next: run /setup in each repo"
}

install_project() {
  local dir="$1"
  [ -d "$dir" ] || die "project directory not found: $dir"
  local dest="$dir/.opencode"
  render "$DATA_DIR"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] would copy commands + agents into $dest"
    log "[dry-run] would merge the skill-suppression rule into $dest/opencode.json"
    return
  fi
  copy_tree_files "$DATA_DIR/commands" "$dest/commands"
  copy_tree_files "$DATA_DIR/agents" "$dest/agents"
  merge_project_config "$dest/opencode.json"
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

  if command -v git >/dev/null 2>&1; then
    log "ok: git"
  else
    log "MISSING: git"
  fi

  local global_cfg found_rule=0
  for global_cfg in "$CONFIG_DIR/opencode.json" "$CONFIG_DIR/opencode.jsonc"; do
    [ -f "$global_cfg" ] || continue
    if grep -Eq '"action"[[:space:]]*:[[:space:]]*"skill"|"skill"[[:space:]]*:' "$global_cfg"; then
      log "ok: skill suppression rule found in $global_cfg"
      found_rule=1
    fi
  done
  if [ -f "$PWD/.opencode/opencode.json" ] &&
     grep -Eq '"action"[[:space:]]*:[[:space:]]*"skill"|"skill"[[:space:]]*:' "$PWD/.opencode/opencode.json"; then
    log "ok: skill suppression rule found in $PWD/.opencode/opencode.json"
    found_rule=1
  fi
  if [ "$found_rule" -eq 0 ]; then
    log "note: no skill suppression rule found in the global or project config; add this to a permissions array:"
    log "      $SKILL_RULE"
  fi

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
    if [ -f "$PWD/docs/agents/verification.md" ]; then
      log "ok: $PWD/docs/agents/verification.md"
    else
      log "note: no docs/agents/verification.md; re-run /setup or add it"
    fi
    if [ -f "$PWD/docs/agents/issue-tracker.md" ]; then
      if grep -qi 'GitHub' "$PWD/docs/agents/issue-tracker.md"; then
        if command -v gh >/dev/null 2>&1; then log "ok: gh"; else log "MISSING: gh (tracker says GitHub)"; fi
      fi
      if grep -qi 'GitLab' "$PWD/docs/agents/issue-tracker.md"; then
        if command -v glab >/dev/null 2>&1; then log "ok: glab"; else log "MISSING: glab (tracker says GitLab)"; fi
      fi
    fi
  else
    log "note: run /setup in this repo"
  fi
}

uninstall() {
  local data_resolved=""
  data_resolved="$(readlink -f "$DATA_DIR" 2>/dev/null || true)"

  for item in commands agents; do
    if [ -L "$CONFIG_DIR/$item" ]; then
      local target
      target="$(readlink -f "$CONFIG_DIR/$item" 2>/dev/null || true)"
      if [ -z "$target" ]; then
        log "skipped $CONFIG_DIR/$item (broken symlink)"
        continue
      fi
      if [ -z "$data_resolved" ]; then
        log "skipped $CONFIG_DIR/$item (data dir not found: $DATA_DIR)"
        continue
      fi
      case "$target" in
        "$data_resolved"/*)
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

  log "note: $DATA_DIR and $WORK_DIR are left in place; remove them manually for a clean slate."
}

case "$COMMAND" in
  global) install_global ;;
  project) install_project "$PROJECT_DIR" ;;
  doctor) doctor ;;
  uninstall) uninstall ;;
  *) die "unknown command: $COMMAND" ;;
esac
