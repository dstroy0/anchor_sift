// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// hdf5_io.c: errors, byte order, checksums and file access
#include "hdf5_internal.h"

int hdf5_error(Hdf5File *file, const char *reason)
{
    if (file->reason[0u] == '\0')
    {
        (void)snprintf(file->reason, sizeof(file->reason), "%s", reason);
    }
    return 0;
}

int hdf5_error_number(Hdf5File *file, const char *reason, unsigned long long number)
{
    if (file->reason[0u] == '\0')
    {
        (void)snprintf(file->reason, sizeof(file->reason), "%s %llu", reason, number);
    }
    return 0;
}

Hdf5Walk hdf5_walk_error(Hdf5File *file, const char *reason)
{
    (void)hdf5_error(file, reason);
    return HDF5_WALK_FAILED;
}

void hdf5_report(const Hdf5File *file)
{
    fprintf(stderr, "hdf5: %s: %s\n", (file->path != NULL) ? file->path : "(no path)",
            (file->reason[0u] != '\0') ? file->reason : "a malformed file");
}

unsigned long long hdf5_little(const unsigned char *bytes, unsigned int width)
{
    unsigned long long value = 0ull;
    for (unsigned int place = 0u; place < width; place += 1u)
    {
        value |= ((unsigned long long)bytes[place]) << (8u * place);
    }
    return value;
}

unsigned long long hdf5_big(const unsigned char *bytes, unsigned int width)
{
    unsigned long long value = 0ull;
    for (unsigned int place = 0u; place < width; place += 1u)
    {
        value = (value << 8u) | (unsigned long long)bytes[place];
    }
    return value;
}

unsigned long long hdf5_take(Hdf5Cursor *cursor, unsigned int width)
{
    const int fits = !cursor->broken && (width <= 8u) && ((cursor->length - cursor->at) >= width);
    cursor->broken = !fits;
    const unsigned long long value = fits ? hdf5_little(&cursor->bytes[cursor->at], width) : 0ull;
    cursor->at += fits ? width : 0u;
    return value;
}

const unsigned char *hdf5_span(Hdf5Cursor *cursor, unsigned long long width)
{
    const int fits = !cursor->broken && ((unsigned long long)(cursor->length - cursor->at) >= width);
    cursor->broken = !fits;
    const unsigned char *const span = fits ? &cursor->bytes[cursor->at] : NULL;
    cursor->at += fits ? (size_t)width : 0u;
    return span;
}

unsigned int hdf5_log2(unsigned long long value)
{
    unsigned int bits = 0u;
    while ((value >> bits) > 1ull)
    {
        bits += 1u;
    }
    return bits;
}

int hdf5_power_of_two(unsigned long long value)
{
    return (value != 0ull) && ((value & (value - 1ull)) == 0ull);
}

unsigned long long hdf5_all_ones(unsigned int width)
{
    return (width >= 8u) ? ~0ull : ((1ull << (8u * width)) - 1ull);
}

int hdf5_undefined(const Hdf5File *file, unsigned long long address)
{
    return address == hdf5_all_ones(file->offset_bytes);
}

int hdf5_product(const unsigned long long *values, unsigned int count, unsigned long long start,
                 unsigned long long *product)
{
    unsigned long long total = start;
    for (unsigned int place = 0u; place < count; place += 1u)
    {
        if ((values[place] != 0ull) && (total > (~0ull / values[place])))
        {
            return 0;
        }
        total *= values[place];
    }
    *product = total;
    return 1;
}

static uint32_t hdf5_rotate(uint32_t value, unsigned int turn)
{
    return (value << turn) | (value >> (32u - turn));
}

