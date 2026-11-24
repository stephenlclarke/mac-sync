# Self-contained runtime

The App Store edition does not search Homebrew or download executables at runtime. Build the pinned tools with `make store-runtime`. Xcode command-line tools, Python 3.12 or later, and the Go version in `sources.json` are development requirements only. Native builds support Apple silicon; build on the target architecture.

Git, rsync, GNU tar and age are separate, unmodified upstream programs. Their licences are not changed by Mac Sync's MIT option. Each app includes notices, pinned source archives for the GPL programs, the build recipe and source checksums. The source and licence records must travel with the tools, including in historical packages. The source archive is bundled rather than relying on a mutable download URL or release-asset retention.

Git uses macOS's system libcurl and CommonCrypto. The build uses baseline libcurl headers to avoid compiling calls to newer curl APIs that are absent on supported older macOS versions. No old curl implementation is compiled or shipped. Only its public headers and licence are kept in the app's corresponding-source materials; macOS supplies the actual, OS-maintained network/TLS library. Git's Perl, Python, Tcl/Tk, gettext, PCRE and external OpenSSL dependencies are disabled. Runtime auditing rejects Homebrew-linked libraries and deployment targets newer than the app's advertised minimum.

The source pins do not replace ongoing security maintenance. Review upstream advisories, update hashes and Go module licences, rebuild and re-test before release. Validate redistribution and App Store terms for all third-party materials before submission. The MIT option covers quux.io's own code only.
