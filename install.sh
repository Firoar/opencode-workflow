#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$REPO_ROOT/template"
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
  doctor              Verify symlinks, profile, model IDs, tracker CLI, and skill policy
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

# Small JSONC reader/merger for the targeted skill policy. Kept embedded so the
# installer stays self-contained.
config_py() {
  python3 - "$@" <<'PY'
import fnmatch
import json
import re
import sys


def strip_jsonc(text):
    out = []
    i = 0
    n = len(text)
    in_string = False
    escaped = False
    while i < n:
        ch = text[i]
        if in_string:
            out.append(ch)
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            i += 1
            continue
        if ch == '"':
            in_string = True
            out.append(ch)
            i += 1
            continue
        if ch == "/" and i + 1 < n and text[i + 1] == "/":
            i += 2
            while i < n and text[i] not in "\r\n":
                i += 1
            continue
        if ch == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i += 2
            continue
        out.append(ch)
        i += 1
    cleaned = "".join(out)
    return re.sub(r",(\s*[}\]])", r"\1", cleaned)


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.loads(strip_jsonc(handle.read()))


def targeted_rules(source):
    rules = source.get("permissions", [])
    return [
        rule
        for rule in rules
        if isinstance(rule, dict)
        and rule.get("action") == "skill"
        and rule.get("effect") == "deny"
    ]


mode = sys.argv[1]
if mode == "rules":
    rules = targeted_rules(load(sys.argv[2]))
    for index, rule in enumerate(rules):
        comma = "," if index < len(rules) - 1 else ""
        print("    " + json.dumps(rule, separators=(", ", ": ")) + comma)

elif mode == "merge":
    destination, source_path = sys.argv[2], sys.argv[3]
    rules = targeted_rules(load(source_path))
    if not rules:
        raise SystemExit("source contains no targeted skill rules")
    data = load(destination)
    if not isinstance(data, dict):
        raise SystemExit(2)
    permissions = data.get("permissions")
    if not isinstance(permissions, list):
        permissions = []
    legacy = {"action": "skill", "resource": "*", "effect": "deny"}
    permissions = [
        rule for rule in permissions if rule != legacy and rule not in rules
    ]
    permissions.extend(rules)
    data["permissions"] = permissions
    with open(destination, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")

elif mode == "check":
    config_path, source_path = sys.argv[2], sys.argv[3]
    rules = targeted_rules(load(source_path))
    legacy = {"action": "skill", "resource": "*", "effect": "deny"}
    try:
        data = load(config_path)
    except Exception:
        print("parse-error")
        raise SystemExit(0)
    if not isinstance(data, dict):
        print("parse-error")
        raise SystemExit(0)
    permissions = data.get("permissions")
    if not isinstance(permissions, list):
        permissions = []

    issues = []
    if legacy in permissions:
        issues.append("legacy")
    for rule in rules:
        if rule not in permissions:
            issues.append("missing:" + rule["resource"])

    indices = [
        index
        for index, rule in enumerate(permissions)
        if isinstance(rule, dict) and rule in rules
    ]
    if indices:
        first = min(indices)
        for rule in permissions[first + 1 :]:
            if not isinstance(rule, dict):
                continue
            if rule.get("effect") not in ("allow", "ask"):
                continue
            action = rule.get("action", "")
            if not (
                action == "*"
                or action == "skill"
                or fnmatch.fnmatchcase("skill", action)
            ):
                continue
            resource = rule.get("resource", "")
            if resource == "*" or any(
                fnmatch.fnmatchcase(target["resource"], resource) for target in rules
            ):
                issues.append("after:" + action + " " + resource)

    if issues:
        for issue in issues:
            print(issue)
    else:
        print("ok")

else:
    raise SystemExit("unknown mode: " + mode)
PY
}

print_skill_rules() {
  if ! command -v python3 >/dev/null 2>&1; then
    log "      python3 is required to print the rules; see $SOURCE/opencode.jsonc"
    return 0
  fi
  log "      Add these rules at the end of your permissions array (keep them last):"
  config_py rules "$SOURCE/opencode.jsonc" | sed 's/^/      /'
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
  cp "$SOURCE/opencode.jsonc" "$dest/opencode.jsonc"
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
  local dest_dir="$1"
  local jsonc="$dest_dir/opencode.jsonc"
  local json="$dest_dir/opencode.json"
  local target=""

  if [ -e "$jsonc" ]; then
    target="$jsonc"
  elif [ -e "$json" ]; then
    target="$json"
  fi

  if [ -z "$target" ]; then
    cp "$SOURCE/opencode.jsonc" "$jsonc"
    log "wrote $jsonc"
    return
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] would merge the targeted skill policy into $target"
    return
  fi

  if [ "${target##*.}" = "jsonc" ]; then
    log "note: $target uses JSONC; leaving it untouched to preserve comments."
    print_skill_rules
    return
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    log "warn: python3 not found; left $target untouched."
    print_skill_rules
    return
  fi

  local tmp
  tmp="$(mktemp "${target}.tmp.XXXXXX")"
  cp "$target" "$tmp"
  if config_py merge "$tmp" "$SOURCE/opencode.jsonc"; then
    backup_path "$target"
    mv "$tmp" "$target"
    log "merged the targeted skill policy into $target (block kept last)"
  else
    rm -f "$tmp"
    log "warn: could not parse $target; left it untouched."
    print_skill_rules
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
    cp "$SOURCE/opencode.jsonc" "$CONFIG_DIR/opencode.jsonc"
    log "wrote $CONFIG_DIR/opencode.jsonc with the targeted skill policy"
  else
    log "note: global installs cannot safely edit your opencode config."
    log "      To suppress only duplicate workflow skills, add this block at the end of its permissions array:"
    print_skill_rules
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
    log "[dry-run] would merge the targeted skill policy into $dest/opencode.json(c)"
    return
  fi
  copy_tree_files "$DATA_DIR/commands" "$dest/commands"
  copy_tree_files "$DATA_DIR/agents" "$dest/agents"
  merge_project_config "$dest"
  log "installed profile '$PROFILE_NAME' into $dest"
  log "next: run /setup in $dir"
}

