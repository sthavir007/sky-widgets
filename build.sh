#!/bin/zsh
# Builds ~/Applications/Now Playing.app (Spotify helper + desktop widget) with Xcode, signed with
# the Apple Development certificate (team 89Y9A68Y5H). Edit project.yml, not the .xcodeproj.
set -e
cd "$(dirname "$0")"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate --quiet
xcodebuild -project NowPlaying.xcodeproj -scheme NowPlaying -configuration Release \
  -derivedDataPath .xcbuild -allowProvisioningUpdates -quiet build
APP=~/Applications/"Now Playing.app"
pkill -x "Now Playing" 2>/dev/null || true
rm -rf "$APP"
ditto ".xcbuild/Build/Products/Release/Now Playing.app" "$APP"
# drop the copy in the build folder so the widget gallery only knows the installed app
pluginkit -r ".xcbuild/Build/Products/Release/Now Playing.app/Contents/PlugIns/NowPlayingWidget.appex" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u ".xcbuild/Build/Products/Release/Now Playing.app" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
pluginkit -a "$APP/Contents/PlugIns/NowPlayingWidget.appex"
open "$APP" --args --background
echo "built $APP"