uint32_t hdf5_lookup3(const unsigned char *bytes, size_t length)
{
    uint32_t first = 0xDEADBEEFu + (uint32_t)length;
    uint32_t second = first;
    uint32_t third = first;
    size_t at = 0u;
    while ((length - at) > 12u)
    {
        first += (uint32_t)hdf5_little(&bytes[at], 4u);
        second += (uint32_t)hdf5_little(&bytes[at + 4u], 4u);
        third += (uint32_t)hdf5_little(&bytes[at + 8u], 4u);
        first -= third;
        first ^= hdf5_rotate(third, 4u);
        third += second;
        second -= first;
        second ^= hdf5_rotate(first, 6u);
        first += third;
        third -= second;
        third ^= hdf5_rotate(second, 8u);
        second += first;
        first -= third;
        first ^= hdf5_rotate(third, 16u);
        third += second;
        second -= first;
        second ^= hdf5_rotate(first, 19u);
        first += third;
        third -= second;
        third ^= hdf5_rotate(second, 4u);
        second += first;
        at += 12u;
    }
    if (length == at)
    {
        return third;
    }
    unsigned char tail[12u];
    memset(tail, 0, sizeof(tail));
    memcpy(tail, &bytes[at], length - at);
    first += (uint32_t)hdf5_little(&tail[0u], 4u);
    second += (uint32_t)hdf5_little(&tail[4u], 4u);
    third += (uint32_t)hdf5_little(&tail[8u], 4u);
    third ^= second;
    third -= hdf5_rotate(second, 14u);
    first ^= third;
    first -= hdf5_rotate(third, 11u);
    second ^= first;
    second -= hdf5_rotate(first, 25u);
    third ^= second;
    third -= hdf5_rotate(second, 16u);
    first ^= third;
    first -= hdf5_rotate(third, 4u);
    second ^= first;
    second -= hdf5_rotate(first, 14u);
    third ^= second;
    third -= hdf5_rotate(second, 24u);
    return third;
}

int hdf5_sealed(const unsigned char *bytes, size_t length)
{
    return (length >= HDF5_SEAL_BYTES) && ((uint32_t)hdf5_little(&bytes[length - HDF5_SEAL_BYTES], 4u) ==
                                           hdf5_lookup3(bytes, length - HDF5_SEAL_BYTES));
}

uint32_t hdf5_fletcher32(const unsigned char *bytes, size_t length)
{
    uint32_t low = 0u;
    uint32_t high = 0u;
    size_t remaining = length / 2u;
    size_t at = 0u;
    while (remaining > 0u)
    {
        const size_t run = (remaining > 360u) ? 360u : remaining;
        remaining -= run;
        for (size_t step = 0u; step < run; step += 1u)
        {
            low += ((uint32_t)bytes[at] << 8u) | (uint32_t)bytes[at + 1u];
            high += low;
            at += 2u;
        }
        low = (low & 0xFFFFu) + (low >> 16u);
        high = (high & 0xFFFFu) + (high >> 16u);
    }
    if ((length % 2u) != 0u)
    {
        low += (uint32_t)bytes[at] << 8u;
        high += low;
        low = (low & 0xFFFFu) + (low >> 16u);
        high = (high & 0xFFFFu) + (high >> 16u);
    }
    low = (low & 0xFFFFu) + (low >> 16u);
    high = (high & 0xFFFFu) + (high >> 16u);
    return (high << 16u) | low;
}

unsigned long long hdf5_bytes_remaining(const Hdf5File *file, unsigned long long address)
{
    const unsigned long long start = file->base + address;
    return ((start < file->base) || (start > file->file_bytes)) ? 0ull : (file->file_bytes - start);
}

int hdf5_fetch(Hdf5File *file, unsigned long long address, unsigned long long bytes, unsigned char *out)
{
    if ((bytes == 0ull) || (bytes > hdf5_bytes_remaining(file, address)))
    {
        return hdf5_error(file, "a structure that lies past the end of the file");
    }
    const EngineFileRange range = {file->path, file->base + address, bytes, out};
    if (file->tools->read(&range) != (long long)bytes)
    {
        return hdf5_error(file, "a file read that came back short");
    }
    return 1;
}

unsigned char *hdf5_load(Hdf5File *file, unsigned long long address, unsigned long long bytes)
{
    const size_t length = (size_t)bytes;
    if (file->budget == 0ull)
    {
        (void)hdf5_error(file, "more reads than any sane file needs");
        return NULL;
    }
    file->budget -= 1ull;
    if (((unsigned long long)length != bytes) || (bytes == 0ull) || (bytes > hdf5_bytes_remaining(file, address)))
    {
        (void)hdf5_error(file, "a structure that lies past the end of the file");
        return NULL;
    }
    unsigned char *const buffer = (unsigned char *)malloc(length);
    if (buffer == NULL)
    {
        (void)hdf5_error(file, "no memory for a structure");
        return NULL;
    }
    if (!hdf5_fetch(file, address, bytes, buffer))
    {
        free(buffer);
        return NULL;
    }
    return buffer;
}
