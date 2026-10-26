#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
CEF="$ROOT/vendor/cef"
APP="$ROOT/build/mac/Aava.app"
mkdir -p build/mac "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
if [ ! -f "$CEF/include/cef_app.h" ]; then
  echo 'Run python3 scripts/fetch-cef.py first.' >&2
  exit 1
fi
cmake -S "$CEF" -B build/cef -DCMAKE_BUILD_TYPE=Release -DPROJECT_ARCH=arm64 -DUSE_SANDBOX=ON -DCMAKE_CXX_FLAGS=-DCEF_API_VERSION=15600
cmake --build build/cef --target libcef_dll_wrapper -j 6
WRAPPER="$ROOT/build/cef/libcef_dll_wrapper/libcef_dll_wrapper.a"
for SOURCE in ChromeHost Engine MiniEngine Main; do
  xcrun clang++ -std=c++20 -arch arm64 -mmacosx-version-min=14.0 -fobjc-arc -DCEF_USE_SANDBOX -DCEF_API_VERSION=15600 -I"$CEF" -IApps/macOS/Sources -c "Apps/macOS/Sources/$SOURCE.mm" -o "build/mac/$SOURCE.o"
done
swiftc -O -swift-version 5 -target arm64-apple-macos14.0 -parse-as-library \
  -import-objc-header Apps/macOS/Sources/Engine.h \
  Sources/AavaCore/*.swift Apps/macOS/Sources/MacStore.swift Apps/macOS/Sources/PrivateSpaceVault.swift Apps/macOS/Sources/PrivateSpaceViews.swift \
  Apps/macOS/Sources/Brand.swift Apps/macOS/Sources/AavaMaterials.swift Apps/macOS/Sources/AavaBackground.swift Apps/macOS/Sources/SpaceAppearanceEditor.swift Apps/macOS/Sources/AavaLibrary.swift Apps/macOS/Sources/AavaCommandBar.swift Apps/macOS/Sources/GitHubLiveFolder.swift Apps/macOS/Sources/SidebarAssets.swift Apps/macOS/Sources/PinnedTabs.swift Apps/macOS/Sources/AavaPanels.swift Apps/macOS/Sources/AavaNotifications.swift Apps/macOS/Sources/AavaSurfaces.swift Apps/macOS/Sources/OnboardingView.swift \
  Apps/macOS/Sources/ArcMigration.swift Apps/macOS/Sources/AavaDownloads.swift Apps/macOS/Sources/AavaLinkChoice.swift Apps/macOS/Sources/MiniControl.swift Apps/macOS/Sources/SpaceNavigationView.swift Apps/macOS/Sources/SidebarResizeHandle.swift Apps/macOS/Sources/BrowserView.swift Apps/macOS/Sources/DesktopApp.swift \
  build/mac/ChromeHost.o build/mac/Engine.o build/mac/MiniEngine.o build/mac/Main.o "$WRAPPER" \
  -framework Cocoa -framework IOSurface -Xlinker -lc++ \
  -o "$APP/Contents/MacOS/Aava"
xcrun clang++ -std=c++20 -arch arm64 -mmacosx-version-min=14.0 -DCEF_USE_SANDBOX -DCEF_API_VERSION=15600 -I"$CEF" \
  "$CEF/tests/cefsimple/process_helper_mac.cc" "$WRAPPER" \
  -framework Cocoa -framework IOSurface -o build/mac/AavaHelper
python3 scripts/package-mac.py
STAGED_APP="${TMPDIR:-/tmp}/aava-build-stage/Aava.app"
mkdir -p "$(dirname "$STAGED_APP")"
COPYFILE_DISABLE=1 ditto --norsrc "$APP" "$STAGED_APP"
python3 scripts/sign-mac.py "$STAGED_APP"
echo "Verified staging build: $STAGED_APP"
COPYFILE_DISABLE=1 ditto --norsrc "$STAGED_APP" "$APP"
# ditto can preserve destination Finder metadata even when resource copying is disabled.
for ATTRIBUTE in com.apple.FinderInfo com.apple.ResourceFork; do
  xattr -dr "$ATTRIBUTE" "$APP" >/dev/null 2>&1 || true
done
codesign --verify --deep --strict "$APP"
echo "Built: $APP"
