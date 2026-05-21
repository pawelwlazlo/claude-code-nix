#!/usr/bin/env bash
# nerdbrain-load.sh — SessionStart hook: loads project entity page into context.
set -u
umask 077

# ── Configuration (overridable via env for testing) ────────────────────────────
VAULT="${NERDBRAIN_VAULT:-$HOME/obsidian/nerdbrain}"
PROJECTS_DIR="$VAULT/5-wiki/entities/projects"
ALIASES="${NERDBRAIN_ALIASES:-$HOME/.claude/nerdbrain.aliases}"
KILL_SWITCH="$HOME/.claude/nerdbrain.disabled"

# ── _resolve_slug ──────────────────────────────────────────────────────────────
# Resolves a stable, filesystem-safe project slug from:
#   1. .nerdbrain-slug file in $PWD (explicit override)
#   2. git remote.origin.url (normalized + alias-substituted)
#   3. basename of $PWD (fallback)
_resolve_slug() {
  # 1. Override file
  if [ -f "$PWD/.nerdbrain-slug" ]; then
    head -n1 "$PWD/.nerdbrain-slug" | tr -cd 'a-z0-9-' | head -c 200
    return
  fi

  # 2. Git remote
  local url
  url=$(git -C "$PWD" config --get remote.origin.url 2>/dev/null || true)
  if [ -n "$url" ]; then
    # Normalize: strip prefixes/suffixes, fold separators
    local cleaned
    cleaned=$(printf '%s' "$url" \
              | sed -E 's|^git@||; s|^https?://||; s|:|/|; s|\.git$||')
    # Apply host alias (first path segment)
    if [ -f "$ALIASES" ]; then
      local host al
      host="${cleaned%%/*}"
      al=$(grep -E "^${host}=" "$ALIASES" 2>/dev/null \
           | head -n1 | cut -d= -f2 | tr -cd 'a-z0-9-')
      [ -n "$al" ] && cleaned="$al/${cleaned#*/}"
    fi
    printf '%s' "$cleaned" | tr '/.' '--' | tr '[:upper:]' '[:lower:]'
    return
  fi

  # 3. Basename fallback
  basename "$PWD" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-'
}

# ── _probe_tier ────────────────────────────────────────────────────────────────
# Returns: rest | rest-http | cli | file | none
_probe_tier() {
  # Tier 1: HTTPS REST API
  if curl -k -s -m 1 -o /dev/null -w '%{http_code}' \
       https://127.0.0.1:27124/ 2>/dev/null | grep -q '^200$'; then
    echo rest; return
  fi
  # Tier 1b: HTTP REST API
  if curl -s -m 1 -o /dev/null -w '%{http_code}' \
       http://127.0.0.1:27123/ 2>/dev/null | grep -q '^200$'; then
    echo rest-http; return
  fi
  # Tier 2: obsidian CLI (binary present on PATH)
  # Note: command -v is a shell builtin — no execution, no hang.
  # Vault accessibility is verified lazily when the CLI is actually invoked.
  if command -v obsidian >/dev/null 2>&1; then
    echo cli; return
  fi
  # Tier 3: plain filesystem (vault directory present)
  [ -d "$VAULT" ] && echo file || echo none
}

# ── _json_out ──────────────────────────────────────────────────────────────────
# Prints a valid SessionStart hook JSON object.
# Usage: _json_out "$context_string"
_json_out() {
  python3 -c '
import json, sys
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": sys.argv[1]
    }
}))' "${1:-}"
}

# ── _read_api_key ──────────────────────────────────────────────────────────────
# Returns the apiKey from the Obsidian Local REST API plugin config, or empty.
_read_api_key() {
  local kf="$VAULT/.obsidian/plugins/obsidian-local-rest-api/data.json"
  [ -f "$kf" ] || return 0
  # Warn on loose permissions (informational only — never block).
  local mode
  mode=$(stat -f '%Lp' "$kf" 2>/dev/null || stat -c '%a' "$kf" 2>/dev/null || echo "")
  case "$mode" in
    600|400) ;;
    *) printf 'nerdbrain-load: warning: %s has mode %s (expected 600)\n' "$kf" "$mode" >&2 ;;
  esac
  python3 -c "
import json
try:
    print(json.load(open('$kf')).get('apiKey', ''))
