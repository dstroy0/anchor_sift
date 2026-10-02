// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef TESSERA_DEVICE_H
#define TESSERA_DEVICE_H

// The device's tessera: a ledger laid out in the device's memory, whose decisions the device makes. One thread runs a
// list of calls in order, each tessera_ledger_core.h's decision, the one the host daemon's ledger makes. A call the
// ledger's arrays cannot take stops the run with nothing changed; the host grows the arrays on the device, copying
// what they hold, and the run goes on from that call. The host daemon stays: it builds with no CUDA toolchain and
// makes no CUDA context. This one is built only where nvcc is.

#include "tessera_ledger.h"

#ifdef __cplusplus
extern "C"
{
#endif

    // the ledger on the device, and the host's copy of it as the last run left it, its arrays pointing into the
    // device's memory
    typedef struct
    {
        TesseraLedger *ledger;
        TesseraLedger host_ledger;
    } TesseraDevice;

    // a ledger laid out on the device with `capacity` jobs, kept peaks and deadlines to start; 0 where the device
    // errors on it
    int tessera_device_open(TesseraDevice *device, unsigned long long capacity);

    void tessera_device_close(TesseraDevice *device);

    // `count` calls made in order on the device, each answered in `answers`; 0 where the device errors on the memory or
    // a launch, or the arrays do not grow
    int tessera_device_calls(TesseraDevice *device, const TesseraCall *calls, unsigned long long count,
                             TesseraAnswer *answers);

    // the device's ledger read back into `copy`, a host ledger whose arrays are its counts, released by
    // tessera_ledger_close; 0 where a copy errors
    int tessera_device_read(const TesseraDevice *device, TesseraLedger *copy);

#ifdef __cplusplus
}
#endif

#endif
