# gameWE - SourceMod plugin: development

Building and releasing the plugin. The code layout and the rules for changes
are in [CLAUDE.md](../CLAUDE.md).

## Build

You need `spcomp` from SourceMod 1.12 or newer.

```bash
make build      # build/stage/addons/sourcemod/plugins/gamewe.smx
make package    # dist/gamewe-sourcemod-<version>.tar.gz, .zip and .sha256
```

If `spcomp` is not in `PATH`, use `make SPCOMP=/path/to/spcomp`. To add another
include folder, use `SM_INCLUDE=/path/to/include`. The version comes from the git
tag (`v1.2.3`) or the `VERSION` file. Warnings are treated as errors.

The GitHub workflow `.github/workflows/build.yml` builds the plugin with
SourceMod 1.12 and 1.13 for every push to `main` (or when started by hand) and
keeps the packages as a workflow artifact.

## Releases

Releases are made by [semantic-release](https://semantic-release.gitbook.io/)
(`.releaserc.json`) in the same workflow; nobody tags by hand. To make a
release, push commits written as [Conventional Commits](https://www.conventionalcommits.org/)
to `main`. semantic-release reads the commits since the last tag and decides
the next version:

| Commit | Release |
|---|---|
| `feat: ...` | minor (0.1.0 → 0.2.0) |
| `fix: ...` (also `fix(security): ...`), `perf: ...` | patch (0.1.0 → 0.1.1) |
| `feat!: ...`, `fix!: ...` or a `BREAKING CHANGE:` footer | major (0.1.0 → 1.0.0) |
| `docs`, `chore`, `ci`, `build`, `test`, `refactor`, `style` | no release |

For a release it writes `VERSION`, `GAMEWE_PLUGIN_VERSION` in
`gamewe.sp`/`gamewe_messages.sp` and `CHANGELOG.md`, commits them as
`chore(release): vX.Y.Z [skip ci]`, tags `vX.Y.Z` and creates the GitHub
release. The workflow then builds that tag with SourceMod 1.12 and uploads the
packages (`.tar.gz`, `.zip`, `.sha256`) to the release. Never edit the version
files or `CHANGELOG.md` by hand.
