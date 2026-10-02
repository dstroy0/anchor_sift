// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// container_write.c: one container written from another, with new code in it, driven by a layout file
#include "container_write.h"

#include <stdio.h>
#include <string.h>

// what bounds the memory this takes. Neither is the format's to state: a format says where things are, and these
// say how much of it this will carry at once
#define CONTAINER_SECTIONS 64u
#define CONTAINER_ATTRIBUTE_ROOM 4096u

// every place this reads or writes, taken out of the layout once
typedef struct
{
    unsigned long long segment_table, section_table, segment_entry, segment_count;
    unsigned long long section_entry, section_count, strings_index;
    unsigned long long section_name, section_offset, section_size, section_info, section_align;
    unsigned long long segment_offset, segment_file_size, segment_memory_size;
    unsigned long long symbol_size, symbol_bytes;
    unsigned int segment_table_width, section_table_width, segment_entry_width, segment_count_width;
    unsigned int section_entry_width, section_count_width, strings_index_width;
    unsigned int section_name_width, section_offset_width, section_size_width, section_info_width;
    unsigned int section_align_width, segment_offset_width, segment_file_width, segment_memory_width;
    unsigned int symbol_size_width;
    unsigned long long header_bytes, instruction, table_align, table_entry;
    unsigned long long registers_shift, registers_symbol_mask;
    unsigned long long attribute_header, attribute_format_value, attribute_registers, attribute_exits;
} Places;

// a part of the container as this holds it: where it was, the bytes it takes now and how many, and where it goes
typedef struct
{
    unsigned long long was_at;
    const unsigned char *bytes;
    unsigned long long size;
    unsigned long long align;
    unsigned long long goes_at;
} Section;

static unsigned long long value_read(const unsigned char *bytes, unsigned int width)
{
    unsigned long long held = 0ull;
    for (unsigned int at = 0u; at < width; at += 1u)
    {
        held |= ((unsigned long long)bytes[at]) << (8u * at);
    }
    return held;
}

static void value_put(unsigned char *bytes, unsigned int width, unsigned long long value)
{
    for (unsigned int at = 0u; at < width; at += 1u)
    {
        bytes[at] = (unsigned char)((value >> (8u * at)) & 0xffull);
    }
}

static unsigned long long rounded(unsigned long long at, unsigned long long align)
{
    return ((align > 1ull) && ((at % align) != 0ull)) ? (at + (align - (at % align))) : at;
}

// every place the emitter uses, taken out of `layout`. 1, or 0 with the missing row named by the layout itself
static int places_read(const ContainerLayout *layout, Places *places)
{
    memset(places, 0, sizeof(*places));
    const int held =
        layout_field(layout, "header.segment_table", &places->segment_table, &places->segment_table_width) &&
        layout_field(layout, "header.section_table", &places->section_table, &places->section_table_width) &&
        layout_field(layout, "header.segment_entry", &places->segment_entry, &places->segment_entry_width) &&
        layout_field(layout, "header.segment_count", &places->segment_count, &places->segment_count_width) &&
        layout_field(layout, "header.section_entry", &places->section_entry, &places->section_entry_width) &&
        layout_field(layout, "header.section_count", &places->section_count, &places->section_count_width) &&
        layout_field(layout, "header.strings_index", &places->strings_index, &places->strings_index_width) &&
        layout_field(layout, "section.name", &places->section_name, &places->section_name_width) &&
        layout_field(layout, "section.offset", &places->section_offset, &places->section_offset_width) &&
        layout_field(layout, "section.size", &places->section_size, &places->section_size_width) &&
        layout_field(layout, "section.info", &places->section_info, &places->section_info_width) &&
        layout_field(layout, "section.align", &places->section_align, &places->section_align_width) &&
        layout_field(layout, "segment.offset", &places->segment_offset, &places->segment_offset_width) &&
        layout_field(layout, "segment.file_size", &places->segment_file_size, &places->segment_file_width) &&
        layout_field(layout, "segment.memory_size", &places->segment_memory_size, &places->segment_memory_width) &&
        layout_field(layout, "symbol.size", &places->symbol_size, &places->symbol_size_width);
    if (!held)
    {
        return 0;
    }
    places->header_bytes = layout_number(layout, "header", 0ull);
    places->symbol_bytes = layout_number(layout, "symbol", 0ull);
    places->instruction = layout_number(layout, "instruction", 0ull);
    places->table_align = layout_number(layout, "table.align", 1ull);
    places->table_entry = layout_number(layout, "table.entry", 8ull);
    places->registers_shift = layout_number(layout, "registers.shift", 0ull);
    places->registers_symbol_mask = layout_number(layout, "registers.symbol_mask", 0ull);
    places->attribute_header = layout_number(layout, "attribute.header", 0ull);
    places->attribute_format_value = layout_number(layout, "attribute.format_value", 0ull);
    places->attribute_registers = layout_number(layout, "attribute.registers", 0ull);
    places->attribute_exits = layout_number(layout, "attribute.exits", 0ull);
    if ((places->header_bytes == 0ull) || (places->symbol_bytes == 0ull) || (places->attribute_header == 0ull) ||
        (places->instruction == 0ull))
    {
        printf("  container_write: %s names no header, symbol, attribute or instruction size\n", layout->from);
        return 0;
    }
    return 1;
}

