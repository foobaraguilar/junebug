# Junebug Roadmap

**Telegram in → OpenClaw orchestrates → Ollama infers → you approve → deploy.**

Home Mac (Intel i7, CPU only). Start simple: one agent, one model, one Telegram reply. Build up.

---

## Simple rule

| Question | Answer |
|----------|--------|
| Building Junebug? | **Claude Code** |
| Junebug running on the Mac? | **OpenClaw + Ollama** |
| Editing site from Telegram? | **Website agent** (local model, Phase 2) |
| Need cloud intelligence later? | Optional API plug-in — **not v1** |

---

## Structural diagram (Home Mac)

Everything in the solid box runs on your Mac. Claude Code is **outside** — build time only.

**Setup-time** (occasional): pull models, fine-tune later. **Always-on**: gateway → agent → Ollama.

```
  Claude Code ·····  edits config.yaml, SOUL.md  (not in runtime loop)
         │
         │ git commit
         ▼

  SETUP-TIME (occasional)                    ALWAYS-ON (runtime)
  ─────────────────────                      ────────────────────
  Hugging Face ──pull──► Ollama              YOU ──► Telegram
  Colab/Kaggle ──train──►     │                    │
       (Phase 4+)             │                    ▼
                              │         ┌──────────────────────────┐
                              │    OS   │ OpenClaw Gateway         │
                              │   LAYER │ dispatches only —        │
                              │         │ does not reason          │
                              │         │ · routing                │
                              │         │ · pairing / allowlist    │
                              │         │ · access control         │
                              │         └───────────┬──────────────┘
                              │                     ▼
                              │              ┌─────────────┐
                              │         OS   │ main agent  │
                              │        LAYER │ SOUL.md     │
                              │              └──────┬──────┘
                              │                     ▼
                              └────────────► ┌─────────────┐
                                        BRAIN│ Ollama      │
                                             │ qwen2.5:3b  │
                                             └──────┬──────┘
                                                    │
                                                    ▼
                                             ┌─────────────┐
                                             │  Telegram   │
                                             │  reply      │
                                             └─────────────┘

  Phase 2+ only — before anything leaves the Mac:
       agent output ──► ⏸ Approval gate (you confirm in Telegram)
                              │
                              ▼
                    external action (git push · email send)
```

### Gateway: routing, pairing, access control

All three are **gateway-layer** jobs — the agent never decides who's allowed in.

| Job | What it does in Junebug |
|-----|-------------------------|
| **Routing** | Telegram message in → match or create agent session → reply back on same channel |
| **Pairing** | Unknown senders must be approved before the gateway accepts their messages |
| **Access control** | `bind: loopback` (no public port), `dmPolicy: allowlist`, your chat ID in `.env` |

Configured in `openclaw/config.yaml` → generated into `openclaw/runtime/openclaw.json`.

### Key design choices

| Choice | Why |
|--------|-----|
| **Gateway = OS layer** | Routes, pairs, and access-controls — dispatches only, does not reason |
| **Model = brain** | Ollama infers; one model per agent when you scale up |
| **Claude Code is narrow + offline** | Writes config and personas. Never in the live Telegram loop. Never holds email/git credentials. |
| **CPU-only latency** | 3B models: ~2–15 s/reply. Don't run two 7B models concurrently — cores compete. Test one agent before adding a second. |
| **Confirmation before external action** | Phase 2+: propose diff → you approve → commit/push. No blind deploys. |

---

## Dev time vs runtime

```
┌─────────────────────────────────────────────────────────┐
│  DEV TIME — Claude Code + you                           │
│  · openclaw/config.yaml                                 │
│  · agents/main/SOUL.md                                  │
│  · scripts/, .env.example                               │
│  · re-run ./scripts/setup-openclaw.sh after config edits │
└─────────────────────────────────────────────────────────┘
                          │ git commit
                          ▼
┌─────────────────────────────────────────────────────────┐
│  RUNTIME — Home Mac (no Claude)                         │
│  Telegram → OpenClaw → agent → Ollama → reply           │
│  (Phase 2+: → propose → approve → git)                  │
└─────────────────────────────────────────────────────────┘
```

---

## Where Claude Code helps most

| Area | Claude Code? | Notes |
|------|--------------|-------|
| `openclaw/config.yaml`, `agents/*/SOUL.md`, `scripts/` | ✅ | Primary job |
| Website repo `CLAUDE.md` | ✅ | Phase 2 site conventions |
| Live Telegram bot | ❌ | OpenClaw + Ollama |
| Git push / deploy at runtime | ❌ | Agent + your approval |
| Running `ollama` or gateway | ❌ | You run scripts in terminal |

---

## Config files — which governs what

| File | Governs |
|------|---------|
| `openclaw/config.yaml` | Which agents exist, models, routing (Claude Code edits this) |
| `agents/*/SOUL.md` | Agent personality and rules |
| `.env` | Secrets (git-ignored); merged on setup |
| `openclaw/runtime/openclaw.json` | Generated — do not edit by hand |

All persona/config files live in **git** so changes are diffable and revertable.

---

## What lives where

| Location | What |
|----------|------|
| **Home Mac** | OpenClaw gateway, agents, Ollama, Junebug repo, `~/.ollama/models/` |
| **Telegram cloud** | Chat transport only |
| **GitHub** | Website repo + Pages deploy |
| **Colab / Kaggle** | Fine-tuning jobs only (GPU); artifacts download to Mac |
| **Hugging Face** | Base model weights; adapter storage |
| **Claude Code** | Your laptop/Cursor — not on the Mac runtime loop |

