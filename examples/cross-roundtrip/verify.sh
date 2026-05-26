#!/usr/bin/env bash
#
# End-to-end roundtrip:
#   1. Publish wirelet-runtime to mavenLocal (so the JVM decoder can resolve it).
#   2. Run emit-wirelet-kotlin against shared-schema/ to generate MessageCodec.kt.
#   3. Build & run the Swift encoder, which writes Message bytes to a temp file.
#   4. Build & run the JVM decoder, which reads the same bytes and prints them.
#
# Expected final output line: `id=42 text=hello tags=[a, b]`

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIRELET_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$SCRIPT_DIR"

# 1. Make sure wirelet-runtime is in maven local.
echo "[1/4] Publishing wirelet-runtime to mavenLocal..."
"$WIRELET_ROOT/kotlin/gradlew" -p "$WIRELET_ROOT/kotlin" \
    :runtime:publishToMavenLocal \
    -PwireletVersion=0.0.1-local \
    --quiet

# 2. Generate Kotlin codecs from the shared schema.
echo "[2/4] Generating Kotlin codecs..."
GEN_DIR="$SCRIPT_DIR/jvm-decoder/build/generated/wirelet"
mkdir -p "$GEN_DIR"
( cd "$WIRELET_ROOT" && swift run emit-wirelet-kotlin \
    --config "$SCRIPT_DIR/kotlin-codegen.json" \
    --source "$SCRIPT_DIR/shared-schema/Sources/SharedSchema" \
    --output "$GEN_DIR" )

# 3. Build & run the Swift encoder.
BYTES_FILE="$(mktemp -t wirelet-roundtrip-XXXXXX.bin)"
trap 'rm -f "$BYTES_FILE"' EXIT
echo "[3/4] Running Swift encoder..."
( cd "$SCRIPT_DIR/swift-encoder" && swift run swift-encoder "$BYTES_FILE" )

# 4. Build & run the JVM decoder.
echo "[4/4] Running JVM decoder..."
( cd "$SCRIPT_DIR/jvm-decoder" && ./gradlew run --args="$BYTES_FILE" --quiet --console=plain )

echo
echo "Cross-language roundtrip succeeded."
