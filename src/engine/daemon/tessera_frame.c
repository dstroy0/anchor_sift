// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "tessera.h"

#include <string.h>

#define TESSERA_AT_MAGIC 0u
#define TESSERA_AT_VERSION 4u
#define TESSERA_AT_KIND 8u
#define TESSERA_AT_OVERRIDE 12u
#define TESSERA_AT_DEVICE 16u
#define TESSERA_AT_SIGNUM 32u
#define TESSERA_AT_DECLARED 64u
#define TESSERA_AT_HOLDING 72u
#define TESSERA_AT_SWEEP 80u
#define TESSERA_AT_IDLE 88u
#define TESSERA_AT_BYTES 96u
#define TESSERA_AT_MEASURED 104u
#define TESSERA_AT_IDENTITY 112u
#define TESSERA_AT_LUID 120u

_Static_assert(TESSERA_AT_SIGNUM + ENGINE_SIGNUM_BYTES == TESSERA_AT_DECLARED, "tessera: the signum ends where the declared bytes begin");
_Static_assert(TESSERA_AT_LUID + 8u == TESSERA_FRAME_BYTES, "tessera: the luid ends the frame");

static void tessera_put_word(unsigned char *bytes, unsigned int at, unsigned int value)
{
    for (unsigned int byte = 0u; byte < 4u; byte += 1u)
    {
        // one byte of the word, taken from the bottom
        bytes[at + byte] = (unsigned char)((value >> (8u * byte)) & 0xFFu);
    }
}

static void tessera_put_long(unsigned char *bytes, unsigned int at, unsigned long long value)
{
    for (unsigned int byte = 0u; byte < 8u; byte += 1u)
    {
        // one byte of the long, taken from the bottom
        bytes[at + byte] = (unsigned char)((value >> (8u * byte)) & 0xFFull);
    }
}

static unsigned int tessera_get_word(const unsigned char *bytes, unsigned int at)
{
    unsigned int value = 0u;
    for (unsigned int byte = 0u; byte < 4u; byte += 1u)
    {
        value |= (unsigned int)bytes[at + byte] << (8u * byte);
    }
    return value;
}

static unsigned long long tessera_get_long(const unsigned char *bytes, unsigned int at)
{
    unsigned long long value = 0ull;
    for (unsigned int byte = 0u; byte < 8u; byte += 1u)
    {
        value |= (unsigned long long)bytes[at + byte] << (8u * byte);
    }
    return value;
}

static int tessera_kind_known(unsigned int kind)
{
    return ((kind >= TESSERA_ASK_SUBMIT) && (kind <= TESSERA_ASK_MEASURED))
        || ((kind >= TESSERA_TELL_ADMITTED) && (kind <= TESSERA_TELL_REFUSED));
}

int tessera_frame_pack(const TesseraFrame *frame, unsigned char bytes[TESSERA_FRAME_BYTES])
{
    if ((frame->magic != TESSERA_MAGIC) || (frame->version != TESSERA_VERSION) || !tessera_kind_known(frame->kind)
        || (frame->override_budget > 1u))
    {
        return 0;
    }
    tessera_put_word(bytes, TESSERA_AT_MAGIC, frame->magic);
    tessera_put_word(bytes, TESSERA_AT_VERSION, frame->version);
    tessera_put_word(bytes, TESSERA_AT_KIND, frame->kind);
    tessera_put_word(bytes, TESSERA_AT_OVERRIDE, frame->override_budget);
    memcpy(bytes + TESSERA_AT_DEVICE, frame->device, TESSERA_DEVICE_BYTES);
    memcpy(bytes + TESSERA_AT_SIGNUM, frame->signum.bytes, ENGINE_SIGNUM_BYTES);
    tessera_put_long(bytes, TESSERA_AT_DECLARED, frame->declared);
    tessera_put_long(bytes, TESSERA_AT_HOLDING, frame->holding_microseconds);
    tessera_put_long(bytes, TESSERA_AT_SWEEP, frame->sweep_microseconds);
    tessera_put_long(bytes, TESSERA_AT_IDLE, frame->idle_microseconds);
    tessera_put_long(bytes, TESSERA_AT_BYTES, frame->bytes);
    tessera_put_long(bytes, TESSERA_AT_MEASURED, frame->measured);
    tessera_put_long(bytes, TESSERA_AT_IDENTITY, frame->identity);
    tessera_put_long(bytes, TESSERA_AT_LUID, frame->luid);
    return 1;
}

int tessera_frame_unpack(const unsigned char bytes[TESSERA_FRAME_BYTES], TesseraFrame *frame)
{
    TesseraFrame read;
    read.magic = tessera_get_word(bytes, TESSERA_AT_MAGIC);
    read.version = tessera_get_word(bytes, TESSERA_AT_VERSION);
    read.kind = tessera_get_word(bytes, TESSERA_AT_KIND);
    read.override_budget = tessera_get_word(bytes, TESSERA_AT_OVERRIDE);
    memcpy(read.device, bytes + TESSERA_AT_DEVICE, TESSERA_DEVICE_BYTES);
    memcpy(read.signum.bytes, bytes + TESSERA_AT_SIGNUM, ENGINE_SIGNUM_BYTES);
    read.declared = tessera_get_long(bytes, TESSERA_AT_DECLARED);
    read.holding_microseconds = tessera_get_long(bytes, TESSERA_AT_HOLDING);
    read.sweep_microseconds = tessera_get_long(bytes, TESSERA_AT_SWEEP);
    read.idle_microseconds = tessera_get_long(bytes, TESSERA_AT_IDLE);
    read.bytes = tessera_get_long(bytes, TESSERA_AT_BYTES);
    read.measured = tessera_get_long(bytes, TESSERA_AT_MEASURED);
    read.identity = tessera_get_long(bytes, TESSERA_AT_IDENTITY);
    read.luid = tessera_get_long(bytes, TESSERA_AT_LUID);
    if ((read.magic != TESSERA_MAGIC) || (read.version != TESSERA_VERSION) || !tessera_kind_known(read.kind)
        || (read.override_budget > 1u))
    {
        return 0;
    }
    *frame = read;
    return 1;
}