unsigned int container_endings_find(const ContainerLayout *layout, const unsigned char *code,
                                    unsigned long long code_size, unsigned long long ending, unsigned int *exits,
                                    unsigned int room)
{
    const unsigned long long instruction = layout_number(layout, "instruction", 0ull);
    const unsigned long long key = layout_number(layout, "operation.mask", 0xfffull);
    unsigned int found = 0u;
    if (instruction == 0ull)
    {
        return 0u;
    }
    for (unsigned long long at = 0ull; (at + instruction) <= code_size; at += instruction)
    {
        if (((value_read(&code[at], 8u) & key) == (ending & key)) && (found < room))
        {
            exits[found] = (unsigned int)at;
            found += 1u;
        }
    }
    return found;
}

// the section table of `pattern`, with the count and where the names lie
static unsigned long long sections_of(const Places *places, const unsigned char *pattern, unsigned int *count,
                                      unsigned long long *strings, unsigned long long *entry)
{
    const unsigned long long table = value_read(&pattern[places->section_table], places->section_table_width);
    *entry = value_read(&pattern[places->section_entry], places->section_entry_width);
    *count = (unsigned int)value_read(&pattern[places->section_count], places->section_count_width);
    const unsigned long long names =
        table + (value_read(&pattern[places->strings_index], places->strings_index_width) * *entry);
    *strings = value_read(&pattern[names + places->section_offset], places->section_offset_width);
    return table;
}

unsigned int container_registers_read(const ContainerLayout *layout, const unsigned char *pattern, const char *part)
{
    Places places;
    char named[256];
    if (!places_read(layout, &places) || !layout_text(layout, "section.code", part, named, sizeof(named)))
    {
        return 0u;
    }
    unsigned int count = 0u;
    unsigned long long strings = 0ull;
    unsigned long long entry = 0ull;
    const unsigned long long table = sections_of(&places, pattern, &count, &strings, &entry);
    unsigned int found = 0u;
    for (unsigned int index = 0u; index < count; index += 1u)
    {
        const unsigned long long at = table + ((unsigned long long)index * entry);
        const unsigned long long name =
            strings + value_read(&pattern[at + places.section_name], places.section_name_width);
        if (strcmp((const char *)&pattern[name], named) == 0)
        {
            found = (unsigned int)(value_read(&pattern[at + places.section_info], places.section_info_width) >>
                                   places.registers_shift);
        }
    }
    return found;
}

// the place of the section named `name`, or `count` where the pattern holds none
static unsigned int section_named(const Places *places, const unsigned char *pattern, const Section *sections,
                                  unsigned int count, unsigned long long strings, const char *name)
{
    unsigned int found = count;
    for (unsigned int index = 0u; index < count; index += 1u)
    {
        const unsigned long long at =
            strings + value_read(&pattern[sections[index].was_at + places->section_name], places->section_name_width);
        found = (strcmp((const char *)&pattern[at], name) == 0) ? index : found;
    }
    return found;
}

// the attribute `attribute` of these bytes, or NULL where they hold none; its value's size through `value_size`
static const unsigned char *attribute_of(const Places *places, const unsigned char *bytes, unsigned long long size,
                                         unsigned long long attribute, unsigned long long *value_size)
{
    unsigned long long at = 0ull;
    while ((at + places->attribute_header) <= size)
    {
        const unsigned long long format = bytes[at];
        const unsigned long long named = bytes[at + 1u];
        const unsigned long long kept =
            (format == places->attribute_format_value) ? value_read(&bytes[at + 2u], 2u) : 0ull;
        if (named == attribute)
        {
            *value_size = kept;
            return &bytes[at];
        }
        at += places->attribute_header + kept;
    }
    *value_size = 0ull;
    return NULL;
}

