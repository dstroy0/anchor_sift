// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The device's tessera (tessera_device.h): the ledger's decisions made on the device by one thread, from the source
// the host daemon's ledger makes them by (tessera_ledger_core.h).
#include "tessera_device.h"
#include "tessera_ledger_core.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

// the calls from `first` made in order by one thread, each answered, until one the ledger's rooms cannot take:
// `stopped` is that call, or `count` where every call was made
__global__ void tessera_device_run(TesseraLedger *ledger, const TesseraCall *calls, unsigned long long first,
                                   unsigned long long count, TesseraAnswer *answers, unsigned long long *stopped)
{
    unsigned long long at = first;
    while (at < count)
    {
        tessera_core_call(ledger, &calls[at], &answers[at]);
        if (answers[at].full != 0)
        {
            break;
        }
        at += 1ull;
    }
    *stopped = at;
}

// `items` on the device grown to hold `wanted` of `size` bytes each, its room doubled until it does, and the `count`
// it held copied into the grown room
static int tessera_device_grow(void **items, unsigned long long *room, unsigned long long count,
                               unsigned long long wanted, size_t size)
{
    if (wanted <= *room)
    {
        return 1;
    }
    unsigned long long grown_room = (*room == 0ull) ? 1ull : *room;
    while (grown_room < wanted)
    {
        grown_room *= 2ull;
    }
    void *grown = NULL;
    if (cudaMalloc(&grown, (size_t)grown_room * size) != cudaSuccess)
    {
        return 0;
    }
    if ((count != 0ull) && (cudaMemcpy(grown, *items, (size_t)count * size, cudaMemcpyDeviceToDevice) != cudaSuccess))
    {
        cudaFree(grown);
        return 0;
    }
    cudaFree(*items);
    *items = grown;
    *room = grown_room;
    return 1;
}

// each room of the device's ledger, held on the host as `held`, grown to the most a call of `kind` can add
static int tessera_device_room(TesseraLedger *held, TesseraCallKind kind)
{
    const TesseraRooms rooms = tessera_core_rooms(held, kind);
    return tessera_device_grow((void **)&held->jobs, &held->job_room, held->job_count, rooms.jobs, sizeof(TesseraJob))
        && tessera_device_grow((void **)&held->history, &held->history_room, held->history_count, rooms.history,
                               sizeof(TesseraHistory))
        && tessera_device_grow((void **)&held->heap, &held->heap_room, held->heap_count, rooms.heap,
                               sizeof(TesseraDeadline));
}

int tessera_device_open(TesseraDevice *device, unsigned long long room)
{
    memset(device, 0, sizeof(*device));
    TesseraLedger *const held = &device->held;
    held->next_identity = 1ull;
    const unsigned long long first_room = (room == 0ull) ? 1ull : room;
    const int laid
        = tessera_device_grow((void **)&held->jobs, &held->job_room, 0ull, first_room, sizeof(TesseraJob))
       && tessera_device_grow((void **)&held->history, &held->history_room, 0ull, first_room, sizeof(TesseraHistory))
       && tessera_device_grow((void **)&held->heap, &held->heap_room, 0ull, first_room, sizeof(TesseraDeadline))
       && (cudaMalloc((void **)&device->ledger, sizeof(TesseraLedger)) == cudaSuccess)
       && (cudaMemcpy(device->ledger, held, sizeof(TesseraLedger), cudaMemcpyHostToDevice) == cudaSuccess);
    if (!laid)
    {
        tessera_device_close(device);
    }
    return laid;
}

void tessera_device_close(TesseraDevice *device)
{
    cudaFree(device->held.jobs);
    cudaFree(device->held.history);
    cudaFree(device->held.heap);
    cudaFree(device->ledger);
    memset(device, 0, sizeof(*device));
}

