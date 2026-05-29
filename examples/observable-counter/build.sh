#!/usr/bin/env bash
#
# Build the observable-counter example end-to-end.
#
# 1. Publish wirelet-runtime + wirelet-observable-runtime + plugin to mavenLocal.
# 2. Cross-compile libObservableCounterJNI.so for aarch64-unknown-linux-android28.
# 3. Stage the .so + Swift Android runtime + libc++_shared.so into jniLibs.
# 4. assembleDebug.
#
# Inputs: none. Outputs: APK at app/build/outputs/apk/debug/app-debug.apk.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SDK_ID="swift-6.3.2-RELEASE_android"
SDK_BUNDLE="$HOME/Library/org.swift.swiftpm/swift-sdks/${SDK_ID}.artifactbundle"
SDK_LIB="$SDK_BUNDLE/swift-android/swift-resources/usr/lib/swift-aarch64/android"
ANDROID_TRIPLE="aarch64-unknown-linux-android28"
SWIFT_PKG="$HERE/swift"
ANDROID_APP="$HERE/android-app"
JNI_DEST="$ANDROID_APP/app/src/main/jniLibs/arm64-v8a"
ANDROID_NDK_ROOT="${ANDROID_NDK_ROOT:-$HOME/Library/Android/sdk/ndk}"

echo "=== publishToMavenLocal ==="
"$ROOT/kotlin/gradlew" \
  -p "$ROOT/kotlin" \
  -PwireletVersion=0.0.1-local \
  :runtime:publishToMavenLocal \
  :observable-runtime:publishToMavenLocal \
  :gradle-plugin:publishToMavenLocal

echo "=== cross-compile Swift -> $ANDROID_TRIPLE ==="
swift build \
  --package-path "$SWIFT_PKG" \
  --swift-sdk "$ANDROID_TRIPLE" \
  -c release

echo "=== stage jniLibs ==="
rm -rf "$JNI_DEST"
mkdir -p "$JNI_DEST"
cp "$SWIFT_PKG/.build/$ANDROID_TRIPLE/release/libObservableCounterJNI.so" "$JNI_DEST/"
cp "$SDK_LIB"/lib*.so "$JNI_DEST/"
# libc++_shared.so ships in the host's Android NDK install (the Swift
# Android artifact bundle's ndk-sysroot does not include it).
LIBCXX="$(find "$ANDROID_NDK_ROOT" -path '*aarch64-linux-android/libc++_shared.so' 2>/dev/null | head -1)"
if [ -z "$LIBCXX" ]; then
  echo "FATAL: libc++_shared.so not found under $ANDROID_NDK_ROOT" >&2
  echo "Install the Android NDK from Android Studio's SDK Manager." >&2
  exit 1
fi
cp "$LIBCXX" "$JNI_DEST/"
echo "Staged $(ls "$JNI_DEST" | wc -l | tr -d ' ') .so files."

echo "=== assembleDebug ==="
( cd "$ANDROID_APP" && ./gradlew :app:assembleDebug )

echo
echo "SUCCESS. APK at:"
echo "  $ANDROID_APP/app/build/outputs/apk/debug/app-debug.apk"
