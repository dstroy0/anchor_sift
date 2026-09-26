// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef TESSERA_MEASURE_H
#define TESSERA_MEASURE_H

#include "tessera.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TesseraMeasure TesseraMeasure;

typedef struct TesseraProcess TesseraProcess;

TesseraMeasure *tessera_measure_open(const unsigned char device[TESSERA_DEVICE_BYTES], unsigned long long luid);

void tessera_measure_close(TesseraMeasure *measure);

// 1 where no pid is measured from outside (WSL): each job's process reports its own bytes instead
int tessera_measure_reported(const TesseraMeasure *measure);

// 1 for the host's processors: the capacity is the processors jobs are given, and the daemon counts their use from
// what its running jobs report
int tessera_measure_host(const TesseraMeasure *measure);

int tessera_measure_device(TesseraMeasure *measure, unsigned long long *capacity, unsigned long long *in_use);

int tessera_measure_process(TesseraMeasure *measure, unsigned long long pid, unsigned long long *used);

TesseraProcess *tessera_process_hold(unsigned long long pid);

int tessera_process_lives(const TesseraProcess *process);

void tessera_process_release(TesseraProcess *process);

#ifdef __cplusplus
}
#endif

#endif
