---
name: release-security-gate
description: Full security pass over the gameWE SourceMod plugin before release-relevant commits are pushed to main (semantic-release then bumps, tags and releases). Use whenever a release is being prepared; ends with a go/no-go report and never tags or pushes on its own.
---

# Release security gate (gameWE SourceMod plugin)

Run all steps over the whole repository, not only the last diff. Report a
table with the 20 points (ok / finding / n.a.) and a go/no-go.

Releases are made by semantic-release in CI: every push to `main` that
contains a `feat`, `fix` or breaking-change commit (Conventional Commits)
bumps the version, writes `CHANGELOG.md`, tags `vX.Y.Z` and publishes the
GitHub release (and, where there is one, the container image). So this gate
runs **before pushing release-relevant commits to `main`**, without asking
first. Never tag by hand, never edit the version files or `CHANGELOG.md` by
hand, and do not push to `main` yourself: report the gate result and the
version semantic-release will make (`feat` → minor, `fix` → patch,
`!`/`BREAKING CHANGE` → major), then ask Dennis for the go.

## Steps

1. **Clean tree and version:** `git status` is clean; `VERSION`,
   `GAMEWE_PLUGIN_VERSION` and the top `CHANGELOG.md` entry agree with the
   latest tag (`git describe --tags --abbrev=0`).
2. **Build:** `make build` with SourceMod 1.12 and, if available, 1.13;
   no warnings.
3. **Secrets in the whole history:** prefer
   `gitleaks detect --source . --log-opts="--all"`; otherwise
   `git log -p --all | grep -nEi '(rcon_password|password|secret|token)\s*[:= ]'`.
4. **Command inventory:**
   `grep -n 'Reg\(Server\|Console\|Admin\)Cmd\|AddCommandListener' addons/sourcemod/scripting/*.sp`
   - every collector command is `RegServerCmd`, every console command is
   harmless or admin-gated.
5. **Injection review:** every `ServerCommand(` and every `LogToGame(` with
   a `%s` that can carry player or collector text; confirm escaping.
6. **Buffers:** `grep -n 'GetCmdArg\|Format(\|strcopy(' ...` for changes
   since the last tag (`git diff $(git describe --tags --abbrev=0) -- addons`), sizes match the
   buffers.
7. **Format strings:** no player, chat, cvar or collector text is ever the
   format argument of `Format`, `LogToGame`, `PrintToChat`, `PrintToServer`,
   `ReplyToCommand`, `ServerCommand`, `LogMessage` etc. (always
   `Format(buf, size, "%s", text)`):
   `grep -nE '(Format|LogToGame|PrintTo\w+|ReplyToCommand|ServerCommand|LogMessage)\([^"]*,\s*[a-z_]+\)' addons/sourcemod/scripting/*.sp`
   and review every hit.
8. **Workflow:** `.github/workflows/build.yml` builds `main` and publishes
   only via semantic-release (no tag trigger); actions are pinned and the
   SourceMod download is checked.
9. **Test on a server** if one is available: hostile player name, chat
   flood of `rank`, `gamewe_browse <id> javascript:...`, user id of a
   player who left.
10. **The 20 points:** go through the `security-check` skill's list for the
   whole plugin, with extra attention on changes since the last tag.
11. **Report:** go/no-go, findings with file:line and fix, the version semantic-release will make, then ask Dennis
    for the go to push to `main`.
