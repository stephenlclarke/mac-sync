# App Store submission

Status: engineering preparation, not an approved or upload-ready App Store release. The GitHub/Homebrew edition remains available. Never upload an unsigned archive or call Developer ID signing App Store signing.

## Release gates

- [ ] Review the exact bundled dependency licences against App Store terms. Mac Sync's own code offers MIT or AGPL, but Git, rsync and GNU tar retain GPL terms. Notices and source archives alone do not establish App Store compatibility. Resolve this before submission; obtain suitable permissions or replace incompatible dependencies if required.
- [ ] Register `io.quux.mac-sync` in the authorised Apple Developer team and App Store Connect. Confirm the final name, SKU, category, regions, price and age rating in App Store Connect. Do not accept agreements on behalf of the owner without approval.
- [ ] Obtain Apple Distribution application and installer signing identities and the matching Mac App Store provisioning profile. Developer ID/notarisation credentials are a separate channel.
- [ ] Run full tests, ASan, TSan, CodeQL, runtime audit and generated-data sandbox tests at the final commit. Validate minimum supported macOS and current macOS; a host running macOS 27 is not proof of macOS 13 compatibility.
- [ ] Test user-granted external folders, bookmark renewal, background-agent approval/disable/relaunch, HTTPS/SSH authentication, offline retry, recovery and channel migration on a clean account.
- [ ] Review the privacy report against the exact executables and SDKs. Host [PRIVACY.md](../PRIVACY.md) at a stable public URL and enter it in App Store Connect. Review provider-dependent user-content disclosures rather than assuming “no data collected” covers every destination and optional service.
- [ ] Capture final screenshots, support URL, release notes and review notes. Give reviewers a generated-data walkthrough that does not require real personal files. Explain folder consent and optional background registration.
- [ ] Export with Apple Distribution, inspect the exported installer/app and its profile, then validate through Xcode/App Store Connect. Actual upload, submission and review approval are distinct steps.

## Build and audit

Development requirements: Xcode, XcodeGen 2.46.0 or later, Python 3.12 or later and the Go version in `Tools/runtime/sources.json`. Users of the Store edition do not need these tools or Homebrew.

```sh
make store-runtime
make store-archive
make store-audit
make store-smoke
```

`store-smoke` uses only generated files in the isolated test application's container. External-folder access needs a separate, explicit consent test. Create an empty `mac-sync-store-access.*` folder under `/private/tmp`, obtain the user's approval for that exact folder, then run `make store-smoke-external MAC_SYNC_TEST_FOLDER=/private/tmp/mac-sync-store-access.SUFFIX`. The test rejects any other selected path. The first process saves a test-only bookmark; the second process starts without a folder dialogue and restores it. Both exercise repeated sync, encryption, archive access and missing-grant snapshot preservation. Cleanup must finish while access is still active. The second run removes the saved test bookmark and both runs leave the approved folder empty. Do not add this consent step to unattended CI or use real user folders.

The archive is `.build/MacSyncStore.xcarchive`. The generated `MacSyncStore.xcodeproj` is not committed. Open it in Xcode to select your team and configure signing/provisioning, or set `MAC_SYNC_STORE_TEAM` and run `make store-signed-archive`. `Store/ExportOptions.plist` selects `app-store-connect` export, not upload. `MAC_SYNC_STORE_TEAM=YOUR_TEAM_ID make store-export` needs a signed archive and the appropriate distribution assets already available to Xcode. It is not a conversion of Developer ID signing into Store signing. Inspect the exported app with:

```sh
python3 Tools/runtime/audit_runtime.py /absolute/path/to/exported/MacSync.app --distribution
```

The audit rejects missing tools/notices, externally linked libraries, wrong deployment targets, unexpected code, missing sandbox inheritance, inconsistent teams and non-App-Store signatures. Apple's validation remains authoritative; the local audit is not a substitute.

Use `pkgutil --check-signature` on the exported `.pkg` as well. It must have the matching Mac App Store installer distribution signature, not a Developer ID installer or an ad hoc signature.

## Privacy declarations

The Store manifest declares no tracking or analytics collection by quux.io. File metadata is used for container/user-selected files; preferences are app-local; elapsed time supports timers and deadlines; available disk space protects writes. Review the linked third-party runtimes for any additional uses before submission. See Apple's [required-reason API reference](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype) and [privacy manifest guidance](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).

## Background service

The bundled `io.quux.mac-sync.background.plist` runs the same signed app with `--background-agent`. It does not launch a second UI. It restores this edition's folder grants and runs the existing single observer/short-lived worker. `SMAppService` controls registration; macOS retains approval and disable controls. See Apple's [service documentation](https://developer.apple.com/documentation/servicemanagement/smappservice) and [embedded command-line tool requirements](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app).
