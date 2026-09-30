// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// container_same.c: the emitter driven by a layout file against the one with the layout compiled in.
//
//     container_same <layout> <pattern> <part>
//
// The two are given the same pattern, the same code and the same part, and their bytes are compared. Where they
// agree, every offset, width, tag and name the old one held is in the layout file and none of it is lost. This is
// the check that lets the compiled-in one go.
// both emitters are C and their headers carry no linkage of their own, so it is named here
extern "C"
{
#include "container_write.h"
#include "cubin_write.h"
}

#include <cstdio>
#include <cstring>

static unsigned char s_pattern[262144];
static unsigned char s_from_file[262144];
static unsigned char s_from_code[262144];
static unsigned char s_code[65536];

int main(int count, char **arguments)
{
    if (count < 4)
    {
        printf("  container_same <layout> <pattern> <part>\n");
        return 2;
    }
    FILE *const file = fopen(arguments[2], "rb");
    if (file == NULL)
    {
        printf("  the pattern %s could not be read\n", arguments[2]);
        return 1;
    }
    const unsigned long long pattern_size = (unsigned long long)fread(s_pattern, 1u, sizeof(s_pattern), file);
    fclose(file);

    ContainerLayout layout;
    if (!container_layout_read(&layout, arguments[1]))
    {
        return 1;
    }
    printf("  %s holds %u rows\n", arguments[1], layout.rows);

    // code the two are both given: a part of one instruction, all zeroes, which needs no meaning to be laid out
    memset(s_code, 0, sizeof(s_code));
    const unsigned long long code_size = 16ull * 4ull;
    const unsigned int registers = 255u;
    unsigned int exits[4] = {0u, 0u, 0u, 0u};

    ContainerWrite by_file;
    memset(&by_file, 0, sizeof(by_file));
    by_file.layout = &layout;
    by_file.pattern = s_pattern;
    by_file.pattern_size = pattern_size;
    by_file.part = arguments[3];
    by_file.code = s_code;
    by_file.code_size = code_size;
    by_file.registers = registers;
    by_file.exits = exits;
    by_file.exit_count = 0u;
    unsigned long long file_size = 0ull;
    const int file_written = container_write(&by_file, s_from_file, sizeof(s_from_file), &file_size);

    CubinWrite by_code;
    memset(&by_code, 0, sizeof(by_code));
    by_code.pattern = s_pattern;
    by_code.pattern_size = pattern_size;
    by_code.kernel = arguments[3];
    by_code.code = s_code;
    by_code.code_size = code_size;
    by_code.registers = registers;
    by_code.exits = exits;
    by_code.exit_count = 0u;
    unsigned long long code_written_size = 0ull;
    const int code_written = cubin_write(&by_code, s_from_code, sizeof(s_from_code), &code_written_size);

    if ((file_written == 0) || (code_written == 0))
    {
        printf("container same: by file %d, by code %d, one of them wrote nothing\n", file_written, code_written);
        return 1;
    }
    if (file_size != code_written_size)
    {
        printf("container same: by file %llu bytes, by code %llu\n", file_size, code_written_size);
        return 1;
    }
    unsigned long long differed = 0ull;
    unsigned long long first = 0ull;
    for (unsigned long long at = 0ull; at < file_size; at += 1u)
    {
        if (s_from_file[at] != s_from_code[at])
        {
            first = (differed == 0ull) ? at : first;
            differed += 1ull;
        }
    }
    printf("container same: %llu bytes each, %llu differing%s\n", file_size, differed,
           (differed == 0ull) ? ", the layout file holds everything the code held" : "");
    if (differed != 0ull)
    {
        printf("  the first at %llu: by file %02x, by code %02x\n", first, s_from_file[first], s_from_code[first]);
    }
    return (differed == 0ull) ? 0 : 1;
}
