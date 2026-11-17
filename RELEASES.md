# Mac Sync Releases

<!-- markdownlint-disable MD013 -->

Mac Sync uses the same two-lane release contract as `container-compose`.

The GitHub/Homebrew process remains the direct-distribution path. App Store archives are separate, self-contained builds with a different bundle identifier, signing identity, provisioning profile and update mechanism. Follow the [App Store submission gates](docs/app-store-submission.md); do not publish an experimental archive as an approved Store release. Mac Sync's own code now offers AGPL-3.0-or-later OR MIT. Bundled third-party tools retain their licences and require separate distribution review.
Semantic releases are immutable and Current is a replaceable prerelease built
from the newest fully validated `main` commit.

## Published Lanes

| Lane | Git tag | Archive | Homebrew formula |
| --- | --- | --- | --- |
| Stable | `<major>.<minor>.<patch>` | `mac-sync-release-arm64.tar.gz` | `mac-sync` |
| Current | `current` | `mac-sync-current-<commit>-arm64.tar.gz` | `mac-sync-current` |

Stable releases become GitHub Latest. Current uses a commit-addressed asset so
the Homebrew formula remains installable while the mutable release is updated.
The formula version is `current.<workflow-run>.<commit>`.

Both lanes require successful CI and CodeQL runs for the exact commit. CI runs
the local `make ci` contract, including the 85% coverage floor and the Sonar
quality gate, plus the synthetic memory budget and separate ASan and TSan test
jobs. Release packaging then checks the checksum, archive paths,
executables, CLI smoke tests, app plist version/build values, icon, and
`build-info.json` provenance.

The workflow signs an archive with Developer ID when the repository secrets
`MAC_SYNC_DEVELOPER_ID_CERTIFICATE_P12` (a base64-encoded `.p12`) and
`MAC_SYNC_DEVELOPER_ID_CERTIFICATE_PASSWORD` are configured. Both certificate material and its password are required for a public release. If either is absent, the release fails rather than publishing an unsigned archive. The workflow validates the certificate authority.

New releases now require Developer ID signing, Apple notarisation acceptance, a stapled ticket and a successful Gatekeeper assessment. There is no unsigned or unnotarised release fallback. Existing historical releases are not retroactively notarised.

The hosted `release-signing` environment also requires the `APPLE_NOTARY_KEY_P8` App Store Connect team API-key secret and the non-secret `APPLE_NOTARY_KEY_ID` / `APPLE_NOTARY_ISSUER_ID` variables. The build imports a temporary owner-only key into its Keychain profile, then removes that file. Credentials never enter app files, release notes or build metadata. Users of the packaged app need no Apple credentials. Do not paste passwords or private keys into issues or chat.

For local packaging, first store credentials interactively with `xcrun notarytool store-credentials mac-sync-notary --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID`. The tool prompts for the app-specific password locally. Then use `make package-signed MAC_SYNC_CODESIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' MAC_SYNC_NOTARY_PROFILE=mac-sync-notary MAC_SYNC_REQUIRE_NOTARIZATION=1`. The helper waits for `Accepted`, staples, validates and assesses the actual bundle. A timeout or rejection stops packaging; inspect the submission ID with `notarytool info` or `notarytool log` before retrying.

To enable signing, export the Developer ID Application certificate and private
key from Keychain Access as a password-protected `.p12`. Store its base64 value
as the `DEVELOPER_ID_APPLICATION_P12_BASE64` repository secret and its export
password as `DEVELOPER_ID_APPLICATION_P12_PASSWORD`. The workflow imports the
certificate into an ephemeral runner Keychain and never writes either value to
the repository or release asset. The prior `MAC_SYNC_DEVELOPER_ID_...` and
`MAC_SYNC_DEVELOPER_ID_CERTIFICATE_...` secret names remain supported for
migration.

## Local Developer ID signing

The app bundle ID is `tools.xyzzy.mac-sync`. Direct-distribution signing uses a Developer ID Application certificate, not a provisioning profile. Sign in to Xcode with the maintainer's Apple Developer account and create or download the certificate. Its private key must be available in the login Keychain.