int tessera_device_calls(TesseraDevice *device, const TesseraCall *calls, unsigned long long count,
                         TesseraAnswer *answers)
{
    if (count == 0ull)
    {
        return 1;
    }
    TesseraCall *device_calls = NULL;
    TesseraAnswer *device_answers = NULL;
    unsigned long long *stopped = NULL;
    int ok = (cudaMalloc((void **)&device_calls, (size_t)count * sizeof(TesseraCall)) == cudaSuccess)
          && (cudaMalloc((void **)&device_answers, (size_t)count * sizeof(TesseraAnswer)) == cudaSuccess)
          && (cudaMalloc((void **)&stopped, sizeof(unsigned long long)) == cudaSuccess)
          && (cudaMemcpy(device_calls, calls, (size_t)count * sizeof(TesseraCall), cudaMemcpyHostToDevice)
              == cudaSuccess);
    unsigned long long first = 0ull;
    while (ok && (first < count))
    {
        tessera_device_run<<<1, 1>>>(device->ledger, device_calls, first, count, device_answers, stopped);
        unsigned long long reached = count;
        ok = (cudaGetLastError() == cudaSuccess)
          && (cudaMemcpy(&reached, stopped, sizeof(reached), cudaMemcpyDeviceToHost) == cudaSuccess)
          && (cudaMemcpy(&device->held, device->ledger, sizeof(TesseraLedger), cudaMemcpyDeviceToHost) == cudaSuccess);
        if (ok && (reached < count))
        {
            // the call at `reached` could add more than the ledger's rooms hold: each is grown to the most it can
            // add, and the run goes on from that call, which the ledger then takes
            ok = tessera_device_room(&device->held, calls[reached].kind)
              && (cudaMemcpy(device->ledger, &device->held, sizeof(TesseraLedger), cudaMemcpyHostToDevice)
                  == cudaSuccess);
        }
        first = reached;
    }
    ok = ok
      && (cudaMemcpy(answers, device_answers, (size_t)count * sizeof(TesseraAnswer), cudaMemcpyDeviceToHost)
          == cudaSuccess);
    cudaFree(device_calls);
    cudaFree(device_answers);
    cudaFree(stopped);
    return ok;
}

int tessera_device_read(const TesseraDevice *device, TesseraLedger *copy)
{
    TesseraLedger held;
    if (cudaMemcpy(&held, device->ledger, sizeof(held), cudaMemcpyDeviceToHost) != cudaSuccess)
    {
        memset(copy, 0, sizeof(*copy));
        return 0;
    }
    *copy = held;
    // one more of each than it holds, and an empty room is not a null pointer
    copy->job_room = held.job_count + 1ull;
    copy->history_room = held.history_count + 1ull;
    copy->heap_room = held.heap_count + 1ull;
    copy->jobs = (TesseraJob *)malloc((size_t)copy->job_room * sizeof(TesseraJob));
    copy->history = (TesseraHistory *)malloc((size_t)copy->history_room * sizeof(TesseraHistory));
    copy->heap = (TesseraDeadline *)malloc((size_t)copy->heap_room * sizeof(TesseraDeadline));
    const int read
        = (copy->jobs != NULL) && (copy->history != NULL) && (copy->heap != NULL)
       && (cudaMemcpy(copy->jobs, held.jobs, (size_t)held.job_count * sizeof(TesseraJob), cudaMemcpyDeviceToHost)
           == cudaSuccess)
       && (cudaMemcpy(copy->history, held.history, (size_t)held.history_count * sizeof(TesseraHistory),
                      cudaMemcpyDeviceToHost)
           == cudaSuccess)
       && (cudaMemcpy(copy->heap, held.heap, (size_t)held.heap_count * sizeof(TesseraDeadline),
                      cudaMemcpyDeviceToHost)
           == cudaSuccess);
    if (!read)
    {
        free(copy->jobs);
        free(copy->history);
        free(copy->heap);
        memset(copy, 0, sizeof(*copy));
    }
    return read;
}
