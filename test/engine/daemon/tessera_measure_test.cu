// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "tessera.h"
#include "tessera_measure.h"

#include <cuda_runtime.h>
#include <stdio.h>
#include <string.h>

#if defined(_WIN32)
#define NOMINMAX
#include <windows.h>
#else
#include <sys/wait.h>
#include <unistd.h>
#endif

#define MEASURE_TEST_BYTES (256ull << 20u)

static unsigned long long measure_test_self(void)
{
#if defined(_WIN32)
    return GetCurrentProcessId();
#else
    // a pid is positive, held whole in an unsigned long long
    return (unsigned long long)getpid();
#endif
}

static int measure_test_child_ends(unsigned long long *failed)
{
#if defined(_WIN32)
    STARTUPINFOA startup;
    PROCESS_INFORMATION child;
    memset(&startup, 0, sizeof(startup));
    startup.cb = sizeof(startup);
    memset(&child, 0, sizeof(child));
    char command[] = "cmd.exe /c exit 0";
    if (!CreateProcessA(NULL, command, NULL, NULL, FALSE, CREATE_SUSPENDED | CREATE_NO_WINDOW, NULL, NULL, &startup, &child))
    {
        *failed += 1ull;
        return 1;
    }
    TesseraProcess *const held = tessera_process_hold(child.dwProcessId);
    const int lived = (held != NULL) && tessera_process_lives(held);
    ResumeThread(child.hThread);
    WaitForSingleObject(child.hProcess, INFINITE);
    const int ended = (held != NULL) && !tessera_process_lives(held);
    tessera_process_release(held);
    CloseHandle(child.hThread);
    CloseHandle(child.hProcess);
#else
    int ready[2];
    if (pipe(ready) != 0)
    {
        *failed += 1ull;
        return 1;
    }
    const pid_t child = fork();
    if (child == 0)
    {
        char wait_byte = 0;
        close(ready[1]);
        const ssize_t read_bytes = read(ready[0], &wait_byte, 1u);
        _exit((read_bytes >= 0) ? 0 : 1);
    }
    close(ready[0]);
    // a pid is positive, held whole in an unsigned long long
    TesseraProcess *const held = tessera_process_hold((unsigned long long)child);
    const int lived = (held != NULL) && tessera_process_lives(held);
    close(ready[1]);
    int status = 0;
    waitpid(child, &status, 0);
    const int ended = (held != NULL) && !tessera_process_lives(held);
    tessera_process_release(held);
#endif
    printf("  a child held: lived %d, then ended %d\n", lived, ended);
    *failed += lived ? 0ull : 1ull;
    *failed += ended ? 0ull : 1ull;
    return 2;
}

int main(void)
{
    unsigned long long failed = 0ull;
    unsigned long long cases = 0ull;
    cudaDeviceProp properties;
    if (cudaGetDeviceProperties(&properties, 0) != cudaSuccess)
    {
        printf("  no device answered; the measure test needs one\n");
        return 1;
    }
    unsigned char device[TESSERA_DEVICE_BYTES];
    memcpy(device, properties.uuid.bytes, TESSERA_DEVICE_BYTES);
    unsigned long long luid = 0ull;
#if defined(_WIN32)
    LUID adapter;
    memcpy(&adapter, properties.luid, sizeof(adapter));
    // the high part is a signed long whose bits form the upper word of the luid
    luid = ((unsigned long long)(unsigned long)adapter.HighPart << 32u) | adapter.LowPart;
#endif
    TesseraMeasure *const measure = tessera_measure_open(device, luid);
    failed += (measure != NULL) ? 0ull : 1ull;
    cases += 1ull;
    if (measure == NULL)
    {
        printf("  the measure did not open\n  tessera measure: %llu failed\n", failed);
        return 1;
    }
    unsigned long long capacity = 0ull;
    unsigned long long in_use_before = 0ull;
    const int read_device = tessera_measure_device(measure, &capacity, &in_use_before);
    failed += (read_device && (capacity >= properties.totalGlobalMem) && (in_use_before <= capacity)) ? 0ull : 1ull;
    cases += 1ull;
    // under WSL no pid is read from outside, so this process reads itself, as a job's client does there
    const int reported = tessera_measure_reported(measure) && tessera_self_paravirtual();
    failed += (tessera_measure_reported(measure) == tessera_self_paravirtual()) ? 0ull : 1ull;
    cases += 1ull;
    unsigned long long used_before = 0ull;
    const int read_before = reported ? tessera_self_measure(luid, &used_before)
                                     : tessera_measure_process(measure, measure_test_self(), &used_before);
    void *block = NULL;
    const int allocated = cudaMalloc(&block, MEASURE_TEST_BYTES) == cudaSuccess;
    const int touched = allocated && (cudaMemset(block, 0x5A, MEASURE_TEST_BYTES) == cudaSuccess)
                     && (cudaDeviceSynchronize() == cudaSuccess);
    unsigned long long used_after = 0ull;
    const int read_after = reported ? tessera_self_measure(luid, &used_after)
                                    : tessera_measure_process(measure, measure_test_self(), &used_after);
    unsigned long long in_use_after = 0ull;
    const int read_device_after = tessera_measure_device(measure, &capacity, &in_use_after);
    failed += (read_before && read_after && touched && (used_after >= used_before + MEASURE_TEST_BYTES)) ? 0ull : 1ull;
    cases += 1ull;
    failed += (read_device_after && (in_use_after >= in_use_before + MEASURE_TEST_BYTES)) ? 0ull : 1ull;
    cases += 1ull;
    unsigned long long used_other = 0ull;
    const int read_other = tessera_measure_process(measure, 0xFFFFFFF0ull, &used_other);
    // a pid with no device work reads 0; under WSL no pid is read from outside at all
    failed += ((reported ? !read_other : read_other) && (used_other == 0ull)) ? 0ull : 1ull;
    cases += 1ull;
    // the runtime's byte count is a size_t, held whole in an unsigned long long
    printf("  device %llu bytes (the runtime says %llu), in use %llu then %llu\n", capacity,
           (unsigned long long)properties.totalGlobalMem, in_use_before, in_use_after);
    printf("  this process %llu bytes, then %llu after %llu allocated (%s)\n", used_before, used_after,
           MEASURE_TEST_BYTES, reported ? "read by itself: WSL reports each process's own bytes" : "read by pid");
    cudaFree(block);
    TesseraProcess *const self = tessera_process_hold(measure_test_self());
    failed += ((self != NULL) && tessera_process_lives(self)) ? 0ull : 1ull;
    cases += 1ull;
    tessera_process_release(self);
    // the count of cases is two, widened
    cases += (unsigned long long)measure_test_child_ends(&failed);
    tessera_measure_close(measure);
    printf("  tessera measure: %llu cases, %llu failed\n", cases, failed);
    return (failed == 0ull) ? 0 : 1;
}
