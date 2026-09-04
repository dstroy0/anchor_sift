# Contributing {#proj_contributing}

## Build and test

```sh
cmake -S . -B build -DEMBEDDED_TYPES_WERROR=ON
cmake --build build --parallel
ctest --test-dir build --output-on-failure
```

Three CTest targets, one per header under test. `EMBEDDED_TYPES_BUILD_TESTS` defaults on when this
is the top-level project and off when it is consumed by another.

`test/harness.py` carries each build tree's flags:

```sh
python test/harness.py test                     # the library as it ships
python test/harness.py test --tree build-werror # the same, with every warning an error
python test/harness.py suites --strict          # every case registered, none behind a conditional
python test/harness.py cases test/unit/test_embed_types
```

The suites use [Unity](https://github.com/ThrowTheSwitch/Unity), fetched at `v2.6.1` when this
directory is configured. Generating a runner needs `ruby` on `PATH`. Both belong to `test/` alone.
The target a consumer links carries the include directory and `c_std_11`, and no test framework.

## Adding a suite

A suite is a directory under `test/unit/` holding exactly one `.c` of cases and a `CMakeLists.txt`
that names it:

```cmake
embedded_types_add_suite(test_embed_something)
```

Then one `add_subdirectory` line in `test/unit/CMakeLists.txt`. Nothing central holds a list of
suite names.

A case is `void test_<name>(void)` at file scope. Two shapes make a case silently never run, and
`harness.py suites --strict` reports both:

- **A definition the generator walks past.** Unity's generator collects `void test_<name>(void)` and
  nothing else. A case named anything else is never registered, and the suite still reports a pass.
- **A case defined inside a preprocessor conditional.** The generator reads case names out of the
  source text and does not see the conditional. The runner declares and calls the case whichever way
  the conditional went, and where it went the other way the definition is absent and the suite fails
  to link. Put the `#if` inside the case body, and call `TEST_IGNORE_MESSAGE` on the arm that cannot
  measure anything.

## Where the proof lives

Most of this library is proved by compiling. The eight width assertions, the packed-enum probe, and
every `EMBED_TABLE_LAYOUT` are static. A build that reaches the link step has already checked them,
and no case in `test/` repeats that work.

The suites cover what a static assertion does not reach:

- **Signedness.** A typedef pointing at the wrong signedness has the right size, and `sizeof` passes
  either way. Each case casts `-1` to the alias and tests the sign of the result.
- **Boolean normalization.** Any nonzero converts to 1. A plain eight-bit alias keeps the value it
  was given, and two true values can then compare unequal across an API boundary.
- **`EMBED_RAW`.** A word read from an odd address, checked against a `memcpy` of the same bytes.
- **Dispatch wiring.** Offsets are properties of the struct type, and an initializer naming the
  wrong function changes none of them. The suite calls through each member.
- **Generated entry points.** `EMBED_ENTRY` and `EMBED_ENTRY_V` emit a function that builds a
  compound literal from the caller's configuration and hands it to a backend. The suite calls both
  generated entries and checks what the backend received, including the context member the entry
  leaves out of its initializer.
- **The byte order.** `EMBED_BIG_ENDIAN` is derived from `__BYTE_ORDER__`. The case measures how the
  target lays a word out in memory. Reading the same macro back would compare the macro with itself.
- **The feature tests.** `EMBED_HAS_ATTRIBUTE` and `EMBED_HAS_BUILTIN` evaluate to zero for a name
  nothing defines. A non-zero result there would be non-zero for every name, and every attribute
  wrapper would be emitted on a compiler that rejects it.
- **The attribute wrappers.** A marked definition is still a definition and still computes what its
  body defines, and the alignment and packing attributes reach the type. Where the compiler cannot
  carry one, the case calls `TEST_IGNORE_MESSAGE`, and a case that measured nothing does not count
  as a pass.

## Never test the library with itself

The expected side of an assertion comes from a literal, from the compiler, or from exact arithmetic.
Never from the code under test.

A width checked against the macro that produced it compares the macro with itself and passes at any
value. `sizeof(embed_u32) == 4u` is a test. `sizeof(embed_u32) * 8u == 32u` against a macro derived
from the same type is not. Where a case needs an independent source, `uintptr_t` and `memcpy` come
from the compiler and the standard.

## Formatting

```sh
clang-format -i include/*.h test/unit/*/test_*.c
npm run format
```

`unity_runner.c` is generated and is listed in `.clang-format-ignore`. Formatting it by hand is
undone on the next generation.

120 columns. CI checks formatting and never rewrites it. A formatter that rewrites on CI produces
commits nobody reviewed and races the author's own push. Fix it in the working tree.

## Comments

Every header opens with the license banner and a `@file` block, and every declaration in it carries
its own Doxygen block. A block documents exactly one declaration. A contiguous family of similar
macros takes one block each, because nearly identical is not identical.

```c
/* embedded_types - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file embed_types.h
 * @brief What the translation unit is, in one sentence.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-30
 */
```

A macro parameter takes a real name with a trailing underscore, and the block is written around it.
`@param[in] x` documents a defect. Rename the parameter first, and the line then has something to
say. Pad every `@param` description to the longest name, and pad `@return` to match.

```c
/**
 * @brief Expands to __has_attribute(attribute_) where __has_attribute is defined.
 *
 * @param[in] attribute_ Attribute name, as passed to __has_attribute.
 * @return               The value __has_attribute gives for attribute_.
 * @warning Expands to EMBED_GNU_ATTRIBUTES where __has_attribute is undefined, ignoring attribute_.
 */
#define EMBED_HAS_ATTRIBUTE(attribute_) __has_attribute(attribute_)
```

Every attribute wrapper carries a `@warning` naming what its absence costs. Most cost speed when
they expand to nothing. `EMBED_ALIGN` and `EMBED_ALIAS` cost correctness. The `#if` does not
distinguish the two.

State the mechanism, not a consumer. These headers are shared. A block naming what one library does
with a macro, or naming a part it was measured on, documents a relationship instead of the macro.

## What belongs here

The test is whether it is machinery or a domain fact.

Machinery is anything a library above would otherwise define for itself: a width, a word, an
attribute wrapper, a static assertion, a feature probe, an argument count. Define it once, here.

A domain fact belongs to the library that has the opinion. A pool size, a protocol timer, a buffer
count. Those never come here, whatever their prefix looks like.

## Adding a declaration

1. Put it in the header it belongs to, in file order.
2. Write its Doxygen block as you write it, not afterwards.
3. If it can fail silently on some target, add the assertion that catches it or the `@warning` that
   names it.
4. If it is observable at run time, add a case to the suite that observes it independently.
5. Add its name to `keywords.txt`.

## Licensing

Contributions are accepted under the same terms as the project. There is no CLA. Opening a pull
request means you have the right to contribute the code and are doing so under AGPL-3.0-or-later.

Keep the banner on every new file. Both `LicenseRef-` identifiers in it resolve to files in
`LICENSES/`, and a scanner reports the expression as unresolved if one goes missing.
