// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// cubin_write.c: the pattern's sections read, the kernel's code and attributes put in, and the ELF laid out again
#include "cubin_write.h"

#include <stdio.h>
#include <string.h>

// where the ELF header keeps what this reads and writes
#define ELF_PHOFF 32u
#define ELF_SHOFF 40u
#define ELF_PHENTSIZE 54u
#define ELF_PHNUM 56u
#define ELF_SHENTSIZE 58u
#define ELF_SHNUM 60u
#define ELF_SHSTRNDX 62u
#define ELF_HEADER_BYTES 64u

// where a section header keeps what this reads and writes
#define SECTION_NAME 0u
#define SECTION_OFFSET 24u
#define SECTION_SIZE 32u
#define SECTION_INFO 44u
#define SECTION_ALIGN 48u

// where a program header keeps what this reads and writes
#define SEGMENT_OFFSET 8u
#define SEGMENT_FILESIZE 32u
#define SEGMENT_MEMSIZE 40u

// where a symbol keeps what this reads and writes, and how long one is
#define SYMBOL_NAME 0u
#define SYMBOL_SIZE 16u
#define SYMBOL_BYTES 24u

// the register count sits in the top byte of the code section's sh_info, the symbol it names in the rest
#define SECTION_INFO_REGISTERS 24u

// the attributes of a kernel this writes: the count of registers a thread holds, and where the exits lie. An
// attribute is a byte of format, a byte of attribute, two bytes of size and the value
#define ATTRIBUTE_REGISTERS 0x2fu
#define ATTRIBUTE_EXITS 0x1cu
#define ATTRIBUTE_HEADER 4u
#define ATTRIBUTE_FORMAT_VALUE 4u

// the most sections a cubin this writes holds, and the room its sections are laid out with
#define CUBIN_SECTIONS 64u

// a section of the pattern as the writer holds it: where it was, how long it was, the bytes it takes now and how many,
// and where it goes
typedef struct
{
    unsigned long long was_at;
    unsigned long long was_size;
    const unsigned char *bytes;
    unsigned long long size;
    unsigned long long align;
    unsigned long long goes_at;
} CubinSection;

static unsigned long long cubin_read(const unsigned char *bytes, unsigned int width)
{
    unsigned long long value = 0ull;
    for (unsigned int byte = 0u; byte < width; byte += 1u)
    {
        value |= (unsigned long long)bytes[byte] << (8u * byte);
    }
    return value;
}

static void cubin_put(unsigned char *bytes, unsigned int width, unsigned long long value)
{
    for (unsigned int byte = 0u; byte < width; byte += 1u)
    {
        bytes[byte] = (unsigned char)((value >> (8u * byte)) & 0xffu);
    }
}

// `at` rounded up to a multiple of `align`, which 0 and 1 both leave alone
static unsigned long long cubin_round(unsigned long long at, unsigned long long align)
{
    return (align < 2ull) ? at : (((at + align - 1ull) / align) * align);
}

unsigned int cubin_exits_find(const unsigned char *code, unsigned long long code_size, unsigned long long exit_low,
                              unsigned int *exits, unsigned int room)
{
    // the operation is the low twelve bits of the word, what one exit shares with another
    const unsigned long long operation = exit_low & 0xfffull;
    unsigned int found = 0u;
    for (unsigned long long at = 0ull; (at + 16ull) <= code_size; at += 16ull)
    {
        if (((cubin_read(&code[at], 8u) & 0xfffull) == operation) && (found < room))
        {
            exits[found] = (unsigned int)at;
            found += 1u;
        }
    }
    return found;
}

// the section header table of `pattern`, and through `count` how many headers it holds and through `strings` where
// the section names lie
static unsigned long long cubin_sections(const unsigned char *pattern, unsigned int *count,
                                         unsigned long long *strings, unsigned long long *header_bytes)
{
    const unsigned long long table = cubin_read(&pattern[ELF_SHOFF], 8u);
    *header_bytes = cubin_read(&pattern[ELF_SHENTSIZE], 2u);
    *count = (unsigned int)cubin_read(&pattern[ELF_SHNUM], 2u);
    const unsigned long long names = table + (cubin_read(&pattern[ELF_SHSTRNDX], 2u) * *header_bytes);
    *strings = cubin_read(&pattern[names + SECTION_OFFSET], 8u);
    return table;
}

