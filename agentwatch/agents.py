"""Multi-agent (CLI) support: detection, hook install, event normalisation."""

from __future__ import annotations

import json
import re
import shutil
from datetime import datetime
from pathlib import Path
from typing import Any, Callable

# ---------------------------------------------------------------------------
# Agent registry
# ---------------------------------------------------------------------------

AGENT_IDS = ("claude", "grok", "codex", "gemini")

AGENT_DISPLAY = {
    "claude": "Claude",
    "grok": "Grok",
    "codex": "Codex",
    "gemini": "Gemini",
}

# Vendor-specific event name → AgentWatch canonical event name.
_EVENT_ALIASES: dict[str, str] = {
    # Claude / Grok / Codex (shared vocabulary)
    "PreToolUse": "PreToolUse",
    "PostToolUse": "PostToolUse",
    "Notification": "Notification",
    "Stop": "Stop",
    "PermissionRequest": "PermissionRequest",
    "PermissionDenied": "PermissionDenied",
    "SessionEnd": "Stop",  # treat as task_done
    "session_end": "Stop",
    "sessionEnd": "Stop",
    # Gemini CLI
    "BeforeTool": "PreToolUse",
    "AfterTool": "PostToolUse",
    "AfterAgent": "Stop",
    "BeforeAgent": "Notification",
    # snake / camel variants
    "pre_tool_use": "PreToolUse",
    "post_tool_use": "PostToolUse",
    "permission_request": "PermissionRequest",
    "permission_denied": "PermissionDenied",
    "preToolUse": "PreToolUse",
    "postToolUse": "PostToolUse",
    "permissionRequest": "PermissionRequest",
    "stop": "Stop",
}

CANONICAL_EVENTS = (
    "PreToolUse",
    "PostToolUse",
    "Notification",
    "Stop",
    "PermissionRequest",
    "PermissionDenied",
)


def normalize_event_name(event_name: str) -> str:
    """Map vendor event names onto AgentWatch canonical names."""
    if not event_name:
        return event_name
    if event_name in _EVENT_ALIASES:
        return _EVENT_ALIASES[event_name]
    # Case-insensitive fallback
    for k, v in _EVENT_ALIASES.items():
        if k.lower() == event_name.lower():
            return v
    return event_name


def agent_display(agent: str) -> str:
    return AGENT_DISPLAY.get(agent, agent.capitalize() if agent else "Agent")


def project_root() -> Path:
    return Path(__file__).resolve().parent.parent


def python_bin() -> Path:
    """Prefer project .venv python; fall back to current interpreter."""
    import sys

    venv_py = project_root() / ".venv" / "bin" / "python"
    if venv_py.exists():
        return venv_py
    return Path(sys.executable)


def hook_command(canonical_event: str, agent: str) -> str:
    """Shell command string registered with each CLI's hook system."""
    return (
        f"{python_bin()} -m agentwatch.cli hook "
        f"--event {canonical_event} --agent {agent}"
    )


def _command_group(canonical_event: str, agent: str, timeout: int = 15) -> dict[str, Any]:
    return {
        "hooks": [
            {
                "type": "command",
                "command": hook_command(canonical_event, agent),
                "timeout": timeout,
            }
        ]
    }


def _gemini_command_group(canonical_event: str, timeout_ms: int = 15000) -> dict[str, Any]:
    """Gemini expects name + timeout in milliseconds."""
    return {
        "hooks": [
            {
                "name": f"agentwatch-{canonical_event.lower()}",
                "type": "command",
                "command": hook_command(canonical_event, "gemini"),
                "timeout": timeout_ms,
            }
        ]
    }


# ---------------------------------------------------------------------------
# JSON helpers
# ---------------------------------------------------------------------------


def _read_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2)
        fh.write("\n")


def _backup_file(path: Path, tag: str) -> Path | None:
    if not path.exists():
        return None
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    bak = path.with_name(f"{path.name}.agentwatch.bak.{tag}.{ts}")
    shutil.copy2(path, bak)
    return bak


