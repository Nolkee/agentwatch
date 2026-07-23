#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# AgentWatch — install Claude Code hooks
#
# This script adds AgentWatch hooks to ~/.claude/settings.json so that
# Claude Code calls agentwatch on key lifecycle events.
#
# It backs up the existing settings.json before modifying it.
# ---------------------------------------------------------------------------
set -euo pipefail

SETTINGS_FILE="$HOME/.claude/settings.json"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$HOME/.claude/settings.json.agentwatch.bak.$TIMESTAMP"

# Resolve Python path — prefer .venv, fall back to system python3.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PYTHON_BIN=""

if [ -f "$SCRIPT_DIR/.venv/bin/python" ]; then
    PYTHON_BIN="$SCRIPT_DIR/.venv/bin/python"
elif [ -f "$SCRIPT_DIR/.venv/bin/python3" ]; then
    PYTHON_BIN="$SCRIPT_DIR/.venv/bin/python3"
else
    PYTHON_BIN="$(which python3 2>/dev/null || which python 2>/dev/null || echo '')"
fi

if [ -z "$PYTHON_BIN" ]; then
    echo "[AgentWatch] ERROR: Could not find python3. Please install Python 3.10+ and try again."
    exit 1
fi

echo "[AgentWatch] Using Python: $PYTHON_BIN"
echo "[AgentWatch] Settings file: $SETTINGS_FILE"

# ---------------------------------------------------------------------------
# Helper: read a JSON value with python (no jq dependency).
# ---------------------------------------------------------------------------
_json_get() {
    local key="$1"
    if [ -f "$SETTINGS_FILE" ]; then
        $PYTHON_BIN -c "import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps(d.get(sys.argv[2],{}), ensure_ascii=False))" "$SETTINGS_FILE" "$key" 2>/dev/null || echo "{}"
    else
        echo "{}"
    fi
}

# ---------------------------------------------------------------------------
# Backup existing settings.
# ---------------------------------------------------------------------------
if [ -f "$SETTINGS_FILE" ]; then
    cp "$SETTINGS_FILE" "$BACKUP_FILE"
    echo "[AgentWatch] Backed up existing settings to: $BACKUP_FILE"
else
    echo "[AgentWatch] No existing settings.json — creating a fresh one."
fi

# ---------------------------------------------------------------------------
# Build the hook command prefix.
# ---------------------------------------------------------------------------
HOOK_PREFIX="$PYTHON_BIN -m agentwatch.cli hook --event"

# ---------------------------------------------------------------------------
# Determine current hooks (user-level).
# ---------------------------------------------------------------------------
echo "[AgentWatch] Reading current hooks ..."

# ---------------------------------------------------------------------------
# Use Python to merge hooks safely, using the CORRECT Claude Code hook schema.
#
# Correct format per Claude Code settings schema:
# {
#   "hooks": {
#     "PreToolUse": [
#       {
#         "hooks": [
#           { "type": "command", "command": "/path/to/cmd" }
#         ]
#       }
#     ]
#   }
# }
# ---------------------------------------------------------------------------
$PYTHON_BIN << PYEOF
import json, sys
from pathlib import Path

settings_file = Path("$SETTINGS_FILE")

# Load existing or empty.
if settings_file.exists():
    with open(settings_file, "r", encoding="utf-8") as fh:
        try:
            settings = json.load(fh)
        except json.JSONDecodeError:
            print("[AgentWatch] WARNING: Could not parse existing settings.json. Starting fresh.")
            settings = {}
else:
    settings = {}

hooks = settings.get("hooks", {}) or {}

# Define agentwatch hooks in the CORRECT schema format.
# Each event key maps to a list of matcher groups; each group has a "hooks" array.
aw_hook_groups = {
    "PreToolUse": [
        {
            "hooks": [
                {
                    "type": "command",
                    "command": "$PYTHON_BIN -m agentwatch.cli hook --event PreToolUse",
                    "timeout": 15
                }
            ]
        }
    ],
    "PostToolUse": [
        {
            "hooks": [
                {
                    "type": "command",
                    "command": "$PYTHON_BIN -m agentwatch.cli hook --event PostToolUse",
                    "timeout": 15
                }
            ]
        }
    ],
    "Notification": [
        {
            "hooks": [
                {
                    "type": "command",
                    "command": "$PYTHON_BIN -m agentwatch.cli hook --event Notification",
                    "timeout": 15
                }
            ]
        }
    ],
    "Stop": [
        {
            "hooks": [
                {
                    "type": "command",
                    "command": "$PYTHON_BIN -m agentwatch.cli hook --event Stop",
                    "timeout": 15
                }
            ]
        }
    ],
    "PermissionRequest": [
        {
            "hooks": [
                {
                    "type": "command",
                    "command": "$PYTHON_BIN -m agentwatch.cli hook --event PermissionRequest",
                    "timeout": 15
                }
            ]
        }
    ],
    "PermissionDenied": [
        {
            "hooks": [
                {
                    "type": "command",
                    "command": "$PYTHON_BIN -m agentwatch.cli hook --event PermissionDenied",
                    "timeout": 15
                }
            ]
        }
    ],
}

# Track which hook events we modified.
modified = []

for event_name, new_groups in aw_hook_groups.items():
    existing = hooks.get(event_name, []) or []

    # Remove any EXISTING agentwatch entries (of any format) to avoid duplicates,
    # then re-add the correct-format ones.
    cleaned = []
    for entry in existing:
        if not isinstance(entry, dict):
            cleaned.append(entry)
            continue
        # Check if this is a matcher group with agentwatch hooks inside.
        inner_hooks = entry.get("hooks", [])
        if isinstance(inner_hooks, list):
            has_aw = any("agentwatch" in h.get("command", "") for h in inner_hooks if isinstance(h, dict))
            if has_aw:
                continue  # Drop old agentwatch entry
        # Also check for legacy flat format: {"command": "...agentwatch..."}
        if "agentwatch" in entry.get("command", ""):
            continue  # Drop legacy flat agentwatch entry
        cleaned.append(entry)

    # Append the new correct-format groups.
    merged = cleaned + new_groups
    hooks[event_name] = merged
    modified.append(event_name)

if not modified:
    print("[AgentWatch] All hooks are already installed in correct format. Nothing to do.")
    sys.exit(0)

settings["hooks"] = hooks

# Write back.
with open(settings_file, "w", encoding="utf-8") as fh:
    json.dump(settings, fh, ensure_ascii=False, indent=2)

print(f"[AgentWatch] Hooks installed for: {', '.join(modified)}")
print(f"[AgentWatch] Settings written to: {settings_file}")
PYEOF

echo ""
echo "[AgentWatch] Done! Hooks installed successfully (correct schema format)."
echo "[AgentWatch] Backup saved at: $BACKUP_FILE"
echo "[AgentWatch]"
echo "[AgentWatch] To verify, run: cat $SETTINGS_FILE"
echo "[AgentWatch] To test, run:  agentwatch simulate danger"
echo "[AgentWatch] To uninstall, run: bash $SCRIPT_DIR/uninstall_claude_hooks.sh"
echo "[AgentWatch]"
echo "[AgentWatch] Multi-agent (Claude + Grok + Codex + Gemini):"
echo "[AgentWatch]   agentwatch hooks install"
echo "[AgentWatch]   agentwatch hooks status"