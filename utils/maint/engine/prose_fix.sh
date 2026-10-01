#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# The banned constructions this hand wrote, rewritten in place, one exact line each. Every edit is a line number
# and the two texts, and a line whose text has moved is left alone and reported
#
#     utils/maint/engine/prose_fix.sh
set -u

TOP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# file<TAB>line<TAB>old<TAB>new, the old text matched whole, and a moved line is never rewritten by accident
edit() {
    local file="$TOP/$1"
    local line="$2"
    local old="$3"
    local new="$4"
    local held
    held="$(sed -n "${line}p" "$file")"
    case "$held" in
        *"$old"*)
            local away="${held//"$old"/"$new"}"
            printf '%s\n' "$away" >"$TOP/build/prose_fix.line"
            sed -i "${line}r $TOP/build/prose_fix.line" "$file"
            sed -i "${line}d" "$file"
            ;;
        *)
            echo "  $1:$line no longer holds \"$old\""
            ;;
    esac
}

mkdir -p "$TOP/build"

edit src/engine/compiler/cubin/sass_assemble.c 129 \
    "the number's high word. strtoull stops at the dot," "the number's high word. strtoull stops at the dot:"
edit src/engine/compiler/cubin/sass_assemble.c 179 \
    "change one operand, which is the field and whatever" "change one operand: the field and whatever"
edit src/engine/compiler/cubin/sass_assemble.c 204 \
    "a label that names a symbol rather than a label of the text" "a label that names a symbol and not a label of the text"
edit src/engine/compiler/cubin/sass_assemble.c 205 \
    "the loader fills it, so the instruction is checked" "the loader fills it. The instruction is then checked"
edit src/engine/compiler/cubin/sass_assemble.c 264 \
    "A barrier no instruction set is already at rest, so waiting on all" "A barrier no instruction set is already at rest, and waiting on all"
edit src/engine/compiler/cubin/sass_assemble.h 7 \
    "the base carries its own operands, so" "the base carries its own operands, and"
edit src/engine/compiler/cubin/sass_machine.c 57 \
    "register by its number alone, so the pair beginning at R14" "register by its number alone, and the pair beginning at R14"
edit src/engine/compiler/cubin/sass_machine.c 190 \
    "a system register is named, not counted, so two instructions that" "a system register is named, not counted, and two instructions that"
edit src/engine/compiler/cubin/sass_machine.h 8 \
    "operand fields hold, so the encoding a form was first seen with" "operand fields hold, and the encoding a form was first seen with"

rm -f "$TOP/build/prose_fix.line"
echo "done"