unsigned int cubin_registers_read(const unsigned char *pattern, const char *kernel)
{
    unsigned int count = 0u;
    unsigned long long strings = 0ull;
    unsigned long long header_bytes = 0ull;
    const unsigned long long table = cubin_sections(pattern, &count, &strings, &header_bytes);
    char named[256];
    snprintf(named, sizeof(named), ".text.%s", kernel);
    unsigned int found = 0u;
    for (unsigned int index = 0u; index < count; index += 1u)
    {
        const unsigned long long at = table + ((unsigned long long)index * header_bytes);
        const unsigned long long name = strings + cubin_read(&pattern[at + SECTION_NAME], 4u);
        if (strcmp((const char *)&pattern[name], named) == 0)
        {
            found = (unsigned int)(cubin_read(&pattern[at + SECTION_INFO], 4u) >> SECTION_INFO_REGISTERS);
        }
    }
    return found;
}

// the place of the section named `name`, or `count` where the pattern holds none
static unsigned int cubin_section_named(const unsigned char *pattern, const CubinSection *sections, unsigned int count,
                                        unsigned long long strings, const char *name)
{
    unsigned int found = count;
    for (unsigned int index = 0u; index < count; index += 1u)
    {
        const unsigned long long at = strings + cubin_read(&pattern[sections[index].was_at + SECTION_NAME], 4u);
        found = (strcmp((const char *)&pattern[at], name) == 0) ? index : found;
    }
    return found;
}

// the attribute `attribute` of the section's bytes, or NULL where it holds none; its value's size through `size`
static const unsigned char *cubin_attribute(const unsigned char *bytes, unsigned long long size,
                                            unsigned int attribute, unsigned long long *value_size)
{
    unsigned long long at = 0ull;
    while ((at + ATTRIBUTE_HEADER) <= size)
    {
        const unsigned int format = bytes[at];
        const unsigned int named = bytes[at + 1u];
        const unsigned long long kept =
            (format == ATTRIBUTE_FORMAT_VALUE) ? cubin_read(&bytes[at + 2u], 2u) : 0ull;
        if (named == attribute)
        {
            *value_size = kept;
            return &bytes[at];
        }
        at += ATTRIBUTE_HEADER + kept;
    }
    *value_size = 0ull;
    return NULL;
}

// the kernel's info section written with the exits this cubin holds, into `written`; its size, or 0 where the section
// holds no exit attribute and nothing was written
static unsigned long long cubin_info_write(const unsigned char *bytes, unsigned long long size,
                                           const unsigned int *exits, unsigned int exit_count, unsigned char *written,
                                           unsigned long long room)
{
    unsigned long long value_size = 0ull;
    const unsigned char *const found = cubin_attribute(bytes, size, ATTRIBUTE_EXITS, &value_size);
    if (found == NULL)
    {
        // A section with no exit attribute belongs to a function and not to a kernel: an entry ends at an EXIT and
        // the ELF says where each one lies, where a function ends at a RET and has none to say. Carrying the
        // section over untouched is right for that, and only for that - code holding exits whose section has no
        // attribute to record them in is a kernel being written into a function's place, and is refused
        if (exit_count != 0u)
        {
            return 0ull;
        }
        if (size > room)
        {
            printf("  cubin_write: the function's attributes take %llu bytes where the room is %llu\n", size, room);
            return 0ull;
        }
        memcpy(written, bytes, size);
        return size;
    }
    const unsigned long long before = (unsigned long long)(found - bytes);
    const unsigned long long after = before + ATTRIBUTE_HEADER + value_size;
    const unsigned long long written_size = before + ATTRIBUTE_HEADER + (4ull * exit_count) + (size - after);
    if (written_size > room)
    {
        printf("  cubin_write: the kernel's attributes take %llu bytes where the room is %llu\n", written_size, room);
        return 0ull;
    }
    memcpy(written, bytes, before);
    written[before] = ATTRIBUTE_FORMAT_VALUE;
    written[before + 1u] = (unsigned char)ATTRIBUTE_EXITS;
    cubin_put(&written[before + 2u], 2u, 4ull * exit_count);
    for (unsigned int number = 0u; number < exit_count; number += 1u)
    {
        cubin_put(&written[before + ATTRIBUTE_HEADER + (4ull * number)], 4u, exits[number]);
    }
    memcpy(&written[before + ATTRIBUTE_HEADER + (4ull * exit_count)], &bytes[after], size - after);
    return written_size;
}

