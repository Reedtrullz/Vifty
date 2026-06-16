cask "vifty" do
  version "1.1.0"
  sha256 "5b3d6c67acfb7833e71edeb250d238b7c8c362285189e118278fc5bd350cd884"

  disable! date: "2026-06-16", because: "requires a Developer ID signed and notarized release"

  url "https://github.com/Reedtrullz/Vifty/releases/download/v#{version}/Vifty-v#{version}.zip"
  name "Vifty"
  desc "Menu-bar fan control and power monitor for MacBook Pro"
  homepage "https://github.com/Reedtrullz/Vifty"

  depends_on macos: :sequoia

  app "Vifty.app"

  caveats <<~EOS
    Vifty uses a privileged XPC helper (LaunchDaemon) for fan SMC writes.
    On first launch, the app will prompt you to install the helper —
    you may need to approve it in System Settings > Login Items & Extensions.

    The bundled viftyctl agent CLI is at:
      #{appdir}/Vifty.app/Contents/MacOS/viftyctl

    To uninstall the privileged helper alongside the app:
      sudo launchctl bootout system /Library/LaunchDaemons/tech.reidar.vifty.daemon.plist
      sudo rm /Library/LaunchDaemons/tech.reidar.vifty.daemon.plist
      sudo rm /Library/PrivilegedHelperTools/tech.reidar.vifty.daemon
  EOS

  zap trash: "~/Library/Application Support/Vifty"
end
