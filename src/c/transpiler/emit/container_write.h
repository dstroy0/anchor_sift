// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef CONTAINER_WRITE_H
#define CONTAINER_WRITE_H

// One emitter, every container. It reads a layout file and writes what that layout describes.
//
// There is no emitter for one format and another for the next. The work is the same wherever code has to be handed
// to a system: take a container that system already accepts, put the code in, put in the few attributes the code
// decides, and lay the parts out again. Which byte holds the count of sections, what an attribute's tag is, what
// the code's part is called - all of that is rows in a file (container_layout.h, emit/layouts/).
//
// A pattern is a container the target already accepted. Everything in it the emitter does not understand is
// carried over and never invented. A partly known layout is therefore enough to work with: the rows that are
// known say what to change, and the rest of the bytes travel untouched.

#include "container_layout.h"

// what a container is written from
typedef struct
{
    // the layout of this container, read from its file
    const ContainerLayout *layout;
    // a container the target already accepted, and its size
    const unsigned char *pattern;
    unsigned long long pattern_size;
    // the name of the part being written, which the layout's names are built around
    const char *part;
    // the code, and its size
    const unsigned char *code;
    unsigned long long code_size;
    // how many registers the code holds, which the target reads from the container and no instruction declares
    unsigned int registers;
    // where each exit lies in the code, in bytes, which the container carries for it
    const unsigned int *exits;
    unsigned int exit_count;
} ContainerWrite;

// the container written into `written`, which holds `room` bytes, and its size through `size`. 1, or 0 with the
// reason printed, having written nothing
int container_write(const ContainerWrite *args, unsigned char *written, unsigned long long room,
                    unsigned long long *size);

// the offsets in `code` of every instruction whose low word matches `ending`, into `exits` which holds `room` of
// them: the count found. What ends a part is the target's to say and is passed in
unsigned int container_endings_find(const ContainerLayout *layout, const unsigned char *code,
                                    unsigned long long code_size, unsigned long long ending, unsigned int *exits,
                                    unsigned int room);

// how many registers `part` holds in `pattern`, read where the layout says; 0 where the pattern holds no such part
unsigned int container_registers_read(const ContainerLayout *layout, const unsigned char *pattern, const char *part);

#endif
