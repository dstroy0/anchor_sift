#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational

# The engine is the repository's own, at src/c/engine: every build reads it there, and a tree without it fails
# here, before anything compiles
ENGINE="$(cd "$TOP/.." && pwd)/src/c/engine"
if [ ! -f "$ENGINE/engine_config.h" ]; then
    echo "  build failed: no engine at $ENGINE"
    exit 1
fi

# a build's path: c/..., cu/... and sims/... are the engine's, under src/, and anything else the project's
build_path()
{
    case "$1" in
        engine/*) printf '%s\n' "$ENGINE/${1#engine/}" ;;
        c/* | cu/* | sims/*) printf '%s\n' "$ENGINE/../../$1" ;;
        *) printf '%s\n' "$TOP/$1" ;;
    esac
}

build_stamp()
{
    local label="$1"
    if [ -n "${BUILD_OUT:-}" ]; then
        OUT="$BUILD_OUT"
        FINAL="$BUILD_OUT"
        mkdir -p "$OUT"
        return 0
    fi
    FINAL="$TOP/build"
    mkdir -p "$FINAL"
    find "$FINAL" -mindepth 1 -maxdepth 1 -type d \
        -name '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9]_*' \
        -mmin +1440 -exec rm -rf {} +
    OUT="$FINAL/$(date +%Y%m%d_%H%M%S)_$label"
    mkdir -p "$OUT"
    echo "  build directory: $OUT"
}

build_publish()
{
    local artifact="$1"
    [ "$FINAL" = "$OUT" ] && return 0
    cp -f "$artifact" "$FINAL/" || { echo "  build failed: could not copy $artifact to $FINAL (is it running?)"; return 1; }
    echo "  published $FINAL/$(basename "$artifact")"
}
