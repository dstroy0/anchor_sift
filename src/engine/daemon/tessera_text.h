// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef TESSERA_TEXT_H
#define TESSERA_TEXT_H

#include "tessera.h"
#include "scriptura.h"

#ifdef __cplusplus
extern "C" {
#endif

int tessera_text_staged(ScripturaLine *line, const char *text);

void tessera_bytes_hex(ScripturaLine *line, const unsigned char *bytes, unsigned int count);

#ifdef __cplusplus
}
#endif

#endif
