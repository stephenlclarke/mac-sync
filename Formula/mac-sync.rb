class MacSync < Formula
  desc "Curated Mac dotfile, package, secret, and repository snapshot sync tool"
  homepage "https://github.com/stephenlclarke/mac-sync"
  url "https://github.com/stephenlclarke/mac-sync/releases/download/homebrew-main/mac-sync-main-release-arm64.tar.gz"
  version "main-release-47eb709500a1"
  sha256 "b08b49cd179f4ecf9db755f61ce350d7e600676720dfd35c5d80c58b415c184e"
  license "AGPL-3.0-or-later"

  depends_on "age"
  depends_on arch: :arm64
  depends_on "git"
  depends_on "gnu-tar"
  depends_on macos: :ventura
  depends_on "rsync"

  def install
    package_root = if (buildpath/"mac-sync").directory?
      buildpath/"mac-sync"
    else
      buildpath
    end

    payload = if (package_root/"bin").directory?
      package_root/"bin"
    else
      package_root
    end

    bin.install payload/"mac-sync"
    bin.install payload/"mac-spinner"
    prefix.install package_root/"MacSync.app"
  end

  def caveats
    <<~EOS
      This formula installs the main lane prebuilt package asset:
        mac-sync-main-release-arm64.tar.gz

      The Mac Sync app is installed into this formula's prefix. Launch it with:
        open "$(brew --prefix mac-sync)/MacSync.app"

      Homebrew also installs Mac Sync's required command-line dependencies:
      age, GNU tar, Git, and rsync. Apple-provided macOS tools cover Keychain
      access and the remaining POSIX utilities.

      On first launch, Mac Sync guides you to choose an existing mac-sync-data
      checkout or create one. It saves only that path for the CLI/service; Git
      credentials remain in SSH or Keychain. The legacy dot-files checkout is
      not used by this version.
      The CLI remains available as:
        mac-sync --help

      For a custom app-managed schedule, use Settings → Automatic sync.
      Stop the Homebrew service first so only one automatic sync job runs.

      The Homebrew service remains an hourly alternative:
        brew services start mac-sync
        brew services restart mac-sync
        brew services stop mac-sync
    EOS
  end

  service do
    run [opt_bin/"mac-sync", "run"]
    run_type :interval
    interval 3600
    environment_variables PATH: std_service_path_env
    working_dir var
    log_path var/"log/mac-sync.log"
    error_log_path var/"log/mac-sync.log"
  end

  test do
    assert_match "USAGE:", shell_output("#{bin}/mac-sync --help")
    assert_match "brew smoke", shell_output("#{bin}/mac-spinner --message 'brew smoke' --pending")
    assert_predicate formula_opt_bin("age")/"age", :executable?
    assert_predicate formula_opt_bin("age")/"age-keygen", :executable?
    assert_predicate formula_opt_bin("git")/"git", :executable?
    assert_predicate formula_opt_bin("gnu-tar")/"gtar", :executable?
    assert_predicate formula_opt_bin("rsync")/"rsync", :executable?
    assert_equal(
      "#{HOMEBREW_PREFIX}/bin:#{HOMEBREW_PREFIX}/sbin:/usr/bin:/bin:/usr/sbin:/sbin",
      service.to_hash.fetch(:environment_variables).fetch(:PATH),
    )
    assert_predicate prefix/"MacSync.app/Contents/MacOS/MacSync", :executable?
    assert_path_exists prefix/"MacSync.app/Contents/Resources/MacSync.icns"
  end
end
