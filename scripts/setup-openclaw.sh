#!/usr/bin/env bash
# Read openclaw/config.yaml + .env → write openclaw/runtime/openclaw.json
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_YAML="$REPO_ROOT/openclaw/config.yaml"
RUNTIME_DIR="$REPO_ROOT/openclaw/runtime"

if [[ ! -f "$CONFIG_YAML" ]]; then
  echo "error: missing $CONFIG_YAML" >&2
  exit 1
fi

if [[ ! -f "$REPO_ROOT/.env" && -f "$REPO_ROOT/.env.example" ]]; then
  echo "Tip: cp .env.example .env and add Telegram token / chat ID before starting gateway."
fi

mkdir -p "$RUNTIME_DIR"

python3 - "$REPO_ROOT" "$CONFIG_YAML" "$RUNTIME_DIR/openclaw.json" <<'PY'
import ast
import json
import sys
from pathlib import Path
from typing import Dict, List, Tuple, Union


def parse_yaml(path: Path) -> dict:
    lines = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].rstrip()
        if line.strip():
            lines.append(line)

    root = {}
    stack = [(0, root)]  # type: List[Tuple[int, Union[dict, list]]]

    def current_container():
        return stack[-1][1]

    def next_stripped(index: int):
        if index + 1 >= len(lines):
            return None, None
        nxt = lines[index + 1]
        return len(nxt) - len(nxt.lstrip()), nxt.strip()

    for index, line in enumerate(lines):
        indent = len(line) - len(line.lstrip())
        while len(stack) > 1 and indent <= stack[-1][0]:
            stack.pop()

        container = current_container()
        stripped = line.strip()

        if stripped.startswith("- "):
            item = stripped[2:].strip()
            if not isinstance(container, list):
                raise SystemExit(f"Invalid list entry in {path}: {line}")
            if ":" in item:
                item_key, _, item_val = item.partition(":")
                item_dict = {item_key.strip(): item_val.strip().strip('"').strip("'")}
                container.append(item_dict)
                stack.append((indent, item_dict))
            else:
                if item.startswith(('"', "'")):
                    item = ast.literal_eval(item)
                container.append(item)
            continue

        key, sep, value = stripped.partition(":")
        if not sep:
            raise SystemExit(f"Invalid line in {path}: {line}")
        key = key.strip()
        value = value.strip()

        if not value:
            next_indent, next_line = next_stripped(index)
            if next_line and next_line.startswith("- ") and next_indent > indent:
                child = []  # type: Union[dict, list]
            else:
                child = {}
            if not isinstance(container, dict):
                raise SystemExit(f"Invalid mapping in {path}: {line}")
            container[key] = child
            stack.append((indent, child))
            continue

        if value.startswith(('"', "'")):
            parsed = ast.literal_eval(value)
        elif value.startswith("[") and value.endswith("]"):
            parsed = ast.literal_eval(value)
        else:
            parsed = coerce_value(value)

        if not isinstance(container, dict):
            raise SystemExit(f"Invalid key in {path}: {line}")
        container[key] = parsed

    return root


def coerce_value(value):
    if isinstance(value, str):
        if value.startswith(('"', "'")):
            return ast.literal_eval(value)
        try:
            return int(value)
        except ValueError:
            try:
                return float(value)
            except ValueError:
                return value
    return value


def as_list(node: dict, key: str) -> list:
    value = node.get(key, [])
    return value if isinstance(value, list) else []


