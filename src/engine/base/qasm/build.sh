#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Sourced by run.sh and test/run.sh with TOP set. qasm_build <label> builds the qasm objects, the record machine's
# modules and the tessera daemon into $OUT; qasm_link <source> <name> then links one program there as $BINARY.

QASM="$TOP/src/engine/base/qasm"
SCRIPTURA="$TOP/src/engine/base/scriptura"
NO_ROUNDING="$TOP/src/engine/base/no_rounding"
CYCLE="$TOP/src/engine/base/cycle"
KEYMATH="$TOP/src/engine/base/keymath"
KEY_SCHEDULE="$TOP/src/engine/base/key_schedule"
OBSIGNATIO="$TOP/src/engine/base/obsignatio"
DAEMON_DIRECTORY="$TOP/src/engine/daemon"
INCLUDES=(-I "$TOP/src/engine" -I "$QASM" -I "$SCRIPTURA" -I "$NO_ROUNDING" -I "$CYCLE" -I "$KEYMATH"
          -I "$KEY_SCHEDULE" -I "$OBSIGNATIO" -I "$DAEMON_DIRECTORY")

qasm_host_setup()
{
    HOST_FLAGS=()
    LONG_PATHS=()
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            EXECUTABLE=.exe
            EXTENSION=obj
            MSVC_BIN="$(ls -d "/c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC"/*/bin/Hostx64/x64 2>/dev/null | tail -1)"
            if [ -z "$MSVC_BIN" ]; then
                MSVC_BIN="$(ls -d "/c/Program Files/Microsoft Visual Studio"/*/*/VC/Tools/MSVC/*/bin/Hostx64/x64 2>/dev/null | tail -1)"
            fi
            if [ -z "$MSVC_BIN" ]; then
                echo "  no host compiler nvcc accepts on this platform was found."
                return 1
            fi
            HOST_FLAGS=(-ccbin "$MSVC_BIN" -Xcompiler /Zc:preprocessor)
            LONG_PATHS=(-Xlinker /MANIFEST:EMBED -Xlinker "/MANIFESTINPUT:$(cygpath -m "$TOP/src/engine/long_paths.manifest")")
            DAEMON_LIBRARIES=(-lpdh)
            ;;
        *)
            EXECUTABLE=
            EXTENSION=o
            HOST_FLAGS=(-Xcompiler -fPIC)
            DAEMON_LIBRARIES=(-ldl -lpthread)
            ;;
    esac
    ARCHES="${QASM_ARCHES:-}"
    if [ -z "$ARCHES" ]; then
        CAP="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d ' .')"
        ARCHES="sm_${CAP:-86}"
    fi
    GENCODE=()
    for one in $ARCHES; do
        GENCODE+=(-gencode "arch=compute_${one#sm_},code=${one}")
    done
    return 0
}

qasm_c_object()
{
    local source="$1"
    local object="$2"
    rm -f "$object"
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            nvcc "${HOST_FLAGS[@]}" -Xcompiler "/std:c11 /O2" "${INCLUDES[@]}" -c "$source" -o "$object" ;;
        *)
            cc -std=c11 -O2 -fPIC "${INCLUDES[@]}" -c "$source" -o "$object" ;;
    esac
    [ -f "$object" ] || { echo "  build failed: $(basename "$source") did not compile"; return 1; }
}

qasm_cu_object()
{
    local source="$1"
    local object="$2"
    rm -f "$object"
    nvcc "${HOST_FLAGS[@]}" -std=c++17 -O2 "${GENCODE[@]}" "${INCLUDES[@]}" -c "$source" -o "$object"
    [ -f "$object" ] || { echo "  build failed: $(basename "$source") did not compile"; return 1; }
}

qasm_build()
{
    source "$TOP/maint/build_stamp.sh"
    build_stamp "$1"
    qasm_host_setup || return 1
    OBJECTS=()
    SCRIPTURA_OBJECTS=()
    local source
    local object
    for source in "$SCRIPTURA"/*.c "$NO_ROUNDING/exact_integer.c" "$CYCLE/cycle.c" "$QASM/qasm.c"; do
        object="$OUT/$(basename "$source" .c)_c.$EXTENSION"
        qasm_c_object "$source" "$object" || return 1
        OBJECTS+=("$object")
        case "$(basename "$source")" in
            scriptura*) SCRIPTURA_OBJECTS+=("$object") ;;
        esac
    done
    for source in "$QASM/qasm.cu" "$CYCLE/cycle.cu" "$KEYMATH/keymath.cu" "$KEY_SCHEDULE/key_schedule.cu"; do
        object="$OUT/$(basename "$source" .cu)_cu.$EXTENSION"
        qasm_cu_object "$source" "$object" || return 1
        OBJECTS+=("$object")
    done
    # a run on the device is a job on the device's tessera daemon: the client goes into the program, and the daemon
    # is built beside it, where the program starts it when none answers
    DAEMON_OBJECTS=()
    local name
    for name in tessera_client tessera_paths tessera_frame tessera_self tessera_ledger tessera_measure tessera_daemon; do
        object="$OUT/${name}_c.$EXTENSION"
        qasm_c_object "$DAEMON_DIRECTORY/$name.c" "$object" || return 1
        case "$name" in
            tessera_client) OBJECTS+=("$object") ;;
            tessera_paths|tessera_frame|tessera_self) OBJECTS+=("$object"); DAEMON_OBJECTS+=("$object") ;;
            *) DAEMON_OBJECTS+=("$object") ;;
        esac
    done
    SEAL_OBJECT="$OUT/obsignatio_cu.$EXTENSION"
    rm -f "$SEAL_OBJECT"
    nvcc "${HOST_FLAGS[@]}" -O2 "${GENCODE[@]}" "${INCLUDES[@]}" -c "$OBSIGNATIO/obsignatio.cu" -o "$SEAL_OBJECT"
    [ -f "$SEAL_OBJECT" ] || { echo "  build failed: obsignatio.cu did not compile"; return 1; }
    OBJECTS+=("$SEAL_OBJECT")
    DAEMON="$OUT/tessera_daemon$EXECUTABLE"
    rm -f "$DAEMON"
    nvcc "${HOST_FLAGS[@]}" "${GENCODE[@]}" "${LONG_PATHS[@]}" -o "$DAEMON" "${DAEMON_OBJECTS[@]}" \
        "${SCRIPTURA_OBJECTS[@]}" "$SEAL_OBJECT" "${DAEMON_LIBRARIES[@]}"
    [ -f "$DAEMON" ] || { echo "  build failed: the tessera daemon did not link"; return 1; }
    return 0
}

qasm_link()
{
    local source="$1"
    local name="$2"
    BINARY="$OUT/$name$EXECUTABLE"
    rm -f "$BINARY"
    nvcc "${HOST_FLAGS[@]}" -std=c++17 -O2 "${GENCODE[@]}" "${INCLUDES[@]}" "${LONG_PATHS[@]}" -o "$BINARY" \
        "$source" "${OBJECTS[@]}"
    [ -f "$BINARY" ] || { echo "  build failed: $name did not link"; return 1; }
    return 0
}
