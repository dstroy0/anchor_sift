# embedded_types

Three C11 headers: fixed-width integer aliases, a machine word derived from the target, and the
compile-time machinery around them. Header only. No allocation, nothing before `main`, and the only
system headers reached are `stddef.h` and `stdint.h`.

```c
#include "embed_types.h"
#include "embed_dispatch_layout.h"

static embed_u32 crc;
static embed_word accumulator;
static embed_index offset;

/* embed_raw_word is embed_word with alignment 1 and may_alias. A read at an unaligned address
   through the plain embed_word is undefined. */
static embed_word at_odd_offset(const embed_u8 *bytes)
{
    return *(const embed_raw_word *)(const void *)(bytes + 1);
}

/* Emits one static assertion per member for its byte offset, plus one for sizeof(ScanNs). A member
   left out of the list, or padding between two members, fails the build. */
typedef struct
{
    embed_index (*length)(const embed_u8 *at);
    embed_bool (*is_empty)(const embed_u8 *at);
} ScanNs;
EMBED_TABLE_LAYOUT(ScanNs, length, is_empty);
```

## Files

| path                                                                         | contents                                                                             |
| ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| [`include/embed_types.h`](include/embed_types.h)                             | the widths, the boolean, the word, the index, the raw-access word, the assertions    |
| [`include/embed_compiler_directives.h`](include/embed_compiler_directives.h) | feature probes, the static assertion, attribute wrappers, diagnostic pragmas, guards |
| [`include/embed_dispatch_layout.h`](include/embed_dispatch_layout.h)         | `EMBED_TABLE_LAYOUT`, `EMBED_CALL`, `EMBED_ENTRY`, and the machinery behind them     |
| [`test/unit/`](test/unit)                                                    | one Unity suite per header, each its own CTest target                                |
| [`test/harness.py`](test/harness.py)                                         | suite discovery, Unity runner generation, and the two build trees                    |
| [`cmake/`](cmake)                                                            | `embedded_types_add_suite()`                                                         |
| [`LICENSES/`](LICENSES)                                                      | the AGPL text and the two LicenseRef documents                                       |

## Symbols

| symbol                                                                                                                        | definition                                                           |
| ----------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| `embed_u8` … `embed_u64`, `embed_i8` … `embed_i64`                                                                            | `uint8_t` … `int64_t`, each unsigned width pinned by an assertion    |
| `embed_bool`, `EMBED_TRUE`, `EMBED_FALSE`                                                                                     | `_Bool` in C, `bool` in C++; the two constants are cast to that type |
| `embed_word`, `embed_iword`                                                                                                   | the unsigned and signed integer of `EMBED_WORD_BITS` bits            |
| `embed_index`                                                                                                                 | the unsigned integer of `EMBED_INDEX_BITS` bits, for offsets         |
| `embed_raw_word`                                                                                                              | `embed_word` with alignment lowered to 1 and aliasing permitted      |
| `EMBED_STATIC_ASSERT`                                                                                                         | `_Static_assert` in C11, `static_assert` in C23, `#error` below C11  |
| `EMBED_HAS_ATTRIBUTE`                                                                                                         | `__has_attribute`, or `EMBED_GNU_ATTRIBUTES` where it is undefined   |
| `EMBED_HAS_BUILTIN`                                                                                                           | `__has_builtin`, or 0 where it is undefined                          |
| `EMBED_INLINE`, `EMBED_FLATTEN`, `EMBED_ENUM_PACKED`, `EMBED_ALIGN`, `EMBED_ALIAS`, `EMBED_RAW`, `EMBED_UNUSED`, `EMBED_WEAK` | the attribute where available, empty where not                       |
| `EMBED_CAT`, `EMBED_NARG`, `EMBED_ARG_N`                                                                                      | two-step token paste, and argument count from 1 to 24                |
| `EMBED_CALL`                                                                                                                  | `entry_(&(ArgsType_){__VA_ARGS__})`                                  |
| `EMBED_ENTRY`, `EMBED_ENTRY_V`                                                                                                | a value-returning and a void entry point, both built on `EMBED_CALL` |
| `EMBED_TABLE_LAYOUT`, `EMBED_TABLE_STORAGE`                                                                                   | the offset and size assertions, and `static const`                   |
| `EMBED_FUNCTION_POINTER_BYTES`                                                                                                | `sizeof(void (*)(void))`, the stride one dispatch slot takes         |
| `EMBED_BIG_ENDIAN`, `EMBED_FAST_UNALIGNED_LOAD`                                                                               | 0 or 1, from `__BYTE_ORDER__` and the target's load behavior         |