List available signing identities:

```sh
make signing-identities
```

Build a signed archive using the identity and optional Team ID from that output:

```sh
make package-signed \
  MAC_SYNC_CODESIGN_IDENTITY='Developer ID Application: Stephen Clarke (TEAMID)' \
  MAC_SYNC_CODESIGN_TEAM_ID='TEAMID'
```

`make package-release` remains available for local development without a certificate when notarisation is not requested. An explicitly requested signed/notarised build never falls back to ad hoc signing. Keep certificate material and passwords out of the repository.

## Current Build

A successful `main` CI run starts the release workflow automatically. It:

1. Ignores the run if a newer `main` commit exists.
2. Waits for exact-commit CI and CodeQL success.
3. Builds and validates a commit-addressed archive.
4. Stages the new assets on the existing Current release without moving its tag.
5. Updates, pushes, installs, and tests `mac-sync-current` in the Homebrew tap.
6. Moves only the reserved `current` tag and recreates the prerelease with a
   fresh publication time.
7. Removes assets from superseded releases while retaining their records and
   tags.

The staging order keeps the previously published Current formula installable
until its replacement has been uploaded.

## Stable Release

For 1.2.0, use the changes and compatibility notes in [CHANGELOG.md](CHANGELOG.md)
and [Architecture](docs/architecture.md). Include the resource-probe result and
the uncompleted multi-day soak limit in release notes. The standard release
gate is not a claim of long-term memory stability.

Prepare a release only from a clean, published `main` commit:

```sh
make ci
git fetch --all --prune --no-tags
git status --short --branch
git tag --no-sign 1.2.0
git push origin refs/tags/1.2.0
gh workflow run prebuilt-binaries.yml --ref main -f ref=1.2.0
```

Replace `1.2.0` with the intended semantic version. Never move or recreate a
published semantic tag. The workflow refuses to overwrite an existing stable
release or mismatched assets.

The stable workflow publishes the immutable release, updates the default
`mac-sync` formula, installs and tests it from
`stephenlclarke/homebrew-tap`, and then applies asset retention.

## Asset Retention

If publication stops after uploading a stable archive (for example during tap
verification), dispatch the same tag again from the repaired main workflow.
The workflow downloads the existing archive and checksum, validates their
original build/version/commit and signature, and resumes tap verification. It
does not rebuild, replace assets or move the semantic tag. Installation guidance
in release notes can be corrected without changing those immutable artefacts.

Homebrew requires explicit trust for the separately installed spinner formula:

```sh
brew trust --formula stephenlclarke/tap/mac-spinner
```

The workflow trusts only that dependency, not every formula in the tap.

Only these releases retain downloadable assets:

- `current`
- the GitHub Latest stable release

All other release records and Git tags remain visible for changelog and source
history. Their binary and checksum assets are deleted after every successful
publication. Source archives generated by GitHub from retained tags remain
available.

## Verification

After publication, verify the actual published heads and assets:

```sh
git fetch --all --prune --no-tags
git ls-remote origin refs/heads/main refs/tags/current refs/tags/1.1.0
gh release view current --json tagName,targetCommitish,isPrerelease,assets,url
gh release view 1.1.0 --json tagName,targetCommitish,assets,url
gh run list --workflow prebuilt-binaries.yml --limit 5
brew update
brew info stephenlclarke/tap/mac-sync
brew info stephenlclarke/tap/mac-sync-current
```

Each retained archive has a matching `.sha256` sidecar. The workflow also
compares the local archive digest with GitHub's published asset digest.

## Rollback

Do not move a semantic tag or rewrite `main`.

For a bad Current build, fix or revert the source on `main`; the resulting
successful CI run publishes a replacement Current build. Users can return to
stable with:

```sh
brew uninstall mac-sync-current
brew install mac-sync
```

For a stable regression, publish a new patch release and update the stable
formula through the release workflow. Existing release records remain as the
audit trail even after their superseded assets are pruned.