except Exception:
    pass
"
}

# ── _read_page ─────────────────────────────────────────────────────────────────
# Args: slug api_key tier
# Read order:
#   1. Local filesystem (fastest, no auth, no IPC)
#   2. REST API (rest|rest-http tiers, requires api_key)
#   3. obsidian CLI (cli tier, slow but reliable)
# Returns 0 whether page exists or not; empty stdout means "no page found".
_read_page() {
  local slug="$1" api_key="$2" tier="$3"
  local rel="5-wiki/entities/projects/$slug.md"
  local page_path="$VAULT/$rel"

  # 1. Filesystem
  if [ -f "$page_path" ]; then
    cat "$page_path"
    return 0
  fi

  # 2. REST API (curl -f returns non-zero on 4xx/5xx — suppresses error body
  # so we don't leak "Not Found" JSON into the context).
  if { [ "$tier" = rest ] || [ "$tier" = rest-http ]; } && [ -n "$api_key" ]; then
    local base
    [ "$tier" = rest ] && base="https://127.0.0.1:27124" || base="http://127.0.0.1:27123"
    curl -k -s -f -m 2 \
      -H "Authorization: Bearer $api_key" \
      "$base/vault/$rel" 2>/dev/null || true
    return 0
  fi

  # 3. obsidian CLI
  if [ "$tier" = cli ] && command -v obsidian >/dev/null 2>&1; then
    local vault_name; vault_name=$(basename "$VAULT")
    obsidian read vault="$vault_name" path="$rel" 2>/dev/null || true
  fi

  return 0
}

# ── Guard: prevent execution when sourced for testing ─────────────────────────
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

# ══ Main ═══════════════════════════════════════════════════════════════════════

# Kill switches: global or per-project
if [ -f "$KILL_SWITCH" ] || [ -f "$PWD/.nerdbrain-disabled" ]; then
  _json_out ""
  exit 0
fi

# No-op when CWD is inside the vault (vault has its own CLAUDE.md)
if [ -d "$VAULT" ]; then
  cwd_real=$(cd "$PWD" 2>/dev/null && pwd -P)
  vault_real=$(cd "$VAULT" 2>/dev/null && pwd -P)
  case "$cwd_real/" in
    "$vault_real"/*) _json_out ""; exit 0 ;;
  esac
fi

# Resolve slug and probe tier
SLUG=$(_resolve_slug)
TIER=$(_probe_tier)
API_KEY=$(_read_api_key)

# Read entity page (empty string if none)
PAGE_CONTENT=$(_read_page "$SLUG" "$API_KEY" "$TIER" 2>/dev/null || true)

# Detect sync conflicts
CONFLICTS=""
if [ -d "$PROJECTS_DIR" ]; then
  CONFLICTS=$(ls "$PROJECTS_DIR"/*sync-conflict*"$SLUG"* 2>/dev/null || true)
fi

# Build context string
CTX=""
if [ -n "$CONFLICTS" ]; then
  CTX+=$'\n**WARNING:** sync-conflict files present for this slug in 5-wiki/entities/projects/. Do NOT write to this page until the user resolves the conflicts in Obsidian.\n\n'
fi
CTX+="## Nerdbrain second brain — session context"$'\n\n'
CTX+="slug: \`$SLUG\`"$'\n'
CTX+="tier: \`$TIER\`"$'\n'
if [ -n "$API_KEY" ]; then
  CTX+="OBSIDIAN_API_KEY: present — use header \`Authorization: Bearer <key>\` with https://127.0.0.1:27124 (tier=rest) or http://127.0.0.1:27123 (tier=rest-http)"$'\n'
fi
CTX+=$'\n'
if [ -n "$PAGE_CONTENT" ]; then
  CTX+="## Project page from nerdbrain wiki"$'\n\n'
  CTX+="$PAGE_CONTENT"$'\n\n'
  CTX+="_Path: \`5-wiki/entities/projects/$SLUG.md\`. Update per the write protocol in CLAUDE.md._"$'\n'
else
  CTX+="## Project not yet in nerdbrain wiki"$'\n\n'
  CTX+="No page at \`5-wiki/entities/projects/$SLUG.md\` yet. Build understanding during the session and create a page when a write trigger fires (see CLAUDE.md)."$'\n'
fi

_json_out "$CTX"
exit 0
