class MacSync < Formula
  desc "Curated Mac dotfile, package, secret, and repository snapshot sync tool"
  homepage "https://github.com/stephenlclarke/mac-sync"
  url "https://github.com/stephenlclarke/mac-sync/releases/download/homebrew-main/mac-sync-main-release-arm64.tar.gz"
  version "release-bootstrap"
  sha256 :no_check
  license "AGPL-3.0-or-later"

  depends_on "age"
  depends_on arch: :arm64
  depends_on "gnu-tar"
  depends_on macos: :ventura

  def install
    payload = if (buildpath/"mac-sync/bin").directory?
      buildpath/"mac-sync/bin"
    else
      buildpath
    end

    bin.install payload/"mac-sync"
    bin.install payload/"mac-spinner"
  end

  def caveats
    <<~EOS
      This formula installs the main lane prebuilt package asset:
        mac-sync-main-release-arm64.tar.gz

      mac-sync expects the sync configuration repo and machine snapshot repo to
      be available locally. Run:
        mac-sync --help

      Manage scheduled sync with:
        brew services start mac-sync
        brew services restart mac-sync
        brew services stop mac-sync
    EOS
  end

  service do
    run [opt_bin/"mac-sync", "run"]
    run_type :interval
    interval 3600
    working_dir var
    log_path var/"log/mac-sync.log"
    error_log_path var/"log/mac-sync.log"
  end

  test do
    assert_match "Usage:", shell_output("#{bin}/mac-sync --help")
    assert_match "brew smoke", shell_output("#{bin}/mac-spinner --message 'brew smoke' --pending")
  end
end