def main() -> None:
    repo_root = Path(sys.argv[1])
    config_yaml = Path(sys.argv[2])
    output = Path(sys.argv[3])

    env: dict[str, str] = {}
    env_path = repo_root / ".env"
    if env_path.exists():
        for line in env_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            env[key.strip()] = value.strip().strip('"').strip("'")

    cfg = parse_yaml(config_yaml)
    agents_cfg = cfg.get("agents", {})
    if not isinstance(agents_cfg, dict) or not agents_cfg:
        raise SystemExit("openclaw/config.yaml must define agents")

    default_agent = cfg.get("default_agent", next(iter(agents_cfg)))
    ollama_cfg = cfg.get("ollama", {})
    gateway_cfg = cfg.get("gateway", {})
    tools_cfg = cfg.get("tools", {})
    access_cfg = cfg.get("access", {})

    ollama_host = env.get("OLLAMA_HOST", ollama_cfg.get("base_url", "http://127.0.0.1:11434"))
    gateway_token = env.get("OPENCLAW_GATEWAY_TOKEN", "change-me-after-setup")
    telegram_token = env.get("TELEGRAM_BOT_TOKEN", "")
    chat_id = env.get("TELEGRAM_NOTIFY_CHAT_ID", "")

    agent_list = []
    for agent_id, agent in agents_cfg.items():
        if not isinstance(agent, dict):
            continue
        workspace_rel = agent.get("workspace", f"agents/{agent_id}")
        workspace = str((repo_root / workspace_rel).resolve())
        mentions = as_list(agent, "mentions")
        entry = {
            "id": agent_id,
            "default": agent_id == default_agent,
            "name": agent.get("name", agent_id),
            "workspace": workspace,
            "model": agent.get("model", "ollama/qwen2.5:3b"),
            "identity": {
                "name": agent.get("name", agent_id),
                "emoji": agent.get("emoji", "🤖"),
            },
            "agentDir": str((repo_root / "openclaw/runtime/agents" / agent_id / "agent").resolve()),
        }
        if mentions:
            entry["groupChat"] = {"mentionPatterns": mentions}
        params = agent.get("parameters") or agent.get("params")
        if isinstance(params, dict) and params:
            entry["params"] = {k: coerce_value(v) if isinstance(v, str) else v for k, v in params.items()}
        delegates = as_list(agent, "delegates_to")
        if delegates:
            entry["subagents"] = {"allowAgents": delegates}
        agent_tools = agent.get("tools")
        if isinstance(agent_tools, dict) and agent_tools.get("profile"):
            entry["tools"] = {"profile": agent_tools["profile"]}
        agent_list.append(entry)

    default_workspace = agent_list[0]["workspace"] if agent_list else str(repo_root / "agents/main")
    default_model = agent_list[0]["model"] if agent_list else "ollama/qwen2.5:3b"

    models = []
    for item in as_list(ollama_cfg, "models"):
        if isinstance(item, dict):
            models.append({"id": item["id"], "name": item.get("name", item["id"])})
        else:
            models.append({"id": str(item), "name": str(item)})

    if not models:
        models = [{"id": "qwen2.5:3b", "name": "Qwen 2.5 3B"}]

    config = {
        "agents": {
            "defaults": {
                "workspace": default_workspace,
                "model": default_model,
            },
            "list": agent_list,
        },
        "gateway": {
            "mode": "local",
            "auth": {"mode": "token", "token": gateway_token},
            "port": int(gateway_cfg.get("port", 18790)),
            "bind": gateway_cfg.get("bind", "loopback"),
        },
        "session": {"dmScope": "per-channel-peer"},
        "tools": {"profile": tools_cfg.get("profile", "minimal")},
        "plugins": {
            "entries": {
                "ollama": {"enabled": True},
                "telegram": {"enabled": True},
            }
        },
        "models": {
            "providers": {
                "ollama": {
                    "baseUrl": ollama_host,
                    "models": models,
                }
            }
        },
        "channels": {
            "telegram": {
                "enabled": True,
                "groups": {
                    "*": {
                        "requireMention": bool(access_cfg.get("groups_require_mention", True))
                    }
                },
                "botToken": telegram_token,
                "dmPolicy": access_cfg.get("telegram_dm_policy", "allowlist"),
                "allowFrom": [chat_id] if chat_id else [],
            }
        },
        "skills": {
            "install": {"nodeManager": "npm"},
            "workshop": {"approvalPolicy": "pending"},
        },
        "hooks": {
            "internal": {
                "enabled": True,
                "entries": {"session-memory": {"enabled": True}},
            }
        },
        "commands": {
            "ownerAllowFrom": [f"telegram:{chat_id}"] if chat_id else [],
        },
    }

    output.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {output}")


if __name__ == "__main__":
    main()
PY

echo
echo "Config ready. Next:"
echo "  ./scripts/openclaw.sh gateway install --force --wrapper $SCRIPT_DIR/openclaw.sh"
echo "  ./scripts/openclaw.sh gateway start"
echo "  ./scripts/openclaw.sh gateway status"