def _count_agentwatch_hooks(hooks: Any, required: list[str]) -> tuple[int, list[str]]:
    """Count events that contain an agentwatch command among *required* event names."""
    if not isinstance(hooks, dict):
        return 0, []
    found: list[str] = []
    for event_name in required:
        groups = hooks.get(event_name, [])
        if not isinstance(groups, list):
            continue
        hit = False
        for g in groups:
            if not isinstance(g, dict):
                continue
            inner = g.get("hooks", [])
            if isinstance(inner, list):
                for h in inner:
                    if isinstance(h, dict) and "agentwatch" in str(h.get("command", "")):
                        hit = True
                        break
            if "agentwatch" in str(g.get("command", "")):
                hit = True
            if hit:
                break
        if hit:
            found.append(event_name)
    return len(found), found


def _merge_claude_style_hooks(
    settings: dict[str, Any],
    agent: str,
    events: list[str],
) -> dict[str, Any]:
    """Merge AgentWatch hook groups into a Claude-style hooks object."""
    hooks = settings.get("hooks")
    if not isinstance(hooks, dict):
        hooks = {}
    for event_name in events:
        existing = hooks.get(event_name, []) or []
        if not isinstance(existing, list):
            existing = []
        cleaned: list[Any] = []
        for entry in existing:
            if not isinstance(entry, dict):
                cleaned.append(entry)
                continue
            inner = entry.get("hooks", [])
            if isinstance(inner, list) and any(
                isinstance(h, dict) and "agentwatch" in str(h.get("command", ""))
                for h in inner
            ):
                continue
            if "agentwatch" in str(entry.get("command", "")):
                continue
            cleaned.append(entry)
        cleaned.append(_command_group(event_name, agent))
        hooks[event_name] = cleaned
    settings["hooks"] = hooks
    return settings


# ---------------------------------------------------------------------------
# Claude
# ---------------------------------------------------------------------------

CLAUDE_SETTINGS = Path.home() / ".claude" / "settings.json"
CLAUDE_EVENTS = list(CANONICAL_EVENTS)


def claude_status() -> dict[str, Any]:
    settings = _read_json(CLAUDE_SETTINGS)
    count, found = _count_agentwatch_hooks(settings.get("hooks"), CLAUDE_EVENTS)
    return {
        "agent": "claude",
        "display": "Claude",
        "available": CLAUDE_SETTINGS.parent.exists() or shutil.which("claude") is not None,
        "config_path": str(CLAUDE_SETTINGS),
        "installed": count >= 6,
        "hook_count": count,
        "found_events": found,
        "required": 6,
    }


def install_claude() -> dict[str, Any]:
    bak = _backup_file(CLAUDE_SETTINGS, "claude")
    settings = _read_json(CLAUDE_SETTINGS)
    settings = _merge_claude_style_hooks(settings, "claude", CLAUDE_EVENTS)
    _write_json(CLAUDE_SETTINGS, settings)
    st = claude_status()
    st["backup"] = str(bak) if bak else None
    st["action"] = "installed"
    return st


def uninstall_claude() -> dict[str, Any]:
    settings = _read_json(CLAUDE_SETTINGS)
    hooks = settings.get("hooks")
    if isinstance(hooks, dict):
        for event_name in list(hooks.keys()):
            entries = hooks.get(event_name, [])
            if not isinstance(entries, list):
                continue
            kept = []
            for entry in entries:
                if not isinstance(entry, dict):
                    kept.append(entry)
                    continue
                inner = entry.get("hooks", [])
                if isinstance(inner, list):
                    filtered = [
                        h
                        for h in inner
                        if not (isinstance(h, dict) and "agentwatch" in str(h.get("command", "")))
                    ]
                    if len(filtered) < len(inner):
                        if filtered:
                            entry = dict(entry)
                            entry["hooks"] = filtered
                            kept.append(entry)
                        continue
                if "agentwatch" in str(entry.get("command", "")):
                    continue
                kept.append(entry)
            if kept:
                hooks[event_name] = kept
            else:
                del hooks[event_name]
        if hooks:
            settings["hooks"] = hooks
        else:
            settings.pop("hooks", None)
        _write_json(CLAUDE_SETTINGS, settings)
    return claude_status()


# ---------------------------------------------------------------------------
# Grok — ~/.grok/hooks/agentwatch.json (always trusted global hooks)
# ---------------------------------------------------------------------------

GROK_HOOKS_DIR = Path.home() / ".grok" / "hooks"
GROK_HOOKS_FILE = GROK_HOOKS_DIR / "agentwatch.json"
# Grok has no PermissionRequest event; Notification + PermissionDenied cover attention.
# SessionEnd is a backup when a turn-end Stop is skipped (e.g. some channel closes).
GROK_EVENTS = [
    "PreToolUse",
    "PostToolUse",
    "Notification",
    "Stop",
    "SessionEnd",
    "PermissionDenied",
]


