#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Every ruleset read against its code generator's schema, and sass.krs's forms checked against the machine code the
# cell's probes read back (ruleset_read_test.cpp). The code generator is host code in .cu files, compiled as C++, and
# needs no CUDA toolchain and no device
set -u

TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$TEST/../../../../../.." && pwd)"
CODEGEN="$TOP/src/c/transpiler/codegen"
CODEGEN_CU="$TOP/src/cu/transpiler/codegen"
CODEGEN_CU_2="$TOP/src/cu/types/file_defs/krs"
source "$TOP/utils/maint/engine/build_stamp.sh"
build_stamp ruleset_read_test

INCLUDES=(-I "$TOP/src/c/engine" -I "$TOP/src/cu/engine" -I "$CODEGEN" -I "$CODEGEN_CU" -I "$CODEGEN_CU_2")
BINARY="$OUT/ruleset_read_test"
rm -f "$BINARY"
OBJECTS=()
for source in "$CODEGEN_CU"/*.cu "$CODEGEN_CU_2"/*.cu "$TEST/ruleset_read_test.cpp"; do
    case "$(basename "$source")" in
        asm_printer_*.cu|codegen*.cu) continue ;;
    esac
    object="$OUT/$(basename "$source")_rr.o"
    rm -f "$object"
    c++ -std=c++17 -O2 -Wall -Wextra "${INCLUDES[@]}" -x c++ -c "$source" -o "$object"
    [ -f "$object" ] || { echo "  build failed: $(basename "$source") did not compile"; exit 1; }
    OBJECTS+=("$object")
done
c++ -o "$BINARY" "${OBJECTS[@]}"
[ -f "$BINARY" ] || { echo "  build failed: the test did not link"; exit 1; }

"$BINARY"
STATUS=$?
echo "  ruleset read test exit $STATUS"
exit "$STATUS"
