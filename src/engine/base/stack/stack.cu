// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "stack.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

#define STACK_UNCACHED_BLOCK (64ull << 20u)

#define STACK_UNCACHED_ALIGN 4096ull

extern "C" FILE *stack_open(const char *path, unsigned int header[4])
{
    FILE *const file = fopen(path, "rb");
    unsigned int words[5] = {0u, 0u, 0u, 0u, 0u};
    if ((file == NULL) || (fread(words, sizeof(unsigned int), 5u, file) != 5u))
    {
        if (file != NULL)
        {
            fclose(file);
        }
        return NULL;
    }
    memcpy(header, words, 4u * sizeof(unsigned int));
    return file;
}

extern "C" int stack_upload(const char *path, unsigned long long extent[4], unsigned short **device_lanes)
{
    unsigned int header[4] = {0u, 0u, 0u, 0u};
    FILE *const stack = stack_open(path, header);
    for (unsigned int axis = 0u; axis < 4u; axis += 1u)
    {
        extent[axis] = header[axis];
    }
    const size_t lanes = (size_t)(extent[0] * extent[1] * extent[2] * extent[3]);
    unsigned short *const volume = (unsigned short *)malloc((lanes + 1u) * sizeof(unsigned short));
    *device_lanes = NULL;
    const int good = (stack != NULL) && (volume != NULL) && (fread(volume, sizeof(unsigned short), lanes, stack) == lanes)
        && (cudaMalloc((void **)device_lanes, lanes * sizeof(unsigned short)) == cudaSuccess)
        && (cudaMemcpy(*device_lanes, volume, lanes * sizeof(unsigned short), cudaMemcpyHostToDevice) == cudaSuccess);
    if (stack != NULL)
    {
        fclose(stack);
    }
    free(volume);
    return good;
}

