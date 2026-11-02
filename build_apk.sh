#!/bin/bash
set -e

# ==============================================================================
# Badminton Hawk-Eye Pro - Automated Android APK Build Script
# ==============================================================================

echo "================================================================="
echo "   BADMINTON HAWK-EYE PRO: AUTOMATED ANDROID APK BUILD SCRIPT    "
echo "================================================================="

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

OUTPUT_DIR="$PROJECT_DIR/build_output"
mkdir -p "$OUTPUT_DIR"

# 1. Check Flutter SDK
if ! command -v flutter &> /dev/null; then
    echo "[-] Flutter SDK not found in PATH."
    echo "[*] If you want to build locally on your machine, please install Flutter:"
    echo "    https://docs.flutter.dev/get-started/install"
    echo ""
    echo "[*] TIP: You can also push this project to GitHub! The included GitHub Actions"
    echo "    workflow (.github/workflows/build_apk.yml) will automatically compile"
    echo "    and produce the downloadable APK file in 3 minutes without installing anything!"
    exit 1
fi

echo "[+] Flutter detected: $(flutter --version | head -n 1)"

# 2. Check Android SDK
if [ -z "$ANDROID_HOME" ] && [ -z "$ANDROID_SDK_ROOT" ]; then
    echo "[!] Warning: ANDROID_HOME or ANDROID_SDK_ROOT is not set."
    echo "    Flutter will attempt to discover Android SDK automatically."
fi

# 3. Clean and Fetch Dependencies
echo "[+] Fetching Flutter packages..."
flutter pub get

# 4. Compile APK
echo "[+] Compiling Release APK (ARM64 & x86_64)..."
flutter build apk --release --split-per-abi || flutter build apk --release

# 5. Locate and Copy Output APK
APK_SOURCE="build/app/outputs/flutter-apk"
if [ -d "$APK_SOURCE" ]; then
    echo "[+] Copying generated APK(s) to $OUTPUT_DIR..."
    cp -v "$APK_SOURCE"/*.apk "$OUTPUT_DIR/" || true
    echo "================================================================="
    echo "[SUCCESS] Build completed! Your APK file(s) are ready in:"
    echo "          $OUTPUT_DIR"
    echo "================================================================="
    ls -lh "$OUTPUT_DIR"
else
    echo "[-] Error: APK build directory not found."
    exit 1
fi