def grok_status() -> dict[str, Any]:
    available = (Path.home() / ".grok").exists() or shutil.which("grok") is not None
    data = _read_json(GROK_HOOKS_FILE)
    count, found = _count_agentwatch_hooks(data.get("hooks"), GROK_EVENTS)
    return {
        "agent": "grok",
        "display": "Grok",
        "available": available,
        "config_path": str(GROK_HOOKS_FILE),
        # Stop + Notification is the minimum useful set; SessionEnd is optional backup.
        "installed": count >= 4,
        "hook_count": count,
        "found_events": found,
        "required": len(GROK_EVENTS),
    }


def install_grok() -> dict[str, Any]:
    GROK_HOOKS_DIR.mkdir(parents=True, exist_ok=True)
    bak = _backup_file(GROK_HOOKS_FILE, "grok")
    payload: dict[str, Any] = {"hooks": {}}
    for event_name in GROK_EVENTS:
        # SessionEnd is wired to the same Stop handler (task_done).
        hook_event = "Stop" if event_name == "SessionEnd" else event_name
        timeout = 15
        payload["hooks"][event_name] = [_command_group(hook_event, "grok", timeout=timeout)]
    _write_json(GROK_HOOKS_FILE, payload)
    st = grok_status()
    st["backup"] = str(bak) if bak else None
    st["action"] = "installed"
    st["note"] = (
        "Grok loads hooks at session start. Restart Grok, or open /hooks and press r to reload."
    )
    return st


def uninstall_grok() -> dict[str, Any]:
    if GROK_HOOKS_FILE.exists():
        GROK_HOOKS_FILE.unlink()
    return grok_status()


# ---------------------------------------------------------------------------
# Codex — ~/.codex/hooks.json + enable features.hooks in config.toml
# ---------------------------------------------------------------------------

CODEX_HOME = Path.home() / ".codex"
CODEX_HOOKS_FILE = CODEX_HOME / "hooks.json"
CODEX_CONFIG = CODEX_HOME / "config.toml"
CODEX_EVENTS = [
    "PreToolUse",
    "PostToolUse",
    "Notification",
    "Stop",
    "PermissionRequest",
]


def codex_status() -> dict[str, Any]:
    available = CODEX_HOME.exists() or shutil.which("codex") is not None
    data = _read_json(CODEX_HOOKS_FILE)
    count, found = _count_agentwatch_hooks(data.get("hooks"), CODEX_EVENTS)
    # Also accept TOML-embedded hooks that mention agentwatch.
    toml_hit = False
    if CODEX_CONFIG.exists():
        try:
            text = CODEX_CONFIG.read_text(encoding="utf-8")
            if "agentwatch" in text and "hooks" in text:
                toml_hit = True
        except Exception:
            pass
    installed = count >= 4 or (toml_hit and count >= 2)
    return {
        "agent": "codex",
        "display": "Codex",
        "available": available,
        "config_path": str(CODEX_HOOKS_FILE),
        "installed": installed,
        "hook_count": count,
        "found_events": found,
        "required": len(CODEX_EVENTS),
        "features_note": "requires [features] hooks = true (installer sets this)",
    }


def _ensure_codex_hooks_feature() -> None:
    """Ensure config.toml has hooks feature enabled and hooks path set."""
    CODEX_HOME.mkdir(parents=True, exist_ok=True)
    text = ""
    if CODEX_CONFIG.exists():
        text = CODEX_CONFIG.read_text(encoding="utf-8")

    # Enable [features] hooks = true
    if re.search(r"(?m)^\s*hooks\s*=\s*true\s*$", text):
        pass  # already enabled somewhere; still ensure [features] block is correct
    if "[features]" not in text:
        text = text.rstrip() + "\n\n[features]\nhooks = true\n"
    else:
        # Inside features section, set hooks = true if missing/false
        def _patch_features(m: re.Match[str]) -> str:
            block = m.group(0)
            if re.search(r"(?m)^\s*hooks\s*=", block):
                block = re.sub(r"(?m)^\s*hooks\s*=\s*\S+", "hooks = true", block)
            else:
                block = block.rstrip() + "\nhooks = true\n"
            return block

        text2, n = re.subn(
            r"(?ms)^\[features\](.*?)(?=^\[|\Z)",
            _patch_features,
            text,
            count=1,
        )
        text = text2 if n else text + "\n[features]\nhooks = true\n"

    # Point top-level hooks path at our hooks.json when unset.
    hooks_path = str(CODEX_HOOKS_FILE)
    if not re.search(r'(?m)^\s*hooks\s*=\s*["\']', text):
        # Prefer inserting near top after any model_* keys, else append.
        insert = f'hooks = "{hooks_path}"\n'
        if re.search(r"(?m)^model\s*=", text):
            text = re.sub(r"(?m)^(model\s*=\s*.*)$", r"\1\n" + insert.rstrip(), text, count=1)
        else:
            text = insert + "\n" + text.lstrip()
    else:
        # Update existing hooks path only if it looks like a path string and not a table
        text = re.sub(
            r'(?m)^\s*hooks\s*=\s*["\'][^"\']*["\']\s*$',
            f'hooks = "{hooks_path}"',
            text,
            count=1,
        )

    CODEX_CONFIG.write_text(text if text.endswith("\n") else text + "\n", encoding="utf-8")


