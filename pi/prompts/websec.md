---
description: "Black-box web-app audit — you orchestrate web-app-tester workers (sequential by default) per vuln class, then the reporter consolidates. Usage: /websec target=<url> classes=<a,b|all> [parallel]"
---
Act as the **web-orchestrator** (role defined in `~/.pi/agent/agents/web-orchestrator.md`) for: $@

Do it yourself from this session — do not spawn a nested orchestrator:

1. Resolve the named vulnerability classes to claude-red skills under
   `__RED_SKILLS__/<domain>/offensive-<class>/SKILL.md`, across these domains:
   **web/** (xss, sqli, ssrf, idor, ssti, xxe, rce, graphql, deserialization, file-upload,
   open-redirect, parameter-pollution, race-condition, request-smuggling, waf-bypass,
   business-logic), **api/** (api-abuse, api-security), **auth/** (jwt, oauth), **crypto/**
   (tls-attacks; aliases `tls`/`ssl`). Validate with `ls __RED_SKILLS__/*/` and keep only the
   `offensive-*` folders that exist (which also picks up any skills claude-red has since added).
   If no classes are named (or `classes=all`), run every `web/` and `api/` class plus `crypto/`
   tls-attacks; the `auth/` classes (jwt, oauth) are conditional — run them only if explicitly
   named, or if a quick **web-app-tester** detection pass reports the app actually uses JWT / OAuth.
1b. Derive a per-target output dir `OUTDIR=__OUT_DIR__/<slug>` (`<slug>` = target host, scheme/path
   stripped, non `[A-Za-z0-9.-]` -> `-`); `mkdir -p "$OUTDIR"`. Set `RUNSTAMP=$(date -u +%Y%m%d-%H%M%S)`.
   Output is append-only and timestamped (`$OUTDIR/pi-<class>__$RUNSTAMP.md`). **Skip any class whose newest `$OUTDIR/pi-<class>__*.md` ends with**
   **`scan-status: complete`** (resume); a file lacking that marker is a partial run — re-run it. `force` re-runs regardless.
2. Run the **web-app-tester** agent via the **subagent** tool, one class per worker.
   **Default: sequential** — one worker at a time, wait for each to finish before the next
   (the local LLM backend typically has a single slot). Only if the request explicitly says
   *parallel* do you dispatch all resolved classes at once in one batch.
   Give each worker: `target`, the absolute `skill` path, `out=$OUTDIR/pi-<class>__$RUNSTAMP.md`,
   and the black-box rule (HTTP only; do not read the target's source; save big responses to
   a file and grep slices — never dump a whole page into context; stay on the in-scope host:port).
3. After all workers finish, use the **subagent** tool to run the **web-reporter** agent with
   `harness=pi dir=$OUTDIR` (it uses the vendored `__REPORTING_SKILL__` as its report methodology).
4. Return the reporter's summary and the path to `pi-report.md`.
