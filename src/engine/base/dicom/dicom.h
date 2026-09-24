// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef DICOM_H
#define DICOM_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

int dicom_zip_holds(const EngineIngestTools *tools, const char *path, const char *member);

long dicom_describe(const EngineDescribeRequest *request);

long long dicom_read(const EngineArrayRead *request);

#ifdef __cplusplus
}
#endif

#endif