## EMBED_WORD_BITS

Derived from `UINTPTR_MAX`:

| `UINTPTR_MAX`        | `EMBED_WORD_BITS` |
| -------------------- | ----------------- |
| `0xFFFFFFFFFFFFFFFF` | 64                |
| `0xFFFFFFFF`         | 32                |
| `0xFFFF`             | 16                |
| absent, or any other | `#error`          |

`EMBED_INDEX_BITS` is 16 when `EMBED_WORD_BITS` is 16 and 32 otherwise.

Define `EMBED_WORD_BITS` on the command line to override the derivation. `EMBED_WORD_BITS_WAS_OVERRIDDEN`
is then 1, and 0 where the derivation ran. x32, ILP32-on-64, and large-model eight-bit targets are
the cases where an override is needed.

## Building

```sh
cmake -S . -B build -DEMBEDDED_TYPES_WERROR=ON
cmake --build build
ctest --test-dir build --output-on-failure
```

Through the harness:

```sh
python test/harness.py test                     # the library as it ships
python test/harness.py test --tree build-werror # the same, with every warning an error
python test/harness.py suites --strict          # every case registered, none behind a conditional
```

Configuring fetches [Unity](https://github.com/ThrowTheSwitch/Unity) at `v2.6.1`. Generating a
suite's runner needs `ruby` on `PATH`. Both are dependencies of `test/` alone.

Consuming it:

```cmake
add_subdirectory(embedded_types)
target_link_libraries(your_target PRIVATE embedded_types::embedded_types)
```

The `embedded_types::embedded_types` alias is an INTERFACE target carrying the include directory and
`c_std_11`. It carries no warning flags. The diagnostics in `CMakeLists.txt` apply to this project's
own targets.

## Status

1.0.0. Three suites, 27 cases, passing under
`-Wall -Wextra -Wpedantic -Wshadow -Wcast-align -Wcast-qual -Wstrict-prototypes -Wpointer-arith
-Wvla -Werror`.

The suites drop `-Wconversion`, `-Wsign-conversion` and `-Wmissing-prototypes` from the set the
library is compiled under. Unity's assertion macros widen and compare inside the macro body, and a
Unity case is a file-scope definition with nothing declaring it.

## Licensing

**This library is free to use under AGPL-3.0-or-later, and always will be.** No registration, no
key, no gate.

Every use falls under AGPL-3.0-or-later **unless** you hold explicit permission, which is one of
exactly two things:

- **A commercial contract**, negotiated and signed. Where the AGPL's terms do not suit a product,
  terms are negotiable. Write to <dquigg123@gmail.com>.
  See [`LICENSES/LicenseRef-Commercial.txt`](LICENSES/LicenseRef-Commercial.txt).

- **An educator's license**, issued to you personally. Write from your faculty, research or teaching
  address, ordinarily `.edu` or `.org`, describing what you intend to do with it. Granted case by
  case. See [`LICENSES/LicenseRef-Educational.txt`](LICENSES/LicenseRef-Educational.txt).

The educator's license exists so that value returns to your institution and your department, and the
environment that produced the work is enriched by what the work becomes. That is its whole purpose,
and it is a term of the license. Credit the underlying systems and the students and faculty who did
the work, and if the work becomes a product, a royalty ladder applies with a share to the
institution at minimum and to the department where its rules allow.

It is issued to a person, not a department. It does not extend to your colleagues, your students or
your lab. Each person applies for their own, and there is no grandfathering. It is revocable at
will. Conduct undertaken to defeat its purpose ends it immediately, with no notice period and no
opportunity to cure.

If you do not intend to return value to your institution, take the AGPL. It costs nothing and asks
none of this.

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).
