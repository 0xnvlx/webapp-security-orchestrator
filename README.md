# webapp-security-orchestrator

Clone it, build the image, run it — and you have a black-box **web-application pentesting
orchestrator**: a multi-agent system that drives offensive security skills at a target you're
authorized to test and hands back one severity-ranked report. It runs on two harnesses —
[Claude Code](https://www.anthropic.com/claude-code) or the local-LLM harness
[pi](https://github.com/earendil-works/pi) — and its methodology comes from the
[claude-red](https://github.com/SnailSploit/claude-red) skill library.

> ⚠️ **Authorized testing only.** This fires live attack traffic. Run it only against systems you own
> or have explicit written permission to test; unauthorized testing is illegal. No liability accepted.

## Quick start

```sh
git clone https://github.com/0xnvlx/webapp-security-orchestrator
cd webapp-security-orchestrator
docker build -t websec-orchestrator .

# run as your own uid so the reports in out/ come out owned by you
PUID=$(id -u); PGID=$(id -g)        # fish: set PUID (id -u); set PGID (id -g)
docker compose run -e PUID=$PUID -e PGID=$PGID orchestrator    # shell in the image
```

Then launch a harness inside the container:

```sh
claude                      # Claude Code — prompts for creds or key on first use

# or pi — point it at your LLM first, then launch:
nano pi/models.json         # set baseUrl, id, contextWindow
pi
```

(`docker compose` maps `host.docker.internal` so pi can reach an LLM server on your host.) Then just
describe the audit in plain English — Claude Code hands off to the `web-orchestrator` subagent, and
in pi you call `/websec`:

```
audit http://TARGET:PORT for SSRF, SQLi, and anything auth-related     # Claude Code
/websec audit http://TARGET:PORT for SSRF and XSS                      # pi
```

Name the vuln classes to scope the run, or say "audit everything" to sweep the `web`, `api`, and
`crypto` TLS classes — `auth` is added only when the app actually uses it.

Reports land in `out/<target-host>/`. `out/` is bind-mounted, so they also appear **on your host**,
in the `out/` of the directory you ran `docker compose` from. They are owned by you thanks to the
`PUID` in the quick start. Output is append-only and resumable. A finished class is skipped on re-run
unless you tell it to force one.

## What it covers

An **orchestrator** maps the requested classes to claude-red skills, runs one **tester** per class,
then a **reporter** merges the findings into a single ranked report. The standard run covers four
domains:

| Domain | Classes |
|---|---|
| `web` | xss, sqli, ssrf, idor, ssti, xxe, rce, graphql, deserialization, file-upload, open-redirect, parameter-pollution, race-condition, request-smuggling, waf-bypass, business-logic |
| `api` | api-abuse, api-security |
| `crypto` | tls-attacks — the TLS/certificate layer |
| `auth` | jwt, oauth — *added only if a detection pass finds the app uses them* |

(`crypto-attacks`, for CTF-style crypto, also ships as a skill but runs only when named explicitly —
its heavy tooling isn't in the image.)

Domains live in one `DOMAINS` setting in `setup.sh`, and the agents resolve classes by listing the
skill folders on disk — so skills claude-red adds are picked up with no edit. Reporting is vendored
(`reporting/SKILL.md`, adapted from claude-red's `offensive-reporting`), so no download is needed for it.

## Without Docker

```sh
./setup.sh --harness both     # or: claude | pi
./setup.sh test               # verify wiring — non-destructive, no network
```

`setup.sh` sparse-clones the claude-red skills into `~/claude-red` (override with `--red-dir`) and
renders the agent templates into the live harness config dirs. It needs `bash` + `git` and creates
symlinks, so run it on Linux/macOS, or Windows under WSL.

It installs the **skills**, not the **tools** they shell out to — those must be on `PATH` wherever
the harness runs. The Docker image bundles everything the standard run needs:

| Domain | Tools |
|---|---|
| web · api | curl, python3 |
| auth | jwt_tool, john (hashcat omitted due to size) |
| crypto tls | openssl, nmap, testssl.sh, sslyze, sslscan, tlsx, mitmproxy, certstream |
| crypto attacks | RsaCtfTool, SageMath, padbuster, hashpumpy, PyCryptodome — **not in the image** (named-only skill, >1 GB) |

## Local LLM backend (pi)

pi talks to any OpenAI-compatible endpoint (llama.cpp, vLLM, LM Studio, Ollama). Point `pi/models.json`
at it (`baseUrl`, `id`, `contextWindow`); `docker compose` maps `host.docker.internal` so pi can reach
a server on your host. Workers run serially by default — for parallel ones, raise `MAX_CONCURRENCY` in
`pi/extensions/subagent/index.ts`, give the backend 2+ slots, and set `contextWindow` to one slot's real
size. Claude Code has no backend to configure and runs its subagents concurrently.

## Credits

Offensive methodology: [claude-red](https://github.com/SnailSploit/claude-red) (MIT). This repo is the
orchestration layer around it.
