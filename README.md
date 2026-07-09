# Junebug

![Junebug system diagram — Telegram → Main Agent → Agent 1 (website) → approval gate → deploy](assets/junebug-diagram.png)

*Junebug — persistent system on OpenClaw (gateway, sessions, tools, skills).*

Local-first agent harness for a home Mac. **Telegram in → OpenClaw routes → Ollama infers → you approve → deploy.**

The **Main Agent** reads every message and either handles it or delegates to a specialist. **Agent 1** (Personal Website Dev) edits your GitHub Pages site on request. Everything runs on your machine (CPU-only via Ollama). No cloud inference required for v1.

**Roadmap:** [roadmap.md](roadmap.md)

---

## Architecture

The diagram above is the full target layout. **What’s live today is simpler** — see [One model today](#one-model-today) below.

| Piece | Role |
|-------|------|
| **Telegram** | Shared interface + approval channel (DM in, confirm before push) |
| **OpenClaw gateway** | Routing, pairing, allowlist, loopback bind — dispatches only, does not reason |
| **Main Agent** | Entry point; chat; decides handle vs delegate |
| **Agent 1 — Website** | Specialist for site edits (and eventually Telegram photos); proposes diff → you approve → push |
| **Agent N** *(dashed in diagram)* | Future specialists (e.g. inbox heartbeat) — not built yet |
| **Approval gate** | Nothing leaves the Mac (git push, email send) without explicit Telegram confirmation |
| **Ollama** | Local inference on `127.0.0.1:11434` |
| **Claude Code** | Dev-time only — edits this repo’s config and personas; not in the runtime loop |

**Path 1 (now):** `ollama pull qwen2.5:3b` — direct download, no GPU. One weight file on disk at `~/.ollama/models/`.

**Path 2 (later):** dataset → Colab/Kaggle LoRA fine-tune → `ollama create` adapter on the Mac — for per-agent specialization when it’s worth it.

---

## One model today

> **There is only one local model right now** — a single `qwen2.5:3b` instance served by Ollama. Both the Main Agent and Agent 1 (website) point at `ollama/qwen2.5:3b` in config. They are two agent identities (workspace, tools, `SOUL.md`), not two separate brains on disk.

This is intentional for **CPU load**: on an Intel Mac without a GPU, running two full model instances would roughly double RAM and CPU contention for no current benefit. Ollama loads the weights once; each request is serialized through the same endpoint.

| Config entry | Model tag | Physical reality |
|--------------|-----------|------------------|
| `main` | `ollama/qwen2.5:3b` | Shared |
| `website` (Agent 1) | `ollama/qwen2.5:3b` | Same file, same Ollama process |

The diagram’s separate “Local model” and “Local model A” boxes describe the **target** architecture (each specialist eventually getting its own base or fine-tuned model). That split is Phase 3+ in [roadmap.md](roadmap.md) — only when Agent 1 is doing meaningfully different work or you have a fine-tune you want isolated.

---

## Agents

Both agents share **one** `qwen2.5:3b` model today (see [One model today](#one-model-today)).

| Agent | Workspace | Model (today) | Reach it via |
|-------|-----------|---------------|--------------|
| `main` | `agents/main/` | `ollama/qwen2.5:3b` (shared) | DM the bot (default) |
| `website` (Agent 1) | `agents/website/` | `ollama/qwen2.5:3b` (shared) | `@website change the hero tagline to …` or ask main to delegate |

Website flow: **propose diff → you approve in Telegram → commit + push → GitHub Pages auto-deploys**.

---

## Repo structure

```
junebug/
├── assets/
│   └── junebug-diagram.png   # architecture diagram (README)
├── .env.example              # secrets template (copy to .env)
├── openclaw/
│   └── config.yaml           # agents, models, gateway, access — edit this
├── agents/
│   ├── main/                 # OpenClaw workspace (SOUL.md, USER.md, …)
│   └── website/              # site-edit agent workspace
├── scripts/
│   ├── setup-openclaw.sh     # config.yaml + .env → openclaw/runtime/openclaw.json
│   └── openclaw.sh           # always use this wrapper, not bare `openclaw`
└── roadmap.md
```

Generated at runtime (gitignored): `openclaw/runtime/` — config JSON, sessions, LaunchAgent env.

---

## Prerequisites

- macOS (tested on Intel Mac, CPU-only)
- [Homebrew](https://brew.sh)
- [Ollama](https://ollama.com) + `qwen2.5:3b`
- [OpenClaw](https://openclaw.ai) CLI (`openclaw` on `PATH`)
- A Telegram bot token ([@BotFather](https://t.me/BotFather))
- Your personal site repo cloned locally (default: `~/Desktop/foobaraguilar.github.io`)

---

## Quick start

```bash
git clone <your-repo-url> ~/junebug
cd ~/junebug

# 1. Ollama
brew install ollama
brew services start ollama
ollama pull qwen2.5:3b

# 2. OpenClaw (if not installed)
curl -fsSL https://openclaw.ai/install.sh | bash

# 3. Secrets
cp .env.example .env
# Fill in: TELEGRAM_BOT_TOKEN, TELEGRAM_NOTIFY_CHAT_ID, OPENCLAW_GATEWAY_TOKEN

# 4. Generate runtime config
./scripts/setup-openclaw.sh
./scripts/openclaw.sh config validate

# 5. Start gateway
./scripts/openclaw.sh gateway install --force --wrapper scripts/openclaw.sh
./scripts/openclaw.sh gateway start
./scripts/openclaw.sh gateway status
```

**Important:** Always run OpenClaw through `./scripts/openclaw.sh` so state stays in `openclaw/runtime/`.

### Get your Telegram chat ID

1. Message your bot (e.g. `hi`).
2. Open `https://api.telegram.org/bot<TOKEN>/getUpdates` and find `"chat":{"id":…}`.
3. Set `TELEGRAM_NOTIFY_CHAT_ID` in `.env`, then re-run `./scripts/setup-openclaw.sh` and restart the gateway.

### If LaunchAgent won't stay up

On some setups the macOS LaunchAgent exits immediately (launchd exit 126). The gateway still works in the foreground:

```bash
./scripts/openclaw.sh gateway --port 18790
```

Run that in a dedicated terminal or tmux session until launchd is fixed.

---

## Configuration

| File | Purpose |
|------|---------|
| `openclaw/config.yaml` | Agent list, models, delegation, gateway port, access policy |
| `.env` | Bot token, chat ID, gateway token, `WEBSITE_REPO` |
| `agents/*/SOUL.md` | Agent persona and operating rules (injected each session) |
| `agents/main/{USER,IDENTITY,AGENTS,TOOLS}.md` | Operator profile, identity card, ops manual, local notes |

After any change to `config.yaml` or `.env`:

```bash
./scripts/setup-openclaw.sh
./scripts/openclaw.sh gateway restart   # or foreground start
```

Identity in config (`openclaw.json`): main agent is **Junebug** 🪲; both agents use `ollama/qwen2.5:3b` (one shared model). Main tools profile `minimal`; website (Agent 1) uses `coding`.

---

## Usage

```text
# General chat
hi

# Direct website edit
@website change the hero tagline to "Building things on the home Mac"

# Via main (delegates to website)
update my site hero to say "Hello world"
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
| Ollama + `qwen2.5:3b` (single shared model) | Ready |
| OpenClaw config generation | Working |
| Telegram + allowlist | Configured (chat ID in `.env`) |
| Gateway LaunchAgent | Known issue — use foreground start if needed |
| Agent workspace files | Partially filled — see [Next steps](#next-steps) |

---

## Next steps

### 1. Finish agent workspace (high priority)

OpenClaw injects workspace files every session. Several are still stock placeholders in `agents/main/`:

| File | Action |
|------|--------|
| `USER.md` | Describe you — name, timezone, how you like to be helped |
| `IDENTITY.md` | Match config: Junebug, 🪲, local delegator vibe |
| `SOUL.md` | Persona: direct, honest, small model — don't fabricate, admit uncertainty |
| `AGENTS.md` | Trim OpenClaw defaults; move delegation rules here from `SOUL.md` |
| `TOOLS.md` | Ollama URL, website repo path, Telegram notes |
| `HEARTBEAT.md` | Leave empty unless you want proactive check-ins |

### 2. End-to-end test

- [ ] Gateway running (`./scripts/openclaw.sh gateway status` or foreground)
- [ ] DM bot — get a reply from main
- [ ] `@website` — propose a small copy change on the site repo
- [ ] Approve → verify commit + push + live site

### 3. Fix persistent gateway (optional)

- Debug LaunchAgent exit 126 (permissions on `openclaw/runtime/service-env/`, or run from a path outside `~/Desktop`)
- Or add a `tmux`/`launchd` wrapper script you control

### 4. Harden for daily use

- [ ] Revoke/regenerate Telegram bot token if ever shared
- [ ] Confirm `WEBSITE_REPO` in `.env` points at your real site clone
- [ ] Git-init `agents/main/` workspace if you want agent memory backed up (private repo)

### 5. Phase 2+ (from roadmap)

- Reliable website delegation under `qwen2.5:3b` (may need prompt tuning or a slightly larger model)
- More specialist agents (email, calendar, etc.)
- Optional cloud model fallback for hard tasks

---

## License

Private / personal project. Adjust as needed when you publish.
