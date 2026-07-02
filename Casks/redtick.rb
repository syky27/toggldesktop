cask "redtick" do
  version "1.11.0"
  sha256 "e85ffcf420738f2c25d2f8b409da3e7f52a8cd028cf5c8ba27d388b1b3d4032b"

  url "https://github.com/syky27/redtick/releases/download/v#{version}/redtick-v#{version}.dmg"
  name "Redtick"
  desc "Redmine-native time tracker (Toggl Desktop experience for Redmine)"
  homepage "https://github.com/syky27/redtick"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates false
  depends_on macos: :catalina
  depends_on arch: :arm64

  app "Redtick.app"

  zap trash: [
    "~/Library/Application Support/cz.syky.redtick.redtick",
    "~/Library/Caches/cz.syky.redtick.redtick",
    "~/Library/HTTPStorages/cz.syky.redtick.redtick",
    "~/Library/Preferences/cz.syky.redtick.redtick.plist",
    "~/Library/Saved Application State/cz.syky.redtick.redtick.savedState",
  ]
end
