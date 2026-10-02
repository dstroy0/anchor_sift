#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Takes every instruction of a listing whose form the machine file lacks into it with its fields
# (interface_sass_probe_take.c). nvdisasm turns each taken form's bits over, the probe's own reading.
#
#     utils/test/src/c/transpiler/interface/interface_sass_take.sh <listing> [machine file] [architecture]
set -u

TOP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../.." && pwd)"
LISTING="${1:?a listing, as cuobjdump -sass or nvdisasm prints it}"
MACHINE="${2:-$TOP/src/c/transpiler/cubin/machines/sm_86}"
ARCH="${3:-SM86}"
TEST="$TOP/utils/test/src/c/transpiler/interface"
INTERFACE="$TOP/src/c/transpiler/interface"
OUT="$TOP/build/interface_sass_take"
mkdir -p "$OUT/decode"
type -P nvdisasm > /dev/null || { echo "  no nvdisasm on the PATH: the CUDA toolkit's disassembler names the fields"; exit 1; }

INCLUDES=(-I "$TOP/src/c/engine" -I "$TOP/src/cu/engine" -I "$INTERFACE" -I "$TOP/src/c/transpiler/cubin"
          -I "$TOP/src/c/types/file_defs/krs" -I "$TEST")
OBJECTS=()
for source in "$INTERFACE/interface.c" "$INTERFACE/interface_names.c" "$TOP/src/c/types/file_defs/krs/sass_machine.c" \
              "$TOP/src/c/transpiler/cubin/sass_assemble.c" "$TOP/src/c/types/file_defs/ksc/interface_sass_probe_class.c" \
              "$TEST/interface_sass_probe_machine.c" "$TEST/interface_sass_probe_read.c" \
              "$TEST/interface_sass_probe_take.c"; do
    object="$OUT/$(basename "$source" .c).o"
    cc -std=c11 -O2 -w "${INCLUDES[@]}" -c "$source" -o "$object" || exit 1
    OBJECTS+=("$object")
done
cc -o "$OUT/interface_sass_probe_take" "${OBJECTS[@]}" || exit 1
"$OUT/interface_sass_probe_take" "$LISTING" "$MACHINE" "$ARCH" "$OUT/decode"
