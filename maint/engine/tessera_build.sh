#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational

# A program that uses the device is a job on the device's tessera daemon (engine/runtime/daemon, submitted through
# engine/sims/sim_job.cu). TESSERA_INCLUDES are the headers the program and sim_job.cu read. tessera_build compiles the
# client objects the program links and the seal its job's signum is taken with, and builds the daemon beside the
# program, where the program starts it when none answers. It reads TOP, OUT, EXTENSION, HOST_FLAGS, GENCODE and
# INCLUDES, takes a suffix for its objects and then the scriptura objects the daemon links, and sets the arrays
# TESSERA_OBJECTS and TESSERA_SEAL. tessera_run_build, after it, builds tessera_run beside the daemon.
TESSERA_INCLUDES=(-I "$ENGINE/sims" -I "$ENGINE/runtime/daemon" -I "$ENGINE/runtime/obsignatio")

tessera_build()
{
    local suffix="$1"
    shift
    local scriptura_objects=("$@")
    local daemon_directory="$ENGINE/runtime/daemon"
    local includes=("${INCLUDES[@]}" "${TESSERA_INCLUDES[@]}")
    local daemon_objects=()
    local long_paths=()
    local daemon
    local daemon_libraries=()
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            long_paths=(-Xlinker /MANIFEST:EMBED -Xlinker "/MANIFESTINPUT:$(cygpath -m "$ENGINE/long_paths.manifest")")
            daemon="$OUT/tessera_daemon.exe"
            daemon_libraries=(-lpdh)
            ;;
        *)
            daemon="$OUT/tessera_daemon"
            daemon_libraries=(-ldl -lpthread)
            ;;
    esac
    TESSERA_OBJECTS=()
    local name
    local object
    for name in tessera_client_{socket,jobs} tessera_paths tessera_frame tessera_self tessera_ledger tessera_measure \
                tessera_daemon_{state,admission,peers,main}; do
        object="$OUT/${name}_${suffix}.$EXTENSION"
        rm -f "$object"
        case "$(uname -s)" in
            MINGW*|MSYS*|CYGWIN*)
                nvcc "${HOST_FLAGS[@]}" -Xcompiler "/std:c11 /O2" "${includes[@]}" -c "$daemon_directory/$name.c" \
                    -o "$object" ;;
            *)
                cc -std=c11 -O2 -fPIC "${includes[@]}" -c "$daemon_directory/$name.c" -o "$object" ;;
        esac
        [ -f "$object" ] || { echo "  build failed: $name.c did not compile"; return 1; }
        case "$name" in
            tessera_client_*) TESSERA_OBJECTS+=("$object") ;;
            tessera_paths|tessera_frame|tessera_self) TESSERA_OBJECTS+=("$object"); daemon_objects+=("$object") ;;
            *) daemon_objects+=("$object") ;;
        esac
    done
    TESSERA_SEAL=()
    for name in obsignatio_{hash,seal}; do
        object="$OUT/${name}_${suffix}.$EXTENSION"
        rm -f "$object"
        nvcc "${HOST_FLAGS[@]}" -O2 "${GENCODE[@]}" "${includes[@]}" -c "$ENGINE/runtime/obsignatio/$name.cu" \
            -o "$object"
        [ -f "$object" ] || { echo "  build failed: $name.cu did not compile"; return 1; }
        TESSERA_SEAL+=("$object")
    done
    rm -f "$daemon"
    nvcc "${HOST_FLAGS[@]}" "${GENCODE[@]}" "${long_paths[@]}" -o "$daemon" "${daemon_objects[@]}" \
        "${scriptura_objects[@]}" "${TESSERA_SEAL[@]}" "${daemon_libraries[@]}"
    [ -f "$daemon" ] || { echo "  build failed: the tessera daemon did not link"; return 1; }
}

# tessera_run_build builds tessera_run, the host job's wrapper, beside the daemon tessera_build made, from the same
# client objects and seal. It takes the same suffix and scriptura objects.
tessera_run_build()
{
    local suffix="$1"
    shift
    local scriptura_objects=("$@")
    local includes=("${INCLUDES[@]}" "${TESSERA_INCLUDES[@]}")
    local name
    local object
    local run_objects=()
    local long_paths=()
    local run
    local run_libraries=()
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            long_paths=(-Xlinker /MANIFEST:EMBED -Xlinker "/MANIFESTINPUT:$(cygpath -m "$ENGINE/long_paths.manifest")")
            run="$OUT/tessera_run.exe"
            ;;
        *)
            run="$OUT/tessera_run"
            run_libraries=(-ldl -lpthread)
            ;;
    esac
    rm -f "$run"
    for name in tessera_run_{common,windows,posix,child,main}; do
        object="$OUT/${name}_${suffix}.$EXTENSION"
        rm -f "$object"
        case "$(uname -s)" in
            MINGW*|MSYS*|CYGWIN*)
                nvcc "${HOST_FLAGS[@]}" -Xcompiler "/std:c11 /O2" "${includes[@]}" -c "$ENGINE/runtime/daemon/$name.c" \
                    -o "$object" ;;
            *)
                cc -std=c11 -O2 -fPIC "${includes[@]}" -c "$ENGINE/runtime/daemon/$name.c" -o "$object" ;;
        esac
        [ -f "$object" ] || { echo "  build failed: $name.c did not compile"; return 1; }
        run_objects+=("$object")
    done
    nvcc "${HOST_FLAGS[@]}" "${GENCODE[@]}" "${long_paths[@]}" -o "$run" "${run_objects[@]}" "${TESSERA_OBJECTS[@]}" \
        "${scriptura_objects[@]}" "${TESSERA_SEAL[@]}" "${run_libraries[@]}"
    [ -f "$run" ] || { echo "  build failed: tessera_run did not link"; return 1; }
}