// the register count in the whole program's info section set for the kernel's symbol
static void cubin_registers_set(unsigned char *bytes, unsigned long long size, unsigned int symbol,
                                unsigned int registers)
{
    unsigned long long value_size = 0ull;
    const unsigned char *const found = cubin_attribute(bytes, size, ATTRIBUTE_REGISTERS, &value_size);
    // the value is the symbol the count belongs to and the count
    if ((found != NULL) && (value_size == 8ull) && (cubin_read(&found[ATTRIBUTE_HEADER], 4u) == symbol))
    {
        cubin_put(&bytes[(unsigned long long)(found - bytes) + ATTRIBUTE_HEADER + 4ull], 4u, registers);
    }
}

int cubin_write(const CubinWrite *args, unsigned char *written, unsigned long long room, unsigned long long *size)
{
    const unsigned char *const pattern = args->pattern;
    const unsigned long long section_table = cubin_read(&pattern[ELF_SHOFF], 8u);
    const unsigned long long section_bytes = cubin_read(&pattern[ELF_SHENTSIZE], 2u);
    const unsigned int sections = (unsigned int)cubin_read(&pattern[ELF_SHNUM], 2u);
    const unsigned long long segment_table = cubin_read(&pattern[ELF_PHOFF], 8u);
    const unsigned long long segment_bytes = cubin_read(&pattern[ELF_PHENTSIZE], 2u);
    const unsigned int segments = (unsigned int)cubin_read(&pattern[ELF_PHNUM], 2u);
    const unsigned int strings_index = (unsigned int)cubin_read(&pattern[ELF_SHSTRNDX], 2u);
    if ((sections == 0u) || (sections > CUBIN_SECTIONS) || (args->pattern_size < ELF_HEADER_BYTES))
    {
        printf("  cubin_write: the pattern holds %u sections in %llu bytes\n", sections, args->pattern_size);
        return 0;
    }
    CubinSection kept[CUBIN_SECTIONS];
    for (unsigned int index = 0u; index < sections; index += 1u)
    {
        const unsigned long long at = section_table + ((unsigned long long)index * section_bytes);
        kept[index].was_at = at;
        kept[index].was_size = cubin_read(&pattern[at + SECTION_SIZE], 8u);
        kept[index].bytes = &pattern[cubin_read(&pattern[at + SECTION_OFFSET], 8u)];
        kept[index].size = kept[index].was_size;
        kept[index].align = cubin_read(&pattern[at + SECTION_ALIGN], 8u);
        kept[index].goes_at = cubin_read(&pattern[at + SECTION_OFFSET], 8u);
    }
    const unsigned long long strings = cubin_read(&pattern[kept[strings_index].was_at + SECTION_OFFSET], 8u);
    char named[256];
    snprintf(named, sizeof(named), ".text.%s", args->kernel);
    const unsigned int code_index = cubin_section_named(pattern, kept, sections, strings, named);
    snprintf(named, sizeof(named), ".nv.info.%s", args->kernel);
    const unsigned int info_index = cubin_section_named(pattern, kept, sections, strings, named);
    const unsigned int all_index = cubin_section_named(pattern, kept, sections, strings, ".nv.info");
    const unsigned int symbols_index = cubin_section_named(pattern, kept, sections, strings, ".symtab");
    if ((code_index == sections) || (info_index == sections) || (all_index == sections) ||
        (symbols_index == sections))
    {
        printf("  cubin_write: the pattern holds no kernel named %s\n", args->kernel);
        return 0;
    }
    // the kernel's info section and the program's are written into, and the rest of the pattern is carried over
    static unsigned char s_info[4096];
    static unsigned char s_all[4096];
    const unsigned long long info_size =
        cubin_info_write(kept[info_index].bytes, kept[info_index].size, args->exits, args->exit_count, s_info,
                         sizeof(s_info));
    if (info_size == 0ull)
    {
        printf("  cubin_write: %s holds no exit offsets to write\n", named);
        return 0;
    }
    if (kept[all_index].size > sizeof(s_all))
    {
        printf("  cubin_write: .nv.info takes %llu bytes where the room is %llu\n", kept[all_index].size,
               sizeof(s_all));
        return 0;
    }
    memcpy(s_all, kept[all_index].bytes, kept[all_index].size);
    const unsigned int symbol =
        (unsigned int)(cubin_read(&pattern[kept[code_index].was_at + SECTION_INFO], 4u) & 0xffffffu);
    cubin_registers_set(s_all, kept[all_index].size, symbol, args->registers);
    kept[code_index].bytes = args->code;
    kept[code_index].size = args->code_size;
    kept[info_index].bytes = s_info;
    kept[info_index].size = info_size;
    kept[all_index].bytes = s_all;
    // every section laid out again in the order the pattern kept them, each where its alignment puts it
    unsigned long long at = ELF_HEADER_BYTES;
    for (unsigned int index = 1u; index < sections; index += 1u)
    {
        kept[index].goes_at = cubin_round(at, kept[index].align);
        at = kept[index].goes_at + kept[index].size;
    }
    const unsigned long long new_section_table = cubin_round(at, 8ull);
    const unsigned long long new_segment_table = new_section_table + ((unsigned long long)sections * section_bytes);
    const unsigned long long whole = new_segment_table + ((unsigned long long)segments * segment_bytes);
    if (whole > room)
    {
        printf("  cubin_write: the cubin takes %llu bytes where the room is %llu\n", whole, room);
        return 0;
    }
    memset(written, 0, whole);
    memcpy(written, pattern, ELF_HEADER_BYTES);
    cubin_put(&written[ELF_SHOFF], 8u, new_section_table);
    cubin_put(&written[ELF_PHOFF], 8u, new_segment_table);
    for (unsigned int index = 0u; index < sections; index += 1u)
    {
        unsigned char *const header = &written[new_section_table + ((unsigned long long)index * section_bytes)];
        memcpy(header, &pattern[kept[index].was_at], section_bytes);
        if (index != 0u)
        {
            memcpy(&written[kept[index].goes_at], kept[index].bytes, kept[index].size);
            cubin_put(&header[SECTION_OFFSET], 8u, kept[index].goes_at);
            cubin_put(&header[SECTION_SIZE], 8u, kept[index].size);
        }
    }
    // the code section carries the register count in the top byte of its info, beside the symbol it names
    unsigned char *const code_header = &written[new_section_table + ((unsigned long long)code_index * section_bytes)];
    cubin_put(&code_header[SECTION_INFO], 4u,
              ((unsigned long long)args->registers << SECTION_INFO_REGISTERS) | symbol);
    // the kernel's symbol is as long as its code
    unsigned char *const symbol_table = &written[kept[symbols_index].goes_at];
    cubin_put(&symbol_table[((unsigned long long)symbol * SYMBOL_BYTES) + SYMBOL_SIZE], 8u, args->code_size);
    for (unsigned int index = 0u; index < segments; index += 1u)
    {
        const unsigned long long was = segment_table + ((unsigned long long)index * segment_bytes);
        unsigned char *const header = &written[new_segment_table + ((unsigned long long)index * segment_bytes)];
        memcpy(header, &pattern[was], segment_bytes);
        const unsigned long long was_at = cubin_read(&pattern[was + SEGMENT_OFFSET], 8u);
        const unsigned long long was_size = cubin_read(&pattern[was + SEGMENT_FILESIZE], 8u);
        if (was_at == segment_table)
        {
            cubin_put(&header[SEGMENT_OFFSET], 8u, new_segment_table);
            continue;
        }
        // a segment covers a run of sections, and covers the same run where they lie now
        unsigned long long first = whole;
        unsigned long long last = 0ull;
        for (unsigned int index_at = 1u; index_at < sections; index_at += 1u)
        {
            const unsigned long long was_section = cubin_read(&pattern[kept[index_at].was_at + SECTION_OFFSET], 8u);
            if ((was_section >= was_at) && (was_section < (was_at + was_size)))
            {
                first = (kept[index_at].goes_at < first) ? kept[index_at].goes_at : first;
                last = ((kept[index_at].goes_at + kept[index_at].size) > last)
                           ? (kept[index_at].goes_at + kept[index_at].size)
                           : last;
            }
        }
        if (last > first)
        {
            cubin_put(&header[SEGMENT_OFFSET], 8u, first);
            cubin_put(&header[SEGMENT_FILESIZE], 8u, last - first);
            cubin_put(&header[SEGMENT_MEMSIZE], 8u, last - first);
        }
    }
    *size = whole;
    return 1;
}
