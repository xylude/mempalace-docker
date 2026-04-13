# mempalace-docker

Docker setup for running [MemPalace](https://github.com/mempalace/mempalace) as a persistent MCP server accessible to Claude Code (and any other MCP client).

MemPalace is a long-term memory system for Claude. It mines your past Claude conversations, builds a knowledge graph and semantic search index, and exposes it all over MCP so Claude can query its own memory across sessions, machines, and projects.

---

## Requirements

- Docker + Docker Compose
- **RAM:** 4 GB minimum, 6 GB+ recommended. MemPalace loads ChromaDB embeddings into memory — a large palace can be hungry.
- **Disk:** Varies by palace size. Budget ~1–2 GB for a typical install plus your conversation data.
- An exported Claude conversation archive to mine (see [Mining](#mining-your-conversations))

---

## Quick Start

**1. Clone and configure**

```bash
git clone https://github.com/your-org/mempalace-docker
cd mempalace-docker
cp .env.example .env
```

Edit `.env` and set `IMPORT_PATH` to the folder where your Claude conversation exports live. If you don't have exports yet, leave it as-is and create a local `imports/` folder — you can populate it later.

**2. Build and start**

```bash
docker compose up -d --build
```

**3. Initialize the palace**

On first run, initialize the storage:

```bash
docker compose exec mempalace mempalace init /root/.mempalace
```

**4. Mine your conversations**

```bash
docker compose exec mempalace mempalace mine /mnt/imports --mode convos
```

This indexes your conversation exports into the palace. Re-run it whenever you add new exports.

---

## Configuration

All configuration lives in `.env` (copy from `.env.example`):

| Variable | Default | Description |
|---|---|---|
| `PORT` | `8000` | Host port to expose the MCP server on |
| `IMPORT_PATH` | `./imports` | Host path to mount as the import folder |
| `MEM_LIMIT` | `6g` | Docker memory limit for the container |

---

## Connecting to Claude Code

Once the container is running, add it as an MCP server. Use your machine's LAN IP (not `localhost` if Claude Code runs on a different machine or in a different network namespace).

**streamableHttp (default):**

```bash
claude mcp add mempalace --transport http http://<your-ip>:8000/mcp --scope user
```

**SSE (if you switched the Dockerfile CMD to the SSE variant):**

```bash
claude mcp add mempalace --transport sse http://<your-ip>:8000/sse --scope user
```

`--scope user` makes the server available globally across all Claude Code sessions and projects, permanently. This is what you want.

---

## Auto-approve MCP Permissions

By default Claude Code will prompt you to approve each tool call. To allow all MemPalace tools silently, add this to `~/.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "mcp__mempalace__mempalace_add_drawer",
      "mcp__mempalace__mempalace_check_duplicate",
      "mcp__mempalace__mempalace_delete_drawer",
      "mcp__mempalace__mempalace_diary_read",
      "mcp__mempalace__mempalace_diary_write",
      "mcp__mempalace__mempalace_find_tunnels",
      "mcp__mempalace__mempalace_get_aaak_spec",
      "mcp__mempalace__mempalace_get_taxonomy",
      "mcp__mempalace__mempalace_graph_stats",
      "mcp__mempalace__mempalace_kg_add",
      "mcp__mempalace__mempalace_kg_invalidate",
      "mcp__mempalace__mempalace_kg_query",
      "mcp__mempalace__mempalace_kg_stats",
      "mcp__mempalace__mempalace_kg_timeline",
      "mcp__mempalace__mempalace_list_rooms",
      "mcp__mempalace__mempalace_list_wings",
      "mcp__mempalace__mempalace_search",
      "mcp__mempalace__mempalace_status",
      "mcp__mempalace__mempalace_traverse"
    ]
  }
}
```

---

## CLAUDE.md Prompt Template

To get Claude to actually use the palace consistently, add a memory protocol to your `~/.claude/CLAUDE.md`. This tells Claude to query the palace at the start of every session and write a diary entry at the end:

```markdown
## MemPalace Memory Protocol

MemPalace is a persistent memory system accessible via MCP tools (`mcp__mempalace__*`).

### On Every Session Start

Call `mempalace_status` to load the palace overview, then `mempalace_search` or
`mempalace_kg_query` to load context relevant to the current task.

### Before Responding About Past Work, People, or Decisions

Always query the palace first. Never guess — verify.
- Use `mempalace_search` for open-ended or semantic lookups
- Use `mempalace_kg_query` for structured facts (people, projects, decisions)
- Use `mempalace_kg_timeline` to understand how a fact evolved over time

### What to Save

Save early, save often. Things worth saving:
- Architectural decisions and the reasoning behind them
- Bugs found and how they were resolved
- Project goals, constraints, and non-obvious context
- Anything the user explicitly asks you to remember
- What was tried and didn't work (negative results are valuable)

Use `mempalace_kg_add` for structured facts, `mempalace_diary_write` for session summaries.

### After Each Session

Call `mempalace_diary_write` to record what we worked on, decisions made, and open questions.

### When Facts Change

Call `mempalace_kg_invalidate` on the old fact before writing the new one with `mempalace_kg_add`.
Do NOT call `kg_add` to "update" — always invalidate first or conflicting facts will stack.

### mempalace_kg_add Formatting Rules

The KG is strict about input format. Violating these causes silent errors or stacked duplicates:

- **subject/object**: plain text only — no apostrophes, slashes, or special path characters
  - use `Alice OBrien` not `Alice O'Brien`
  - use `home/jason/project` not `/home/jason/project` (leading slash breaks it)
- **predicate**: snake_case — spaces are auto-converted but be consistent
- **dates**: always `YYYY-MM-DD`, zero-padded — `2026-04-01` not `2026-4-1`
- **valid_from**: optional but recommended — omitting it means "always true"
- **duplicate check**: exact match only — conflicting facts won't error, they'll silently stack
```

---

## macOS / OrbStack / Docker Desktop Notes

On macOS, you can't bind directly to your LAN IP from inside Docker the way you can on Linux. A few options:

- **OrbStack**: Use the container's OrbStack DNS name instead of a LAN IP. The host machine can reach it but other machines on the network cannot without extra forwarding.
- **Docker Desktop**: Use `host.docker.internal` to reach the host, but for _inbound_ access from other machines you'll need port forwarding configured at the Docker Desktop level.
- For a single-machine setup (Claude Code and MemPalace on the same Mac), `http://localhost:8000` works fine regardless of Docker flavor.

---

## Upgrading

To pick up a new version of MemPalace:

```bash
docker compose down
docker compose up -d --build --no-cache
```

The palace data lives in the `mempalace-data` Docker volume and is preserved across rebuilds.

---

## Troubleshooting

**Container OOMs or gets killed** — Increase `MEM_LIMIT` in `.env`. Start with `6g`, go up from there.

**`chromadb` install fails during build** — The Dockerfile pins `chromadb==0.6.3` which is known-good. If you're hitting this with a custom image, don't let pip resolve chromadb on its own — pin it before installing mempalace.

**`mine` command finds no conversations** — Make sure your export folder is correctly set in `IMPORT_PATH` and that the files are Claude conversation exports (JSON). The volume mounts it at `/mnt/imports` inside the container.

**MCP tools not showing up in Claude Code** — Run `claude mcp list` to verify the server is registered. Check that the container is actually running (`docker compose ps`) and reachable from the machine running Claude Code.
