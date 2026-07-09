# Junebug

![Junebug system diagram — Telegram → Main Agent → Agent 1 (website) → approval gate → deploy](assets/junebug-diagram.png)

Junebug is a local-first multi-agent assistant built on OpenClaw (gateway, sessions, tools, skills). Telegram is the interface; the Main Agent routes requests to specialist agents; and every external action (git push, email send) requires explicit approval in Telegram. All inference runs locally through Ollama on a home Mac — no cloud APIs required for v1.

**Roadmap:** [roadmap.md](roadmap.md)

---

## Architecture

The diagram shows the full target layout (including future Agent N and per-agent fine-tunes via Path 2). Dashed boxes are not built yet.

| Piece | Role |
|-------|------|
| **Telegram** | Shared interface + approval channel |
| **OpenClaw gateway** | Routing, pairing, allowlist, loopback bind — dispatches only |
| **Main Agent** (`main`) | Entry point; chat; handle or delegate. Workspace: `agents/main/` |
| **Website Agent** (`website`, Agent 1) | Site edits via `@website` or delegation. Workspace: `agents/website/` |
| **Approval gate** | Nothing leaves the Mac without Telegram confirmation |
| **Ollama** | Local inference at `127.0.0.1:11434` |
| **Claude Code** | Dev-time only — edits config and personas; not in the runtime loop |

**Path 1 (now):** `ollama pull qwen2.5:3b` — direct download, no GPU.

**Path 2 (later):** dataset → Colab/Kaggle LoRA → `ollama create` adapter on the Mac.

### Current implementation

Junebug currently uses a single local Ollama model (`qwen2.5:3b`). The Main Agent and Website Agent are separate OpenClaw workspaces that share the same model process — two agent identities (tools, `SOUL.md`), not two brains on disk. This keeps CPU/RAM load low on an Intel Mac without a GPU. Future releases may assign different models or fine-tunes to specialist agents (Phase 3+ in the roadmap).

Website flow: **propose diff → approve in Telegram → commit + push → GitHub Pages auto-deploys**.

---

## Repo structure

```
junebug/
├── assets/
│   └── junebug-diagram.png   # Architecture diagram
├── .env.example              # secrets template (copy to .env)
├── openclaw/
│   └── config.yaml           # agents, models, gateway, access
├── agents/
│   ├── main/                 # Main Agent workspace
│   └── website/              # Website agent workspace
├── scripts/
│   ├── setup-openclaw.sh     # config.yaml + .env → openclaw/runtime/openclaw.json
│   └── openclaw.sh           # always use this wrapper, not bare `openclaw`
└── roadmap.md
```

Generated at runtime (gitignored): `openclaw/runtime/`

---

## Prerequisites

- macOS (Intel Mac, CPU-only)
- [Homebrew](https://brew.sh), [Ollama](https://ollama.com) + `qwen2.5:3b`, [OpenClaw](https://openclaw.ai)
- Telegram bot token ([@BotFather](https://t.me/BotFather))
- Personal site repo cloned locally (default: `~/Desktop/foobaraguilar.github.io`)

---

## Quick start

```bash
git clone <your-repo-url> ~/junebug
cd ~/junebug

brew install ollama && brew services start ollama && ollama pull qwen2.5:3b
curl -fsSL https://openclaw.ai/install.sh | bash   # if needed

cp .env.example .env
# TELEGRAM_BOT_TOKEN, TELEGRAM_NOTIFY_CHAT_ID, OPENCLAW_GATEWAY_TOKEN

./scripts/setup-openclaw.sh
./scripts/openclaw.sh config validate
./scripts/openclaw.sh gateway install --force --wrapper scripts/openclaw.sh
./scripts/openclaw.sh gateway start
```

Always run OpenClaw through `./scripts/openclaw.sh` so state stays in `openclaw/runtime/`.

**Telegram chat ID:** message the bot, then check `https://api.telegram.org/bot<TOKEN>/getUpdates` for `"chat":{"id":…}`. Set `TELEGRAM_NOTIFY_CHAT_ID` in `.env`, re-run setup, restart gateway.

**If the LaunchAgent fails (exit 126),** run:

```bash
./scripts/openclaw.sh gateway --port 18790
```

This is currently the recommended workaround (dedicated terminal or tmux).

---

## Configuration

| File | Purpose |
|------|---------|
| `openclaw/config.yaml` | Agents, models, delegation, gateway, access |
| `.env` | Bot token, chat ID, gateway token, `WEBSITE_REPO` |
| `agents/*/SOUL.md` | Agent persona and rules (injected each session) |
| `agents/main/{USER,IDENTITY,AGENTS,TOOLS}.md` | Operator profile and ops notes |

After changing `config.yaml` or `.env`:

```bash
./scripts/setup-openclaw.sh
./scripts/openclaw.sh gateway restart
```

---

## Usage

```text
hi                                                          # general chat
@website change the hero tagline to "Hello world"           # direct site edit
update my site hero to say "Hello world"                    # via main → delegates
```

Dashboard (local only): http://127.0.0.1:18790/

---

## Security

- **Never commit `.env`** — bot token and gateway token are secrets.
- Gateway binds to **loopback** only; Telegram DMs use **allowlist** (`TELEGRAM_NOTIFY_CHAT_ID`).
- Website agent **never pushes without your explicit approval**.
- Regenerate the bot token via BotFather if it was ever exposed.

---

## Development

| Task | Tool |
|------|------|
| Edit routing, models, agents | `openclaw/config.yaml` → `./scripts/setup-openclaw.sh` |
| Edit agent behavior | `agents/<agent>/SOUL.md` and workspace files |
| Validate config | `./scripts/openclaw.sh config validate` |
| Gateway logs | `/tmp/openclaw/openclaw-*.log` |

---

## Status

| Component | State |
|-----------|--------|
| Ollama | Ready |
| OpenClaw | Working |
| Telegram | Configured |
| Website Agent | Stub — delegation not yet tested E2E |
| Gateway LaunchAgent | Use foreground start (see Quick start) |

---

## Next steps

**Finish workspace docs** in `agents/main/`: `USER.md`, `IDENTITY.md`, `SOUL.md`, `AGENTS.md`, `TOOLS.md`

**End-to-end test:**

- [ ] Gateway running
- [ ] DM bot — reply from main
- [ ] `@website` — small copy change on site repo
- [ ] Approve → verify commit, push, live site

**Harden:** confirm `WEBSITE_REPO` in `.env`; regenerate bot token if ever shared.

See [roadmap.md](roadmap.md) for Phase 2+ (vision, fine-tunes, more agents).

---

## License

Private / personal project. Adjust as needed when you publish.