extern "C" long long stack_file_size(const char *path)
{
#ifdef _WIN32
    WIN32_FILE_ATTRIBUTE_DATA held;
    if ((path == NULL) || (GetFileAttributesExA(path, GetFileExInfoStandard, &held) == 0)
     || ((held.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0u))
    {
        return ENGINE_BYTES_REFUSED;
    }
    return (long long)(((unsigned long long)held.nFileSizeHigh << 32u) | (unsigned long long)held.nFileSizeLow);
#else
    struct stat status;
    if ((path == NULL) || (stat(path, &status) != 0) || !S_ISREG(status.st_mode))
    {
        return ENGINE_BYTES_REFUSED;
    }
    return (long long)status.st_size;
#endif
}

extern "C" long long stack_file_read(const EngineFileRange *range)
{
    if ((range == NULL) || (range->path == NULL) || ((range->out == NULL) && (range->bytes != 0ull)))
    {
        return ENGINE_BYTES_REFUSED;
    }
    const unsigned long long first = range->offset;
    const unsigned long long last = range->offset + range->bytes;
    const unsigned long long start = first & ~(STACK_UNCACHED_ALIGN - 1ull);
    const unsigned long long span = ((last - start) + STACK_UNCACHED_ALIGN - 1ull) & ~(STACK_UNCACHED_ALIGN - 1ull);
    const unsigned long long block = (span < STACK_UNCACHED_BLOCK) ? ((span != 0ull) ? span : STACK_UNCACHED_ALIGN)
                                                                    : STACK_UNCACHED_BLOCK;
#ifdef _WIN32
    HANDLE const file = CreateFileA(range->path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING,
                                    FILE_FLAG_NO_BUFFERING | FILE_FLAG_SEQUENTIAL_SCAN, NULL);
    unsigned char *const buffer = (unsigned char *)VirtualAlloc(NULL, (SIZE_T)block, MEM_COMMIT | MEM_RESERVE,
                                                                PAGE_READWRITE);
    LARGE_INTEGER seek;
    seek.QuadPart = (LONGLONG)start;
    int good = (file != INVALID_HANDLE_VALUE) && (buffer != NULL) && (SetFilePointerEx(file, seek, NULL, FILE_BEGIN) != 0);
#else
    int descriptor = open(range->path, O_RDONLY | O_DIRECT);
    if (descriptor < 0)
    {
        descriptor = open(range->path, O_RDONLY);
        if (descriptor >= 0)
        {
            (void)posix_fadvise(descriptor, 0, 0, POSIX_FADV_DONTNEED);
        }
    }
    void *aligned = NULL;
    int good = (descriptor >= 0) && (posix_memalign(&aligned, (size_t)STACK_UNCACHED_ALIGN, (size_t)block) == 0);
    unsigned char *const buffer = (unsigned char *)aligned;
#endif
    unsigned long long copied = 0ull;
    int ended = 0;
    for (unsigned long long offset = start; good && (ended == 0) && (offset < last); offset += block)
    {
        unsigned long long got = 0ull;
#ifdef _WIN32
        DWORD read = 0u;
        good = (ReadFile(file, buffer, (DWORD)block, &read, NULL) != 0);
        got = read;
#else
        const ssize_t read = pread(descriptor, buffer, (size_t)block, (off_t)offset);
        good = (read >= 0);
        got = good ? (unsigned long long)read : 0ull;
#endif
        ended = (got < block);
        const unsigned long long from = (offset > first) ? offset : first;
        const unsigned long long reach = ((offset + got) < last) ? (offset + got) : last;
        if (good && (reach > from))
        {
            memcpy(range->out + (from - first), buffer + (from - offset), (size_t)(reach - from));
            copied += reach - from;
        }
    }
#ifdef _WIN32
    if (buffer != NULL)
    {
        VirtualFree(buffer, 0, MEM_RELEASE);
    }
    if (file != INVALID_HANDLE_VALUE)
    {
        CloseHandle(file);
    }
#else
    free(aligned);
    if (descriptor >= 0)
    {
        close(descriptor);
    }
#endif
    return good ? (long long)copied : ENGINE_BYTES_REFUSED;
}

extern "C" int stack_read_uncached(const char *path, unsigned long long lanes, unsigned short *volume)
{
    const unsigned long long first = (unsigned long long)STACK_VOXELS_AT;
    const unsigned long long last = first + (2ull * lanes);
#ifdef _WIN32
    HANDLE const file = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING,
                                    FILE_FLAG_NO_BUFFERING | FILE_FLAG_SEQUENTIAL_SCAN, NULL);
    unsigned char *const buffer = (unsigned char *)VirtualAlloc(NULL, (SIZE_T)STACK_UNCACHED_BLOCK, MEM_COMMIT | MEM_RESERVE,
                                                                PAGE_READWRITE);
    LARGE_INTEGER size;
    size.QuadPart = 0;
    int good = (file != INVALID_HANDLE_VALUE) && (buffer != NULL) && (GetFileSizeEx(file, &size) != 0)
        && ((unsigned long long)size.QuadPart == last);
#else
    int descriptor = open(path, O_RDONLY | O_DIRECT);
    if (descriptor < 0)
    {
        descriptor = open(path, O_RDONLY);
        if (descriptor >= 0)
        {
            (void)posix_fadvise(descriptor, 0, 0, POSIX_FADV_DONTNEED);
        }
    }
    void *aligned = NULL;
    struct stat status;
    int good = (descriptor >= 0) && (fstat(descriptor, &status) == 0) && ((unsigned long long)status.st_size == last)
        && (posix_memalign(&aligned, (size_t)STACK_UNCACHED_ALIGN, (size_t)STACK_UNCACHED_BLOCK) == 0);
    unsigned char *const buffer = (unsigned char *)aligned;
#endif
    for (unsigned long long offset = 0ull; good && (offset < last); offset += STACK_UNCACHED_BLOCK)
    {
        unsigned long long got = 0ull;
#ifdef _WIN32
        DWORD read = 0u;
        good = (ReadFile(file, buffer, (DWORD)STACK_UNCACHED_BLOCK, &read, NULL) != 0);
        got = read;
#else
        const ssize_t read = pread(descriptor, buffer, (size_t)STACK_UNCACHED_BLOCK, (off_t)offset);
        good = (read >= 0);
        got = good ? (unsigned long long)read : 0ull;
#endif
        const unsigned long long from = (offset > first) ? offset : first;
        const unsigned long long to = ((offset + got) < last) ? (offset + got) : last;
        good = good && ((got == STACK_UNCACHED_BLOCK) || ((offset + got) >= last));
        if (good && (to > from))
        {
            memcpy((unsigned char *)volume + (from - first), buffer + (from - offset), (size_t)(to - from));
        }
    }
#ifdef _WIN32
    if (buffer != NULL)
    {
        VirtualFree(buffer, 0, MEM_RELEASE);
    }
    if (file != INVALID_HANDLE_VALUE)
    {
        CloseHandle(file);
    }
#else
    free(aligned);
    if (descriptor >= 0)
    {
        close(descriptor);
    }
#endif
    return good;
}
