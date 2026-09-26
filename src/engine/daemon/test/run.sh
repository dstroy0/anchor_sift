#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
set -u

TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE="$(cd "$TEST/.." && pwd)"
TOP="$(cd "$MODULE/../.." && pwd)"
source "$TOP/maint/build_stamp.sh"
build_stamp tessera_test

SCRIPTURA="$TOP/engine/base/scriptura"
OBSIGNATIO="$TOP/engine/base/obsignatio"
INCLUDES=(-I "$TOP/engine" -I "$MODULE" -I "$SCRIPTURA" -I "$OBSIGNATIO")
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        MSVC_BIN="$(ls -d "/c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC"/*/bin/Hostx64/x64 2>/dev/null | tail -1)"
        if [ -z "$MSVC_BIN" ]; then
            MSVC_BIN="$(ls -d "/c/Program Files/Microsoft Visual Studio"/*/*/VC/Tools/MSVC/*/bin/Hostx64/x64 2>/dev/null | tail -1)"
        fi
        [ -n "$MSVC_BIN" ] || { echo "  no host compiler nvcc accepts on this platform was found."; exit 1; }
        SUFFIX=.exe
        OBJECT=obj
        build_host()
        {
            nvcc -ccbin "$MSVC_BIN" -Xcompiler /Zc:preprocessor -Xcompiler "/std:c11 /O2 /W4" "${INCLUDES[@]}" "$@"
        }
        build_device()
        {
            nvcc -ccbin "$MSVC_BIN" -Xcompiler /Zc:preprocessor -Xcompiler -W4 -O2 "${INCLUDES[@]}" "$@" -lpdh
        }
        LONG_PATHS=(-Xlinker /MANIFEST:EMBED -Xlinker "/MANIFESTINPUT:$(cygpath -m "$TOP/engine/long_paths.manifest")")
        ;;
    *)
        SUFFIX=
        OBJECT=o
        build_host()
        {
            cc -std=c11 -O2 -Wall -Wextra "${INCLUDES[@]}" "$@"
        }
        build_device()
        {
            nvcc -O2 -Xcompiler -Wall "${INCLUDES[@]}" "$@" -ldl
        }
        LONG_PATHS=()
        ;;
esac

FAILED=0
run_one()
{
    local name="$1"
    local binary="$OUT/$name$SUFFIX"
    [ -f "$binary" ] || { echo "  build failed: $name did not compile"; FAILED=1; return; }
    "$binary"
    local status=$?
    echo "  $name exit $status"
    [ "$status" -eq 0 ] || FAILED=1
}

