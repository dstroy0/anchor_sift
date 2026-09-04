# Security {#proj_security}

## Scope

embedded_types declares types and expands macros. It has no functions, no storage, and no run-time
behavior.

## What fails the build

**A wrong width.** Every unsigned alias is pinned by a static assertion. A target where `embed_u32`
is not thirty-two bits fails to compile, with a message naming the type.

**An underivable machine word.** `EMBED_WORD_BITS` comes from `UINTPTR_MAX`. Where that macro is
absent, or names a width other than sixteen, thirty-two or sixty-four, the header raises `#error`.
There is no fallback width.

**A disregarded packed-enum attribute.** A compiler may accept `__attribute__((packed))` and ignore
it, and no `#if` detects that. `EmbedEnumProbe` has a one-byte range and its size is asserted. A
build that ignored packing fails to compile.

**A pre-C11 dialect.** No earlier revision has a static assertion. Unguarded, `EMBED_STATIC_ASSERT`
would parse as a function declaration with an implicit `int`, and every assertion in every consumer
would compile to nothing. The header raises `#error` below C11.

## What is not checked

**Unaligned access without the attributes.** `EMBED_RAW` lowers alignment to 1 and permits aliasing.
Both are required. Where the compiler supports neither, both expand to nothing, `embed_raw_word`
reverts to the natural alignment of `embed_word`, and a read through it at an unaligned address is
undefined. Nothing diagnoses this. The `@warning` on `EMBED_ALIGN` and `EMBED_ALIAS` states it. This
is the one place in the library where a missing attribute costs correctness.

**Dispatch table wiring.** `EMBED_TABLE_LAYOUT` asserts byte offsets and `sizeof`. Offsets are
properties of the struct type, and an initializer naming the wrong function changes none of them. A
table can satisfy every assertion and still dispatch to the wrong function. `test/unit/` calls
through a table to cover that.

**Anything at run time.** There are no bounds checks, because there is no run-time code.

**Concurrency.** There is no state.

## Hardening the build

Build with `-DEMBEDDED_TYPES_WERROR=ON`, in CI as well as locally. The warning set is in
`CMakeLists.txt`.

Keep `-Wconversion` and `-Wsign-conversion` on in the consuming build. Those are what make a
narrowing visible at a call site.

## Reporting

Open a private security advisory at
<https://github.com/dstroy0/embedded_types/security/advisories/new>, or e-mail dquigg123@gmail.com.
Include the compiler and target, the value of `EMBED_WORD_BITS` the build derived, and the smallest
translation unit that shows the behavior.

Fixes land on `main`.
