app_name := "ParaDict"
bundle_id := "com.paradict.app"
dev_signing_id := env("DEV_CODESIGN_IDENTITY", "local-dev")
install_path := "/Applications/ParaDict.app"

default:
    @just --list --unsorted

# Kill existing, build, sign, install to /Applications, and launch
[group('dev')]
dev: kill package
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf "{{install_path}}"
    cp -R build/{{app_name}}.app "{{install_path}}"
    # Sign embedded frameworks
    for fw in "{{install_path}}"/Contents/Frameworks/*.framework; do
        [ -d "$fw" ] && codesign --force --sign "{{dev_signing_id}}" "$fw"
    done
    codesign --force --sign "{{dev_signing_id}}" \
        --entitlements build/ParaDict.entitlements \
        "{{install_path}}"
    rm -rf build/{{app_name}}.app
    open "{{install_path}}"

# Debug build
[group('build')]
build:
    swift build --disable-sandbox --product ParaDict

# Create .app bundle (debug)
[group('build')]
package:
    bash Scripts/build-app.sh debug

# Format Swift sources in place
[group('build')]
format:
    swift-format format --in-place --parallel --recursive Package.swift Sources Tests

# Lint Swift sources without modifying them
[group('build')]
lint:
    swift-format lint --strict --parallel --recursive Package.swift Sources Tests

# Run the test suite
[group('build')]
test:
    swift test --disable-sandbox

# Remove build artifacts
[group('build')]
clean:
    rm -rf .build build *.zip

# Kill running instance
[group('dev')]
kill:
    -pkill -f "{{app_name}}" 2>/dev/null || true

# Reset TCC permissions (use when permissions get stuck)
[group('dev')]
reset-tcc:
    sudo tccutil reset ListenEvent {{bundle_id}}
    sudo tccutil reset Accessibility {{bundle_id}}
    sudo tccutil reset Microphone {{bundle_id}}
    @echo "TCC permissions reset. Re-run 'just run' and grant permissions when prompted."

# Reset app UserDefaults
[group('dev')]
reset-settings:
    -killall "{{app_name}}" 2>/dev/null || true
    defaults delete {{bundle_id}} 2>/dev/null || true
    @echo "Settings reset. Restart the app to use defaults."