rm -f "$OUT/tessera_ledger_test$SUFFIX" "$OUT/tessera_frame_test$SUFFIX" "$OUT/tessera_measure_test$SUFFIX"
build_host "$TEST/tessera_ledger_test.c" "$MODULE/tessera_ledger.c" -o "$OUT/tessera_ledger_test$SUFFIX"
run_one tessera_ledger_test
build_host "$TEST/tessera_frame_test.c" "$MODULE/tessera_frame.c" -o "$OUT/tessera_frame_test$SUFFIX"
run_one tessera_frame_test
if [ "${TESSERA_DEVICE:-1}" = "1" ]; then
    MEASURE_OBJECT="$OUT/tessera_measure_host.$OBJECT"
    SELF_OBJECT="$OUT/tessera_self_host.$OBJECT"
    rm -f "$MEASURE_OBJECT" "$SELF_OBJECT"
    build_host -c "$MODULE/tessera_measure.c" -o "$MEASURE_OBJECT"
    build_host -c "$MODULE/tessera_self.c" -o "$SELF_OBJECT"
    build_device "$TEST/tessera_measure_test.cu" "$MEASURE_OBJECT" "$SELF_OBJECT" "${LONG_PATHS[@]}" \
        -o "$OUT/tessera_measure_test$SUFFIX"
    run_one tessera_measure_test

    # the tests' daemons answer endpoints of their own ($TESSERA_RUNTIME), apart from the daemons real jobs use: a pipe
    # name on Windows, and on Linux a short folder, since a socket's path holds 108 bytes
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) RUNTIME="tessera_test_$$" ;;
        *) RUNTIME="$(mktemp -d /tmp/tessera_test.XXXXXX)" ;;
    esac

    # the daemon, and the client against it end to end
    rm -f "$OUT/tessera_daemon$SUFFIX" "$OUT/tessera_job_test$SUFFIX"
    OBJECTS=()
    for source in "$SCRIPTURA"/*.c "$MODULE"/tessera_ledger.c "$MODULE"/tessera_measure.c "$MODULE"/tessera_paths.c \
                  "$MODULE"/tessera_frame.c "$MODULE"/tessera_self.c "$MODULE"/tessera_client.c "$MODULE"/tessera_daemon.c; do
        object="$OUT/$(basename "$source" .c)_tessera.$OBJECT"
        rm -f "$object"
        build_host -c "$source" -o "$object"
        OBJECTS+=("$object")
    done
    SEAL_OBJECT="$OUT/obsignatio_tessera.$OBJECT"
    rm -f "$SEAL_OBJECT"
    build_device -c "$OBSIGNATIO/obsignatio.cu" -o "$SEAL_OBJECT"
    DAEMON_OBJECTS=()
    CLIENT_OBJECTS=()
    for object in "${OBJECTS[@]}"; do
        case "$object" in
            *tessera_client_tessera.$OBJECT) CLIENT_OBJECTS+=("$object") ;;
            *tessera_daemon_tessera.$OBJECT) DAEMON_OBJECTS+=("$object") ;;
            *tessera_ledger_tessera.$OBJECT|*tessera_measure_tessera.$OBJECT) DAEMON_OBJECTS+=("$object") ;;
            *) DAEMON_OBJECTS+=("$object"); CLIENT_OBJECTS+=("$object") ;;
        esac
    done
    build_device "${DAEMON_OBJECTS[@]}" "$SEAL_OBJECT" "${LONG_PATHS[@]}" -o "$OUT/tessera_daemon$SUFFIX"
    [ -f "$OUT/tessera_daemon$SUFFIX" ] || { echo "  build failed: the daemon did not link"; FAILED=1; }
    build_device "$TEST/tessera_job_test.cu" "${CLIENT_OBJECTS[@]}" "$SEAL_OBJECT" "${LONG_PATHS[@]}" \
        -o "$OUT/tessera_job_test$SUFFIX"
    if [ -f "$OUT/tessera_job_test$SUFFIX" ]; then
        # the test damages the history on purpose, so it runs in a state of its own; the daemon it starts inherits it
        STATE="$OUT/tessera_state"
        rm -rf "$STATE"
        mkdir -p "$STATE"
        TESSERA_STATE="$(cygpath -w "$STATE" 2>/dev/null || echo "$STATE")" TESSERA_RUNTIME="$RUNTIME" \
        "$OUT/tessera_job_test$SUFFIX" "$(cygpath -w "$OUT/tessera_daemon$SUFFIX" 2>/dev/null || echo "$OUT/tessera_daemon$SUFFIX")"
        STATUS=$?
        echo "  tessera_job_test exit $STATUS"
        [ "$STATUS" -eq 0 ] || FAILED=1
    else
        echo "  build failed: tessera_job_test did not compile"
        FAILED=1
    fi

    # the host's processors: tessera_run holds a host ticket around its command, beside the daemon it starts
    RUN_OBJECT="$OUT/tessera_run_tessera.$OBJECT"
    rm -f "$RUN_OBJECT" "$OUT/tessera_run$SUFFIX" "$OUT/tessera_burn$SUFFIX"
    build_host -c "$MODULE/tessera_run.c" -o "$RUN_OBJECT"
    build_device "$RUN_OBJECT" "${CLIENT_OBJECTS[@]}" "$SEAL_OBJECT" "${LONG_PATHS[@]}" -o "$OUT/tessera_run$SUFFIX"
    build_host "$TEST/tessera_burn.c" -o "$OUT/tessera_burn$SUFFIX"
    if [ -f "$OUT/tessera_run$SUFFIX" ] && [ -f "$OUT/tessera_burn$SUFFIX" ]; then
        # the host test runs in a state of its own, which the host daemon it starts inherits
        HOST_STATE="$OUT/tessera_host_state"
        rm -rf "$HOST_STATE"
        mkdir -p "$HOST_STATE"
        TESSERA_STATE="$(cygpath -w "$HOST_STATE" 2>/dev/null || echo "$HOST_STATE")" TESSERA_RUNTIME="$RUNTIME" \
        bash "$TEST/tessera_run_test.sh" "$OUT/tessera_run$SUFFIX" "$OUT/tessera_burn$SUFFIX" "$OUT/tessera_run_scratch"
        STATUS=$?
        echo "  tessera_run_test exit $STATUS"
        [ "$STATUS" -eq 0 ] || FAILED=1
        # once it holds, tessera_run and the daemon it starts are published together into build/tessera_host, where
        # every build that wraps itself in a host job finds them; the device daemons beside the programs are untouched.
        # A copy that is running is renamed aside first (Windows lets a running program be renamed, not overwritten),
        # and the jobs already under it keep it; the ones set aside before are removed once nothing runs them
        if [ "$STATUS" -eq 0 ] && [ "$FINAL" != "$OUT" ]; then
            HOST="$FINAL/tessera_host"
            mkdir -p "$HOST"
            rm -f "$HOST"/*.replaced 2> /dev/null
            PUBLISHED=1
            for name in "tessera_run$SUFFIX" "tessera_daemon$SUFFIX"; do
                if [ -f "$HOST/$name" ]; then
                    mv -f "$HOST/$name" "$HOST/$name.$(date +%Y%m%d_%H%M%S).replaced" || PUBLISHED=0
                fi
                cp -f "$OUT/$name" "$HOST/$name" || PUBLISHED=0
            done
            if [ "$PUBLISHED" -eq 1 ]; then
                echo "  published $HOST/tessera_run$SUFFIX and its daemon"
            else
                echo "  build failed: could not publish tessera_run and its daemon to $HOST"
                FAILED=1
            fi
        fi
    else
        echo "  build failed: tessera_run or tessera_burn did not compile"
        FAILED=1
    fi
fi
echo "  tessera tests exit $FAILED"
exit "$FAILED"
