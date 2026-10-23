---
name: security-check
description: Security checklist for every change in the gameWE SourceMod plugin (SourcePawn, log lines for the collector, RCON server commands). Use before finishing, committing or opening a PR for any .sp, .inc, translation, build or workflow change.
---

# Security check for a change (gameWE SourceMod plugin)

Scope: the current diff (`git diff` plus staged and untracked files). Walk
the points below, only as deep as the diff reaches, and report the result.
Many points of the original web-app list do not apply to a game server
plugin; they are mapped to what does.

## Steps

1. Read the diff: `git status --short`, `git diff HEAD`.
2. List new or changed commands (`RegServerCmd`, `RegConsoleCmd`,
   `RegAdminCmd`, `AddCommandListener`), cvars, `LogToGame` formats and
   `ServerCommand` calls.
3. For each point below that the diff touches, check it in the code.
4. Build: `make build` (warnings are errors). If `spcomp` is missing, say so.
5. Quick secret grep on the diff:
   `git diff HEAD | grep -nEi '(rcon_password|password|secret|token)\s*[:= ]'`.
6. Fix what you find, then report: touched points, findings with
   file:line, what you fixed, what is left.

## The checklist, adapted to the plugin

1. **Secrets / keys:** no RCON passwords, server IPs of real servers or
   tokens in code, configs or docs.
2. **Least privilege:** new commands for the collector are
   `RegServerCmd`; player-facing commands need `RegAdminCmd` with the
   lowest fitting flag or must be harmless.
3. **IDOR:** a command with a user id acts only on that client after
   `GetClientOfUserId` + `IsClientInGame` (+ `!IsFakeClient` where needed);
   lists of ids (`1,2,3`) are each checked and bounded.
4. **Git secrets:** see step 5; build output (`build/`, `dist/`) stays ignored.
5. **Admin routes:** no admin-only action (swap, redirect, browse,
   logaddress changes) reachable from player chat or client console.
6. **User isolation:** private messages and menus go only to the target
   client; spectator/raw-message data of one player is not sent to others.
7. **Rate limits:** chat triggers that make the collector answer
   (`rank`, `top10`, `session`, ...) should have a per-client cooldown so a
   player cannot flood the collector and RCON.
8. **Storage:** files the plugin writes (configs, logs) use `BuildPath`
   with fixed names, never names from input.
9. **Input validation:** `GetCmdArg` into sized buffers, `StringToInt`
   results range-checked (time, team, menu handler), strings from the
   collector length-limited before `Format`.
10. **Unauthenticated entry points:** chat (`say`, `say_team`,
    `gamewe_block_commands`) is the only player input; it may only be
    matched against fixed triggers.
11. **Injection (SQL equivalent):** log injection and command injection.
    Player names in `LogToGame` only via `%L` (as the engine does); any
    other player text in a log line needs `"` removed; nothing from players or the collector reaches `ServerCommand`
    unescaped (`;`, `"`, newlines).
12. **Sensitive logs:** no IP addresses or SteamIDs beyond what the
    HLstats log format already carries; no RCON output in logs.
13. **Field tampering:** values from players never decide points, ranks or
    teams in the log lines (the collector computes them).
14. **Uploads:** not applicable.
15. **Server logic:** the collector, not the plugin, is the source of
    truth for stats; the plugin only reports events.
16. **Trim responses:** messages shown to players contain only their own or
    public stats.
17. **Auth sessions:** not applicable (RCON auth is the server's);
    `logaddress` protection (`ProtectLoggingChange`,
    `ProtectForwardingChange`) must keep working.
18. **Dependencies:** SourceMod version and includes: a change to the
    minimum version or to `.github/workflows/build.yml` (pinned actions,
    SourceMod download URL with checksum) gets a note.
19. **Record access:** natives in `gamewe.inc` for other plugins return
    only data for the asked client; query ids are checked before calling a
    callback.
20. **Attack your own change:** try one hostile input (name with `"`, `;`,
    newline, 128 chars; userid of a disconnected client; `gamewe_browse`
    with `javascript:`) and check the code path.
