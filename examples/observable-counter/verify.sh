#!/usr/bin/env bash
#
# CI / local one-shot. Build the bits, then run the emulator smoke.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$HERE/build.sh"
"$HERE/run-emulator.sh"