def install_codex() -> dict[str, Any]:
    CODEX_HOME.mkdir(parents=True, exist_ok=True)
    bak_hooks = _backup_file(CODEX_HOOKS_FILE, "codex")
    bak_cfg = _backup_file(CODEX_CONFIG, "codex")

    payload: dict[str, Any] = {"hooks": {}}
    for event_name in CODEX_EVENTS:
        payload["hooks"][event_name] = [_command_group(event_name, "codex", timeout=15)]
    _write_json(CODEX_HOOKS_FILE, payload)
    _ensure_codex_hooks_feature()

    st = codex_status()
    st["backup"] = str(bak_hooks) if bak_hooks else None
    st["config_backup"] = str(bak_cfg) if bak_cfg else None
    st["action"] = "installed"
    return st


def uninstall_codex() -> dict[str, Any]:
    if CODEX_HOOKS_FILE.exists():
        data = _read_json(CODEX_HOOKS_FILE)
        hooks = data.get("hooks")
        if isinstance(hooks, dict):
            for event_name in list(hooks.keys()):
                groups = hooks.get(event_name, [])
                if not isinstance(groups, list):
                    continue
                kept = []
                for g in groups:
                    if isinstance(g, dict):
                        inner = g.get("hooks", [])
                        if isinstance(inner, list) and any(
                            isinstance(h, dict) and "agentwatch" in str(h.get("command", ""))
                            for h in inner
                        ):
                            continue
                    kept.append(g)
                if kept:
                    hooks[event_name] = kept
                else:
                    del hooks[event_name]
            if hooks:
                data["hooks"] = hooks
                _write_json(CODEX_HOOKS_FILE, data)
            else:
                CODEX_HOOKS_FILE.unlink(missing_ok=True)
    return codex_status()


# ---------------------------------------------------------------------------
# Gemini — ~/.gemini/settings.json hooks with native event names
# ---------------------------------------------------------------------------

GEMINI_SETTINGS = Path.home() / ".gemini" / "settings.json"
# Map: Gemini event → canonical AgentWatch event (for command --event)
GEMINI_EVENT_MAP = {
    "BeforeTool": "PreToolUse",
    "AfterTool": "PostToolUse",
    "Notification": "Notification",
    "AfterAgent": "Stop",
}


def gemini_status() -> dict[str, Any]:
    available = GEMINI_SETTINGS.parent.exists() or shutil.which("gemini") is not None
    settings = _read_json(GEMINI_SETTINGS)
    count, found = _count_agentwatch_hooks(settings.get("hooks"), list(GEMINI_EVENT_MAP.keys()))
    return {
        "agent": "gemini",
        "display": "Gemini",
        "available": available,
        "config_path": str(GEMINI_SETTINGS),
        "installed": count >= 3,
        "hook_count": count,
        "found_events": found,
        "required": len(GEMINI_EVENT_MAP),
    }


