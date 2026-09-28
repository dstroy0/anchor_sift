#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Sourced by run.sh and test/engine/quantum/qasm/run.sh with TOP set. qasm_build <label> builds the qasm objects, the
# record machine's modules and the tessera daemon into $OUT; qasm_link <name> <source>... then links one program there
# as $BINARY.

QASM="$TOP/src/engine/quantum/qasm"
SCRIPTURA="$TOP/src/engine/runtime/scriptura"
NO_ROUNDING="$TOP/src/engine/arithmetic/no_rounding"
CYCLE="$TOP/src/engine/compiler/cycle"
CODEGEN="$TOP/src/engine/compiler/codegen"
KEYMATH="$TOP/src/engine/compiler/keymath"
KEY_SCHEDULE="$TOP/src/engine/compiler/key_schedule"
OBSIGNATIO="$TOP/src/engine/runtime/obsignatio"
DAEMON_DIRECTORY="$TOP/src/engine/runtime/daemon"
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
    for source in "$SCRIPTURA"/*.c "$NO_ROUNDING"/exact_integer_{add,limbs,multiply,divide,gcd,decimal,hash}.c \
                  "$CYCLE/cycle.c" "$QASM"/qasm_{exact,trig,lexer,expression,gates,statements,read}.c \
                  "$QASM"/qasm_field_{rational,number}.c "$QASM/qasm_dense.c" "$QASM"/qasm_chain_{matrix,apply}.c \
                  "$QASM"/qasm_symbolic_{polynomial,function}.c "$QASM"/qasm_lens_{hash,rank}.c; do
        object="$OUT/$(basename "$source" .c)_c.$EXTENSION"
        qasm_c_object "$source" "$object" || return 1
        OBJECTS+=("$object")
        case "$(basename "$source")" in
            scriptura*) SCRIPTURA_OBJECTS+=("$object") ;;
        esac
    done
    for source in "$QASM"/qasm_device_{program,kernels,run}.cu "$QASM"/qasm_self_{program,run}.cu "$CYCLE"/cycle*.cu \
                  "$CODEGEN"/*.cu "$KEYMATH/keymath.cu" "$KEY_SCHEDULE/key_schedule.cu"; do
        object="$OUT/$(basename "$source" .cu)_cu.$EXTENSION"
        qasm_cu_object "$source" "$object" || return 1
        OBJECTS+=("$object")
    done
    # a run on the device is a job on the device's tessera daemon: the client goes into the program, and the daemon
    # is built beside it, where the program starts it when none answers
    DAEMON_OBJECTS=()
    local name
    for name in tessera_client_{socket,jobs} tessera_paths tessera_frame tessera_self tessera_ledger tessera_measure \
                tessera_daemon_{state,admission,peers,main}; do
        object="$OUT/${name}_c.$EXTENSION"
        qasm_c_object "$DAEMON_DIRECTORY/$name.c" "$object" || return 1
        case "$name" in
            tessera_client_*) OBJECTS+=("$object") ;;
            tessera_paths|tessera_frame|tessera_self) OBJECTS+=("$object"); DAEMON_OBJECTS+=("$object") ;;
            *) DAEMON_OBJECTS+=("$object") ;;
        esac
    done
    SEAL_OBJECTS=()
    for name in obsignatio_{hash,seal}; do
        object="$OUT/${name}_cu.$EXTENSION"
        rm -f "$object"
        nvcc "${HOST_FLAGS[@]}" -O2 "${GENCODE[@]}" "${INCLUDES[@]}" -c "$OBSIGNATIO/$name.cu" -o "$object"
        [ -f "$object" ] || { echo "  build failed: $name.cu did not compile"; return 1; }
        SEAL_OBJECTS+=("$object")
    done
    OBJECTS+=("${SEAL_OBJECTS[@]}")
    DAEMON="$OUT/tessera_daemon$EXECUTABLE"
    rm -f "$DAEMON"
    nvcc "${HOST_FLAGS[@]}" "${GENCODE[@]}" "${LONG_PATHS[@]}" -o "$DAEMON" "${DAEMON_OBJECTS[@]}" \
        "${SCRIPTURA_OBJECTS[@]}" "${SEAL_OBJECTS[@]}" "${DAEMON_LIBRARIES[@]}"
    [ -f "$DAEMON" ] || { echo "  build failed: the tessera daemon did not link"; return 1; }
    return 0
}

qasm_link()
{
    local name="$1"
    shift
    local sources=("$@")
    BINARY="$OUT/$name$EXECUTABLE"
    rm -f "$BINARY"
    nvcc "${HOST_FLAGS[@]}" -std=c++17 -O2 "${GENCODE[@]}" "${INCLUDES[@]}" "${LONG_PATHS[@]}" -o "$BINARY" \
        "${sources[@]}" "${OBJECTS[@]}"
    [ -f "$BINARY" ] || { echo "  build failed: $name did not link"; return 1; }
    return 0
}
