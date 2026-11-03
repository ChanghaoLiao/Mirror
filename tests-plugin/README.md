# Mirror plugin helper checks

Run on macOS 14+ with Apple Silicon:

```sh
bash tests-plugin/run.sh
```

These checks use macOS Bash, JavaScript for Automation and Python 3 for adapter/installer tests. They exercise the shipped helper's strict option whitelist, identifier encoding through native `NSURLComponents`, bounded app discovery, app metadata and executable checks, the minimum supported Mirror version (1.0.0), request semantics, privacy of output, platform checks, and real CLI exit codes. Test-only runtime doubles are passed by the test harness directly to internal JavaScript functions; the shipped CLI has no environment-variable command overrides or test flags.

The tests never open Mirror, read conversation data, install software, or change permissions. They do not certify conversation loading, Gatekeeper approval, or first-run setup. An actual app can be checked without launching it:

```sh
bash plugins/mirror/skills/mirror/scripts/mirror.sh status --app /absolute/path/Mirror.app
```

Without `--app`, the helper first checks running applications with the exact Mirror bundle identifier (at most 32 instances), resolves their bundle paths, and validates the selected bundle. One compatible running copy takes precedence over installed copies. Duplicate instances at the same resolved path are accepted; distinct running copies require explicit selection. A running incompatible app reports its validation error rather than silently launching another copy. When no Mirror copy is running, discovery checks only `/Applications/Mirror.app` and `~/Applications/Mirror.app`; two compatible distinct installations also require `--app`. No filesystem-wide search is performed, and result JSON omits app paths.

`open` returns a native receipt, not just a URL launch acknowledgement. Inspect loading and binding separately. Mutations require a fresh revision and are sent once; human actions and pause remain authoritative.

The function adapter tests additionally exercise all 15 operations, strict JSON, Unicode and shell-special text, native error preservation, bounded receipts, uncertain-timeout request IDs and a real isolated subprocess. They never call a model. The standalone archive is produced with `python3 scripts/package-agent.py`.

## Downloaded toolkit onboarding

After `python3 scripts/package-agent.py`, run `python3 tests-plugin/onboarding.test.py`. Tests extract the actual ZIP into a new isolated home with Chinese/spaces/apostrophes in its path. They install/reuse the companion skills, retain customized files and locks, reject links or incomplete packages, remove the original download to verify relocation, and export function schemas without site-packages. When a local Codex CLI exists, a clean-config App Server `skills/list` verifies real discovery without starting a chat or calling a model. The real disabled public installer branch must report `release_unavailable` without creating Applications. This is not a second physical Mac or a Gatekeeper certification.