def install_gemini() -> dict[str, Any]:
    bak = _backup_file(GEMINI_SETTINGS, "gemini")
    settings = _read_json(GEMINI_SETTINGS)
    hooks = settings.get("hooks")
    if not isinstance(hooks, dict):
        hooks = {}

    for gemini_event, canonical in GEMINI_EVENT_MAP.items():
        existing = hooks.get(gemini_event, []) or []
        if not isinstance(existing, list):
            existing = []
        cleaned: list[Any] = []
        for entry in existing:
            if not isinstance(entry, dict):
                cleaned.append(entry)
                continue
            inner = entry.get("hooks", [])
            if isinstance(inner, list) and any(
                isinstance(h, dict) and "agentwatch" in str(h.get("command", ""))
                for h in inner
            ):
                continue
            # Also drop by name prefix
            if isinstance(inner, list) and any(
                isinstance(h, dict) and str(h.get("name", "")).startswith("agentwatch-")
                for h in inner
            ):
                continue
            cleaned.append(entry)
        cleaned.append(_gemini_command_group(canonical, timeout_ms=15000))
        hooks[gemini_event] = cleaned

    settings["hooks"] = hooks
    _write_json(GEMINI_SETTINGS, settings)
    st = gemini_status()
    st["backup"] = str(bak) if bak else None
    st["action"] = "installed"
    return st


def uninstall_gemini() -> dict[str, Any]:
    settings = _read_json(GEMINI_SETTINGS)
    hooks = settings.get("hooks")
    if isinstance(hooks, dict):
        for event_name in list(hooks.keys()):
            entries = hooks.get(event_name, [])
            if not isinstance(entries, list):
                continue
            kept = []
            for entry in entries:
                if not isinstance(entry, dict):
                    kept.append(entry)
                    continue
                inner = entry.get("hooks", [])
                if isinstance(inner, list):
                    filtered = [
                        h
                        for h in inner
                        if not (
                            isinstance(h, dict)
                            and (
                                "agentwatch" in str(h.get("command", ""))
                                or str(h.get("name", "")).startswith("agentwatch-")
                            )
                        )
                    ]
                    if len(filtered) < len(inner):
                        if filtered:
                            entry = dict(entry)
                            entry["hooks"] = filtered
                            kept.append(entry)
                        continue
                kept.append(entry)
            if kept:
                hooks[event_name] = kept
            else:
                del hooks[event_name]
        if hooks:
            settings["hooks"] = hooks
        else:
            settings.pop("hooks", None)
        _write_json(GEMINI_SETTINGS, settings)
    return gemini_status()


# ---------------------------------------------------------------------------
# Unified API
# ---------------------------------------------------------------------------

_INSTALLERS: dict[str, Callable[[], dict[str, Any]]] = {
    "claude": install_claude,
    "grok": install_grok,
    "codex": install_codex,
    "gemini": install_gemini,
}

_UNINSTALLERS: dict[str, Callable[[], dict[str, Any]]] = {
    "claude": uninstall_claude,
    "grok": uninstall_grok,
    "codex": uninstall_codex,
    "gemini": uninstall_gemini,
}

_STATUS: dict[str, Callable[[], dict[str, Any]]] = {
    "claude": claude_status,
    "grok": grok_status,
    "codex": codex_status,
    "gemini": gemini_status,
}


def status_all() -> list[dict[str, Any]]:
    return [fn() for fn in _STATUS.values()]


def status_one(agent: str) -> dict[str, Any]:
    agent = agent.lower()
    if agent not in _STATUS:
        raise ValueError(f"Unknown agent: {agent}. Choose from {', '.join(AGENT_IDS)}")
    return _STATUS[agent]()


def install_agents(agents: list[str] | None = None) -> list[dict[str, Any]]:
    """Install hooks for the given agents (default: all available)."""
    targets = agents or list(AGENT_IDS)
    results = []
    for agent in targets:
        agent = agent.lower()
        if agent not in _INSTALLERS:
            results.append({"agent": agent, "error": "unknown agent"})
            continue
        st = _STATUS[agent]()
        if not st.get("available") and agent != "claude":
            # Still allow install if user forces — write files for later use.
            pass
        try:
            results.append(_INSTALLERS[agent]())
        except Exception as exc:
            results.append({"agent": agent, "error": str(exc), "action": "failed"})
    return results


def uninstall_agents(agents: list[str] | None = None) -> list[dict[str, Any]]:
    targets = agents or list(AGENT_IDS)
    results = []
    for agent in targets:
        agent = agent.lower()
        if agent not in _UNINSTALLERS:
            results.append({"agent": agent, "error": "unknown agent"})
            continue
        try:
            results.append(_UNINSTALLERS[agent]())
        except Exception as exc:
            results.append({"agent": agent, "error": str(exc), "action": "failed"})
    return results
