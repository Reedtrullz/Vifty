cask "vifty" do
  version "1.3.2"
  sha256 "8bbc48b7db7bbe342a6c053a58aa655c969d9b803794f981a4cd8e7d3514bcc0"

  url "https://github.com/Reedtrullz/Vifty/releases/download/v#{version}/Vifty-v#{version}.zip"
  name "Vifty"
  desc "Menu-bar fan control and power monitor for MacBook Pro"
  homepage "https://github.com/Reedtrullz/Vifty"

  depends_on macos: :sequoia
  depends_on arch: :arm64

  app "Vifty.app"

  uninstall script: {
    executable: "#{appdir}/Vifty.app/Contents/Resources/uninstall-vifty.sh",
    args:       ["--app", "#{appdir}/Vifty.app"],
    sudo:       false,
  }

  caveats <<~EOS
    Vifty uses a privileged XPC helper (LaunchDaemon) for fan SMC writes.
    On first launch, the app will prompt you to install the helper —
    you may need to approve it in System Settings > Login Items & Extensions.

    The bundled viftyctl agent CLI is at:
      #{appdir}/Vifty.app/Contents/MacOS/viftyctl

    Homebrew invokes Vifty's bundled safe-uninstall preflight before removing
    the app. Helper teardown remains blocked unless Vifty can prove every fan
    is back under Auto/System ownership with a valid maintenance token.
  EOS

  zap trash: "~/Library/Application Support/Vifty"
end
