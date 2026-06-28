class MacSync < Formula
  desc "Curated Mac dotfile, package, secret, and repository snapshot sync tool"
  homepage "https://github.com/stephenlclarke/mac-sync"
  url "https://github.com/stephenlclarke/mac-sync/releases/download/homebrew-main/mac-sync-main-release-arm64.tar.gz"
  version "release-bootstrap"
  sha256 :no_check
  license "AGPL-3.0-or-later"

  depends_on arch: :arm64
  depends_on macos: :ventura
  depends_on "age"
  depends_on "gnu-tar"

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
    EOS
  end

  test do
    assert_match "Usage:", shell_output("#{bin}/mac-sync --help")
    assert_match "brew smoke", shell_output("#{bin}/mac-spinner --message 'brew smoke' --pending")
  end
end