| Job | Where |
|-----|-------|
| Inference | Mac via Ollama |
| Fine-tuning | Cloud GPU → import to Ollama on Mac |

---

## Main agent session (Phase 1)

| Piece | Location | Value |
|-------|----------|-------|
| Model | `openclaw/config.yaml` | `ollama/qwen2.5:3b` |
| Parameters | `openclaw/config.yaml` | `temperature: 0.3`, `max_tokens: 1024` |
| Persona | `agents/main/SOUL.md` | Talk-only, concise, honest about limits |
| Tools | `openclaw/config.yaml` | `profile: default` — no git/email yet |
| Skills | `agents/main/skills/` | Empty for v1 |

---

## Phased roadmap

### Phase 1 — Talk to it ← **you are here**

**Goal:** `main` agent replies in Telegram via local `qwen2.5:3b`. Nothing else.

| Step | Action |
|------|--------|
| 1 | `brew install ollama` → `ollama pull qwen2.5:3b` |
| 2 | `curl http://127.0.0.1:11434/api/tags` |
| 3 | `curl -fsSL https://openclaw.ai/install.sh \| bash` |
| 4 | `cp .env.example .env` — Telegram token, chat ID, gateway token |
| 5 | `./scripts/setup-openclaw.sh` |
| 6 | `./scripts/openclaw.sh gateway install --force --wrapper scripts/openclaw.sh` |
| 7 | `./scripts/openclaw.sh gateway start` |
| 8 | DM bot on Telegram — get a local reply |

**Done when:** bot replies without cloud APIs.

**Not in Phase 1:** website edits, photos, fine-tuning, second agent.

---

### Phase 2 — Website agent (text only)

**Goal:** one approved site edit goes live.

| Step | Action |
|------|--------|
| 9 | Confirm `~/Desktop/foobaraguilar.github.io` (or `WEBSITE_REPO`) |
| 10 | `@website change the hero tagline to "..."` |
| 11 | Agent shows diff → you approve → commit + push |

**Rollback:** `git revert` on the website repo if a bad edit ships.

**Not in Phase 2:** Telegram photos (text-only model), image publisher agent, email agent.

---

### Phase 3 — One model per agent

**Goal:** agents use separate Ollama model tags.

| Step | Action |
|------|--------|
| 12 | `ollama pull phi3:mini` (or second model) |
| 13 | Add agent block to `openclaw/config.yaml`, re-run setup |
| 14 | Test latency with **one** agent at a time, then both |

**Done when:** `main` and `website` can point at different models.

---

### Phase 4 — Fine-tune + vision (later)

| Item | Notes |
|------|-------|
| Fine-tune per agent | Colab/Kaggle — see below |
| Vision model | `llava` / `qwen2-vl` for Telegram images |
| More agents | Image publisher, email responder — deferred |
| Cloud API | Optional plug-in |

---

## Specializing without training (Phase 1–2)

| Method | What |
|--------|------|
| `SOUL.md` | Persona and rules |
| `openclaw/config.yaml` | Model choice per agent |
| Skills | OpenClaw shell workflows |
| `CLAUDE.md` | Website conventions (Phase 2) |

Pull `qwen2.5:3b`, add rules, infer. **Don't fine-tune until Phase 1 works and you know what's weak.**

---

## When you actually train / fine-tune

**Fine-tuning** = LoRA/QLoRA on a 3B base using your examples. Runs on **Colab/Kaggle GPU**, not the Mac.

### Free-ish compute

| Platform | Good for |
|----------|----------|
| **Google Colab** | LoRA experiments, time-limited GPU |
| **Kaggle** | ~30 GPU hrs/week |
| **Hugging Face** | Host adapters, model hub |

You train in PyTorch/Hugging Face on cloud GPU, then import to Ollama on the Mac.

### End-to-end flow (when you go beyond prompts)

```
1. BASE MODEL
   ollama pull qwen2.5:3b  (Mac, inference)

2. DATASET
   JSONL of prompt/response pairs (create when ready for Phase 4)

3. FINE-TUNE (Colab/Kaggle GPU)
   base + dataset → LoRA adapter

4. IMPORT (Mac)
   ollama create website-custom -f Modelfile

5. POINT AGENT
   openclaw/config.yaml → agent model → ollama/website-custom
```

**Train in cloud → download artifact → infer on Mac.**

### Practical order

1. Phase 1 live — use the bot, note failures
2. Collect prompt/response examples (JSONL)
3. Fine-tune **one** agent's model first
4. Import to Ollama, update config, test alone before adding a second model

---

## Current status

| Component | Status |
|-----------|--------|
| MVP scaffold | ✅ |
| Phase 1 — Telegram + Ollama | ⬜ run steps |
| Website agent (Phase 2) | ⬜ stub |
| Per-agent models (Phase 3) | ⬜ |
| Fine-tuned models (Phase 4) | ⬜ |

---

## One-line summary

**Claude Code builds config. OpenClaw orchestrates on the Mac. Each agent gets its own Ollama model when ready. Colab/Kaggle fine-tunes; Mac infers. You approve before anything leaves.**