// The part's attributes written with the endings this code holds, into `written`; its size, or 0 where the section
// carries no ending attribute and nothing was written
static unsigned long long attributes_written(const Places *places, const unsigned char *bytes,
                                             unsigned long long size, const unsigned int *exits,
                                             unsigned int exit_count, unsigned char *written, unsigned long long room)
{
    unsigned long long value_size = 0ull;
    const unsigned char *const found = attribute_of(places, bytes, size, places->attribute_exits, &value_size);
    if (found == NULL)
    {
        // A section with no ending attribute belongs to something the target calls and returns from, not to
        // something it enters: an entry ends where the container says it ends, and the other ends on its own.
        // Carrying the section over untouched is right for that and only for that
        if (exit_count != 0u)
        {
            return 0ull;
        }
        if (size > room)
        {
            printf("  container_write: the attributes take %llu bytes where the room is %llu\n", size, room);
            return 0ull;
        }
        memcpy(written, bytes, size);
        return size;
    }
    const unsigned long long before = (unsigned long long)(found - bytes);
    const unsigned long long after = before + places->attribute_header + value_size;
    const unsigned long long whole =
        before + places->attribute_header + (4ull * exit_count) + (size - after);
    if (whole > room)
    {
        printf("  container_write: the attributes take %llu bytes where the room is %llu\n", whole, room);
        return 0ull;
    }
    memcpy(written, bytes, before);
    written[before] = (unsigned char)places->attribute_format_value;
    written[before + 1u] = (unsigned char)places->attribute_exits;
    value_put(&written[before + 2u], 2u, 4ull * exit_count);
    for (unsigned int number = 0u; number < exit_count; number += 1u)
    {
        value_put(&written[before + places->attribute_header + (4ull * number)], 4u, exits[number]);
    }
    memcpy(&written[before + places->attribute_header + (4ull * exit_count)], &bytes[after], size - after);
    return whole;
}

// the register count in the whole container's attributes, set for the part's symbol
static void registers_set(const Places *places, unsigned char *bytes, unsigned long long size, unsigned int symbol,
                          unsigned int registers)
{
    unsigned long long value_size = 0ull;
    const unsigned char *const found = attribute_of(places, bytes, size, places->attribute_registers, &value_size);
    if ((found != NULL) && (value_size == 8ull) &&
        (value_read(&found[places->attribute_header], 4u) == (unsigned long long)symbol))
    {
        value_put(&bytes[(unsigned long long)(found - bytes) + places->attribute_header + 4ull], 4u, registers);
    }
}

