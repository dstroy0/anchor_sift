#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational

# A program that uses the device is a job on the device's tessera daemon (engine/daemon, submitted through
# engine/sims/sim_job.cu). TESSERA_INCLUDES are the headers the program and sim_job.cu read. tessera_build compiles the
# client objects the program links and the seal its job's signum is taken with, and builds the daemon beside the
# program, where the program starts it when none answers. It reads TOP, OUT, EXTENSION, HOST_FLAGS, GENCODE and
# INCLUDES, takes a suffix for its objects and then the scriptura objects the daemon links, and sets TESSERA_OBJECTS
# and TESSERA_SEAL. tessera_run_build, after it, builds tessera_run beside the daemon.
TESSERA_INCLUDES=(-I "$ENGINE/sims" -I "$ENGINE/daemon" -I "$ENGINE/base/obsignatio")

tessera_build()
{
    local suffix="$1"
    shift
    local scriptura_objects=("$@")
    local daemon_directory="$ENGINE/daemon"
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
    for name in tessera_client tessera_paths tessera_frame tessera_self tessera_ledger tessera_measure tessera_daemon; do
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
            tessera_client) TESSERA_OBJECTS+=("$object") ;;
            tessera_paths|tessera_frame|tessera_self) TESSERA_OBJECTS+=("$object"); daemon_objects+=("$object") ;;
            *) daemon_objects+=("$object") ;;
        esac
    done
    TESSERA_SEAL="$OUT/obsignatio_${suffix}.$EXTENSION"
    rm -f "$TESSERA_SEAL"
    nvcc "${HOST_FLAGS[@]}" -O2 "${GENCODE[@]}" "${includes[@]}" -c "$ENGINE/base/obsignatio/obsignatio.cu" \
        -o "$TESSERA_SEAL"
    [ -f "$TESSERA_SEAL" ] || { echo "  build failed: obsignatio.cu did not compile"; return 1; }
    rm -f "$daemon"
    nvcc "${HOST_FLAGS[@]}" "${GENCODE[@]}" "${long_paths[@]}" -o "$daemon" "${daemon_objects[@]}" \
        "${scriptura_objects[@]}" "$TESSERA_SEAL" "${daemon_libraries[@]}"
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
    local object="$OUT/tessera_run_${suffix}.$EXTENSION"
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
    rm -f "$object" "$run"
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            nvcc "${HOST_FLAGS[@]}" -Xcompiler "/std:c11 /O2" "${includes[@]}" -c "$ENGINE/daemon/tessera_run.c" \
                -o "$object" ;;
        *)
            cc -std=c11 -O2 -fPIC "${includes[@]}" -c "$ENGINE/daemon/tessera_run.c" -o "$object" ;;
    esac
    [ -f "$object" ] || { echo "  build failed: tessera_run.c did not compile"; return 1; }
    nvcc "${HOST_FLAGS[@]}" "${GENCODE[@]}" "${long_paths[@]}" -o "$run" "$object" "${TESSERA_OBJECTS[@]}" \
        "${scriptura_objects[@]}" "$TESSERA_SEAL" "${run_libraries[@]}"
    [ -f "$run" ] || { echo "  build failed: tessera_run did not link"; return 1; }
}