check_skill_policy() {
  local cfg="$1"
  local label="$2"
  local output line
  [ -f "$cfg" ] || return 0
  if ! command -v python3 >/dev/null 2>&1; then
    log "warn: python3 not found; cannot check the skill policy in $cfg"
    return 0
  fi
  if ! output="$(config_py check "$cfg" "$SOURCE/opencode.jsonc" 2>/dev/null)"; then
    log "warn: $label: could not parse $cfg"
    return 0
  fi
  if [ "$output" = "ok" ]; then
    log "ok: $label: targeted skill policy present (block last)"
    return 0
  fi

  local missing=0 legacy=0
  while IFS= read -r line; do
    case "$line" in
      parse-error)
        log "warn: $label: could not parse $cfg"
        ;;
      legacy)
        legacy=1
        ;;
      missing:*)
        missing=$((missing + 1))
        ;;
      after:*)
        log "warn: $label: rule '${line#after:}' appears after a targeted skill deny and can override it"
        ;;
      *)
        log "warn: $label: $line"
        ;;
    esac
  done <<< "$output"

  if [ "$legacy" -eq 1 ]; then
    log "warn: $label: blanket 'skill * deny' hides every skill; remove it"
  fi
  if [ "$missing" -gt 0 ]; then
    log "note: $label: $missing targeted deny rule(s) missing; those duplicate skills will be advertised"
  fi
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

  local global_cfg project_cfg
  check_skill_policy "$SOURCE/opencode.jsonc" "source"
  for global_cfg in "$CONFIG_DIR/opencode.jsonc" "$CONFIG_DIR/opencode.json"; do
    check_skill_policy "$global_cfg" "global"
  done
  for project_cfg in \
    "$PWD/.opencode/opencode.jsonc" \
    "$PWD/.opencode/opencode.json" \
    "$PWD/opencode.jsonc" \
    "$PWD/opencode.json"; do
    check_skill_policy "$project_cfg" "project"
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
