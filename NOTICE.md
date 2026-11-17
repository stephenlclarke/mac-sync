# mac-sync - Notices and Attributions

Copyright © 2026 quux.io.

Mac Sync code owned by quux.io is available under AGPL-3.0-or-later OR MIT, at your choice. See [licensing](LICENSE.md), `LICENSE` and `LICENSE-MIT.md`. Third-party materials retain their own licences; this permission does not relicense any dependency or submodule.

## Data-loss disclaimer

Mac Sync can copy, replace, overwrite and delete files. Software defects, incorrect settings, interrupted operations, storage-provider failures or lost encryption keys can cause loss, corruption or loss of access to data and files. Use this application at your own risk. Do not rely on Mac Sync as your only backup. Keep an independent, verified backup and check recovery before using it with important data.

To the fullest extent permitted by applicable law, Stephen Clarke and the contributors are not responsible or liable for loss, corruption, overwriting or deletion of data or files, loss of access to encrypted backups, or resulting loss or damage arising from the use of, or inability to use, this application. The application is supplied without warranties or guarantees of data integrity, successful backup, cloud upload or recovery.

This notice supplements the warranty and liability provisions of the selected [licence](LICENSE.md). It does not change the licence or limit rights or liabilities that applicable law does not allow to be excluded or limited.

## Third-Party Materials

The direct edition uses separately installed tools, including Git, rsync, age and GNU tar. Homebrew manages those dependencies. Optional developer integrations also use Homebrew and VS Code's `code` CLI.

The App Store build recipe bundles pinned, unmodified Git, rsync, age and GNU tar executables. Their licences are separate from Mac Sync's licence. Packages include their notices, Go dependency notices and corresponding-source materials in `MacSync.app/Contents/Resources/Runtime`. See [runtime provenance and build instructions](Tools/runtime/README.md). Apple supplies system frameworks and libraries; these are not redistributed. App Store submission requires a separate review of third-party distribution terms.
