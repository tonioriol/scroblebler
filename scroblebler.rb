cask "scroblebler" do
  version "1.2.1"
  sha256 "776a25b5b9c35216c84faf106c87a3dac98ba21d05aebb80fe33d005285f90f8"

  url "https://github.com/tonioriol/scroblebler/releases/download/v#{version}/Scroblebler.1.0.2.dmg"
  name "Scroblebler"
  desc "Last.fm scrobbler for macOS Music app"
  homepage "https://github.com/tonioriol/scroblebler"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "Scroblebler.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-cr", "#{appdir}/Scroblebler.app"],
                   sudo: false
  end

  zap trash: [
    "~/Library/Preferences/com.tonioriol.Scroblebler.plist",
    "~/Library/Application Support/Scroblebler",
  ]
end
