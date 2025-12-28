cask "scroblebler" do
  version "0.1.0"
  sha256 "5df9080437a5ad140b4933a922211f9724cd2d9ecaf91089062d48c6ba72a5c2"

  url "https://github.com/tonioriol/scroblebler/releases/download/v#{version}/Scroblebler.#{version}.dmg"
  name "Scroblebler"
  desc "Last.fm scrobbler for macOS Music app"
  homepage "https://github.com/tonioriol/scroblebler"

  livecheck do
    url :homepage
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
