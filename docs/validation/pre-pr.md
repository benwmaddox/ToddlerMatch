# Local pre-PR validation

The required PR workflow is intentionally cheap: it checks the PR head against
the immutable Stasis identity in `stasis.json`, restores that exact release,
and runs vendor status, formatting, compilation, and vector-policy checks. It
does not package Web or install browsers on every push.

Before opening or updating a PR, run the broad validation once from the
repository root:

```powershell
pwsh ./tools/pre-pr-validation.ps1 -RestoreToolchain
```

The command uses the release in `stasis.json`; it never resolves `latest` for a
PR. If the exact toolchain is already available, omit `-RestoreToolchain` and
optionally pass `-StasisPath` to reuse it. It runs:

- `stasis vendor status`, `stasis fmt --check`, `stasis check`, and `stasis test`;
- the canonical vector-asset audit;
- a fresh Web package with required-file and SHA-256 checks; and
- the Maddox #652 Help and shuffle regression in both Chromium and Firefox.

Playwright `1.58.2` and its browsers are installed under the ignored
`.playwright-cli` directory by default. Use `-SkipBrowserInstall` only when
those exact browsers are already available there. Use `-NoSandbox` when the
local Chromium environment requires it.

Each run creates an ignored `output/pre-pr-validation/<run>/` directory with:

- `receipt.json`, containing `schema_version`, `status`, the current `head_sha`,
  the exact Stasis `release_id` and checksum, timestamp, check results, package
  hashes, and browser report paths; and
- `pr-body.md`, a concise summary that can be pasted into the PR description.

The receipt contract can be checked without downloading Stasis or browsers:

```powershell
pwsh ./tools/test-pre-pr-validation.ps1
```

The hosted equivalent of the full browser run is the manual
`Maddox #652 packaged browser acceptance` workflow. Dispatch it only when
hosted evidence is useful for a runtime or packaging change; it is not a
required pull-request check.

## Pinned versus newest Stasis

PR validation is reproducible and current-head: it uses the checked-in
`vendor.stasis.release_id` and `vendor.stasis.sha256` pair, so a source change
cannot silently switch compiler versions between pushes. Scheduled release
logic may resolve the newest complete Stasis nightly when it is deliberately
building a newer release. That newest-release lookup stays out of PR jobs,
avoiding an extra GitHub API call and preventing a moving toolchain from
repeating expensive validation on each commit.

After the quarterly cross-platform matrix succeeds, automation creates or
updates a dedicated PR containing the new `stasis.json` pin and `vendor/stasis`
snapshot. It never pushes a dependency pin directly to `master`; it explicitly
dispatches the cheap branch gate because a pull request created by the built-in
GitHub token does not emit a normal `pull_request` workflow event.
