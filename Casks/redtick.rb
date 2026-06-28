cask "redtick" do
  version "1.7.4"
  sha256 "84ab157131657fd3b673d3083cd8af22e44ee5a1ca58031036bfa68b8388783e"

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