int container_write(const ContainerWrite *args, unsigned char *written, unsigned long long room,
                    unsigned long long *size)
{
    Places places;
    if (!places_read(args->layout, &places))
    {
        return 0;
    }
    const unsigned char *const pattern = args->pattern;
    unsigned int sections = 0u;
    unsigned long long strings = 0ull;
    unsigned long long section_entry = 0ull;
    const unsigned long long section_table = sections_of(&places, pattern, &sections, &strings, &section_entry);
    const unsigned long long segment_table = value_read(&pattern[places.segment_table], places.segment_table_width);
    const unsigned long long segment_entry = value_read(&pattern[places.segment_entry], places.segment_entry_width);
    const unsigned int segments = (unsigned int)value_read(&pattern[places.segment_count], places.segment_count_width);
    if ((sections == 0u) || (sections > CONTAINER_SECTIONS) || (args->pattern_size < places.header_bytes))
    {
        printf("  container_write: the pattern holds %u sections in %llu bytes\n", sections, args->pattern_size);
        return 0;
    }
    Section kept[CONTAINER_SECTIONS];
    for (unsigned int index = 0u; index < sections; index += 1u)
    {
        const unsigned long long at = section_table + ((unsigned long long)index * section_entry);
        kept[index].was_at = at;
        kept[index].size = value_read(&pattern[at + places.section_size], places.section_size_width);
        kept[index].goes_at = value_read(&pattern[at + places.section_offset], places.section_offset_width);
        kept[index].bytes = &pattern[kept[index].goes_at];
        kept[index].align = value_read(&pattern[at + places.section_align], places.section_align_width);
    }
    char named[256];
    unsigned int code_index = sections;
    unsigned int part_info = sections;
    unsigned int all_info = sections;
    unsigned int symbols = sections;
    if (layout_text(args->layout, "section.code", args->part, named, sizeof(named)))
    {
        code_index = section_named(&places, pattern, kept, sections, strings, named);
    }
    if (layout_text(args->layout, "section.part_info", args->part, named, sizeof(named)))
    {
        part_info = section_named(&places, pattern, kept, sections, strings, named);
    }
    if (layout_text(args->layout, "section.program_info", NULL, named, sizeof(named)))
    {
        all_info = section_named(&places, pattern, kept, sections, strings, named);
    }
    if (layout_text(args->layout, "section.symbols", NULL, named, sizeof(named)))
    {
        symbols = section_named(&places, pattern, kept, sections, strings, named);
    }
    if ((code_index == sections) || (part_info == sections) || (all_info == sections) || (symbols == sections))
    {
        printf("  container_write: the pattern holds no part named %s\n", args->part);
        return 0;
    }
    static unsigned char s_part[CONTAINER_ATTRIBUTE_ROOM];
    static unsigned char s_all[CONTAINER_ATTRIBUTE_ROOM];
    const unsigned long long part_size = attributes_written(&places, kept[part_info].bytes, kept[part_info].size,
                                                            args->exits, args->exit_count, s_part, sizeof(s_part));
    if (part_size == 0ull)
    {
        printf("  container_write: %s holds no endings to write\n", args->part);
        return 0;
    }
    if (kept[all_info].size > sizeof(s_all))
    {
        printf("  container_write: the container's attributes take %llu bytes where the room is %llu\n",
               kept[all_info].size, (unsigned long long)sizeof(s_all));
        return 0;
    }
    memcpy(s_all, kept[all_info].bytes, kept[all_info].size);
    const unsigned int symbol =
        (unsigned int)(value_read(&pattern[kept[code_index].was_at + places.section_info], places.section_info_width) &
                       places.registers_symbol_mask);
    registers_set(&places, s_all, kept[all_info].size, symbol, args->registers);
    kept[code_index].bytes = args->code;
    kept[code_index].size = args->code_size;
    kept[part_info].bytes = s_part;
    kept[part_info].size = part_size;
    kept[all_info].bytes = s_all;

    unsigned long long at = places.header_bytes;
    for (unsigned int index = 1u; index < sections; index += 1u)
    {
        kept[index].goes_at = rounded(at, kept[index].align);
        at = kept[index].goes_at + kept[index].size;
    }
    const unsigned long long new_sections = rounded(at, places.table_align);
    const unsigned long long new_segments = new_sections + ((unsigned long long)sections * section_entry);
    const unsigned long long whole = new_segments + ((unsigned long long)segments * segment_entry);
    if (whole > room)
    {
        printf("  container_write: the container takes %llu bytes where the room is %llu\n", whole, room);
        return 0;
    }
    memset(written, 0, whole);
    memcpy(written, pattern, places.header_bytes);
    value_put(&written[places.section_table], places.section_table_width, new_sections);
    value_put(&written[places.segment_table], places.segment_table_width, new_segments);
    for (unsigned int index = 0u; index < sections; index += 1u)
    {
        unsigned char *const header = &written[new_sections + ((unsigned long long)index * section_entry)];
        memcpy(header, &pattern[kept[index].was_at], section_entry);
        if (index != 0u)
        {
            memcpy(&written[kept[index].goes_at], kept[index].bytes, kept[index].size);
            value_put(&header[places.section_offset], places.section_offset_width, kept[index].goes_at);
            value_put(&header[places.section_size], places.section_size_width, kept[index].size);
        }
    }
    unsigned char *const code_header = &written[new_sections + ((unsigned long long)code_index * section_entry)];
    value_put(&code_header[places.section_info], places.section_info_width,
              ((unsigned long long)args->registers << places.registers_shift) | symbol);
    unsigned char *const symbol_table = &written[kept[symbols].goes_at];
    value_put(&symbol_table[((unsigned long long)symbol * places.symbol_bytes) + places.symbol_size],
              places.symbol_size_width, args->code_size);
    for (unsigned int index = 0u; index < segments; index += 1u)
    {
        const unsigned long long was = segment_table + ((unsigned long long)index * segment_entry);
        unsigned char *const header = &written[new_segments + ((unsigned long long)index * segment_entry)];
        memcpy(header, &pattern[was], segment_entry);
        const unsigned long long was_at = value_read(&pattern[was + places.segment_offset], places.segment_offset_width);
        const unsigned long long was_size =
            value_read(&pattern[was + places.segment_file_size], places.segment_file_width);
        if (was_at == segment_table)
        {
            value_put(&header[places.segment_offset], places.segment_offset_width, new_segments);
            continue;
        }
        // a segment covers a run of sections, and covers the same run where they lie now
        unsigned long long first = whole;
        unsigned long long last = 0ull;
        for (unsigned int index_at = 1u; index_at < sections; index_at += 1u)
        {
            const unsigned long long was_section =
                value_read(&pattern[kept[index_at].was_at + places.section_offset], places.section_offset_width);
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
            value_put(&header[places.segment_offset], places.segment_offset_width, first);
            value_put(&header[places.segment_file_size], places.segment_file_width, last - first);
            value_put(&header[places.segment_memory_size], places.segment_memory_width, last - first);
        }
    }
    *size = whole;
    return 1;
}
