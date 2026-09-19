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
The normal weekly release workflow uses the exact checked-in pin for both
source releases and the release caused by a merged Stasis pin. It treats
`stasis.json` and `vendor/stasis` as shipped inputs, so a merged pin causes one
ordinary all-target release matrix. It never resolves a moving nightly or
mutates the checked-in vendor snapshot during that release.

The quarterly workflow is intentionally separate and cheap: on its stable
quarter-start schedule it resolves the newest complete immutable nightly,
refreshes `stasis.json` and `vendor/stasis`, performs only mechanical identity
and vendor-status checks, and creates or updates a dedicated pin PR. It never
builds desktop, Android, or Web artifacts and never pushes a dependency pin
directly to `master`. It leaves the dedicated pin PR for normal review and
merge; the next normal weekly release consumes the checked-in pin and is where
compatibility is discovered after that PR is merged.
