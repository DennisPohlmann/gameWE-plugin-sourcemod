# gameWE - SourceMod plugin: development

Building and releasing the plugin. The code layout and the rules for changes
are in [CLAUDE.md](../CLAUDE.md).

## Build

You need `spcomp` from SourceMod 1.12 or newer.

```bash
make build      # build/stage/addons/sourcemod/plugins/gamewe.smx
make package    # dist/gamewe-sourcemod-<version>.tar.gz and .zip, each with its .sha256
```

If `spcomp` is not in `PATH`, use `make SPCOMP=/path/to/spcomp`. To add another
include folder, use `SM_INCLUDE=/path/to/include`. The version comes from the git
tag (`v1.2.3`) or the `VERSION` file. Warnings are treated as errors.

The GitHub workflow `.github/workflows/build.yml` builds the plugin with
SourceMod 1.12 and 1.13 (the builds fixed as `SM_1_12` and `SM_1_13` in the
workflow; a newer build is a commit that changes them) for every push (any
branch), every pull request and when started by hand, and keeps the packages as a workflow artifact for 7
days; nothing is published without a release run.

## Releases

Releases are made by [semantic-release](https://semantic-release.gitbook.io/)
(`.releaserc.json`) in the same workflow; nobody tags by hand. Pushing to
`main` does not release: a release is started by hand on `main`, in GitHub
under Actions → build → Run workflow with `release` ticked, or with
`gh workflow run build.yml --ref main -f release=true`. Run the `release-security-gate` skill
first (see `CLAUDE.md`). The run builds and tests everything again; only
when that passed does semantic-release read the
[Conventional Commits](https://www.conventionalcommits.org/) since the last
tag and decide the next version:

| Commit | Release |
|---|---|
| `feat: ...` | minor (0.1.0 → 0.2.0) |
| `fix: ...` (also `fix(security): ...`), `perf: ...` | patch (0.1.0 → 0.1.1) |
| `feat!: ...`, `fix!: ...` or a `BREAKING CHANGE:` footer | major (0.1.0 → 1.0.0) |
| `docs`, `chore`, `ci`, `build`, `test`, `refactor`, `style` | no release |

For a release it writes `VERSION`, `GAMEWE_PLUGIN_VERSION` in
`gamewe.sp`/`gamewe_messages.sp` and `CHANGELOG.md`, commits them as
`chore(release): vX.Y.Z [skip ci]`, tags `vX.Y.Z` and creates the GitHub
release as a draft. The workflow then builds that tag with SourceMod 1.12,
uploads the packages (`.tar.gz`, `.zip`) and their own `.tar.gz.sha256` and
`.zip.sha256` to the release and makes it public. The release stays a draft until all files are in it, so it never shows up
incomplete; if a job fails, re-run the failed jobs of that run. Never edit the version files or `CHANGELOG.md` by hand.
