# Contributing {#proj_contributing}

## Build and test

All five environments are one build. `cmake/MMgrModule.cmake` emits `mmgr_<module>_<env>` for every
entry in `MMGR_ENVIRONMENTS`, so a single configure builds `host`, `word32`, `word16`, `idx16` and
`checks` together, and a single `ctest` run covers all five.

```sh
cmake -S . -B build -DMMGR_BUILD_TESTS=ON
cmake --build build --parallel
ctest --test-dir build --output-on-failure
```

A clean run is 160 CTest targets. `test_memoriam_praetereo` and `test_memoria_externa` are not
among them unless `MMGR_ENABLE_DMA` or `MMGR_ENABLE_EXTRAM` is on. They are skipped loudly, through
`MMGR_SUITES_SKIPPED` and a CMake status message, because a silently dropped suite leaves a passing
run that tested less than it looks like.

A capability gates the whole suite, never a case inside one. A suite that compiles half its cases
away still reports as passing.

## Formatting

Three formatters, one per language, each owning its own files and nothing else. All three wrap at
120 columns, so a Python tool and the C it rewrites line up in a side-by-side diff.

```sh
find src test -name '*.c' -o -name '*.h' | grep -v '^test/vendor/' | xargs clang-format -i
black tools
npm run format
```

CI checks and never rewrites. A formatter that rewrites on CI produces commits nobody reviewed and
races the author's own push; the fix belongs in the working tree.

## Comments

Public headers carry Doxygen comments. Implementation files carry a comment only where the code
cannot say it for itself - a bound that is not obvious, a cast that is load-bearing, a failure mode
you would see at runtime. A comment that restates the line is worse than none.

Every header opens with an SPDX line and a `@file` block. The group is `mod_<stem>`, the stem
column of `tools/dev_env/names.tsv`, and `docs/groups.dox` already declares it - do not add a
`@defgroup` to a header.

```c
/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 */
/**
 * @file spatium.h
 * @ingroup mod_spat
 * @brief A buffer, its capacity and a cursor, carried as one object.
 *
 * What the module is for, and what a caller has to know before using it. Warnings about what is
 * not checked go here, not in every entry.
 */
```

A config struct documents its members with `@param` in the struct's own block. Do not repeat them
on the entries that read it - they are aggregate-initialized members, not function parameters, and
listing them as parameters of a one-argument function reads as a lie:

```c
/**
 * @brief The one argument every entry in this module takes.
 *
 * @param buf Caller-owned storage [BORROWS]. The span does not release it.
 * @param cap Size of the storage in bytes.
 */
typedef struct
{
    uint8_t *const buf;
    const size_t cap;
} SpatiumCfg;

/**
 * @brief Builds a span over `buf`.
 *
 * @param c Reads `buf` and `cap`.
 * @return The span, by value.
 *
 * @slot{0}
 * @warning Does not check that `buf` is non-NULL.
 */
mmgr_span mmgr_spat_from(const SpatiumCfg *c);
```

`@slot{n}` is the entry's position in the dispatch table, `@ns{name}` names the table, and
`[BORROWS]`, `[TAKES OWNERSHIP]` and `[RETURNS OWNERSHIP]` mark who owns a pointer. Everything is
a borrow here, so `[BORROWS]` is what you will write.

Doxygen takes one branch of a `#if`. Put the doc block on the branch it takes, not above the
`#if`, or the entity comes out undocumented - `docs/Doxyfile` sets `PREDEFINED` and that is what
decides which branch that is.

Run `doxygen docs/Doxyfile` before committing. `WARN_IF_UNDOCUMENTED` is on, so anything you added
and did not document shows up in `docs/doxygen-warnings.log`.

## Adding a module

1. A directory under `src/`.
2. A three-line `CMakeLists.txt` calling `mmgr_add_module()`. Nothing central lists the modules, so
   there is no registry to keep in step.
3. One line in `src/CMakeLists.txt`.
4. One `@defgroup` in `docs/groups.dox`, placed where it belongs in the data path.
5. One guide in `docs/modules/`.
6. A row in `tools/dev_env/names.tsv`.

## Documentation

Anything in `docs/` that can be derived from the tree **is** derived from the tree and lives inside
a generated region. Regenerate before committing:

```sh
python -m tools.ci_tooling.ci gen
python -m tools.ci_tooling.ci check
```

Never hand-edit between the `BEGIN GENERATED` and `END GENERATED` markers. They are HTML comments,
and each one names the generator that owns that region.
