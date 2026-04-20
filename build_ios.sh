#!/usr/bin/env bash
# Local iOS build. Replicates .github/workflows/ios.yml on your Mac so
# you don't pay for the macos-15 runner. Run from repo root:
#
#   ./build_ios.sh           — build the xcodeproj (then archive in Xcode)
#   ./build_ios.sh --beta    — build + upload to TestFlight via fastlane
#
# Prereqs (one-time):
#   brew install godot scons
#   cd <repo>
#   bundle install            # pulls fastlane + xcodeproj gems
#   python3 -m pip install "torch==2.7.*" coremltools numpy
#   Xcode 26.x installed and `xcode-select -p` pointing at it
#
# If TestFlight upload is wanted, also set env vars ASC_KEY_ID,
# ASC_ISSUER_ID, ASC_PRIVATE_KEY (or ASC_PRIVATE_KEY_PATH),
# MATCH_GIT_URL, MATCH_PASSWORD, MATCH_KEYCHAIN_PASSWORD.

set -euo pipefail
cd "$(dirname "$0")"

RUN_BETA=0
for arg in "$@"; do
	case "$arg" in
		--beta) RUN_BETA=1 ;;
		*) echo "Unknown arg: $arg"; exit 2 ;;
	esac
done

echo "=== Phase 0: sanity ==="
command -v godot >/dev/null || { echo "godot not on PATH (brew install godot)"; exit 1; }
xcodebuild -version | head -1
godot --version || true

# --- 1. Build the GomokuNeural xcframework (Swift + Obj-C++) ---
echo ""
echo "=== Phase 1: plugin xcframework ==="
if [ ! -d ios_plugin/godot-cpp/include ]; then
	echo "Cloning godot-cpp (branch 4.5, first run only)…"
	git clone --depth=1 --branch=4.5 \
		https://github.com/godotengine/godot-cpp.git ios_plugin/godot-cpp
fi
(cd ios_plugin && ./build.sh)

echo ""
echo "=== Phase 2: stage plugin into addons/ ==="
cp -R ios_plugin/build/libgomoku_neural.ios.template_release.xcframework \
		addons/gomoku_neural/
cp -R ios_plugin/build/libgodot-cpp.ios.template_release.xcframework \
		addons/gomoku_neural/

# --- 3. Convert PyTorch → CoreML (for L6 CNN) ---
echo ""
echo "=== Phase 3: best_model.pt → GomokuNet.mlmodelc ==="
(cd ai_server && python3 export_coreml.py data/weights/best_model.pt \
		--filters 128 --blocks 6 \
		-o /tmp/GomokuNet.mlpackage)
xcrun coremlc compile /tmp/GomokuNet.mlpackage /tmp/
du -sh /tmp/GomokuNet.mlmodelc

# --- 4. Godot import + export ---
echo ""
echo "=== Phase 4: Godot import + iOS export ==="
godot --headless --import --quit || true
mkdir -p build/ios
godot --headless --export-release "iOS" build/ios/gomoku.ipa
ls -la build/ios/

# --- 5. Inject CoreML model + framework into the Godot-exported project ---
echo ""
echo "=== Phase 5: inject CoreML into xcodeproj ==="
bundle exec ruby ios_plugin/scripts/inject_coreml.rb \
		build/ios/gomoku.xcodeproj /tmp/GomokuNet.mlmodelc

echo ""
echo "✅ Build prep done. Xcode project: build/ios/gomoku.xcodeproj"
echo ""

if [ "$RUN_BETA" -eq 1 ]; then
	echo "=== Phase 6: fastlane beta (TestFlight upload) ==="
	bundle exec fastlane beta
else
	echo "Next steps:"
	echo "  (a) Install on device:  open build/ios/gomoku.xcodeproj"
	echo "      → pick your phone as target → ⌘R (or Product → Archive)"
	echo "  (b) TestFlight:         ./build_ios.sh --beta"
fi
