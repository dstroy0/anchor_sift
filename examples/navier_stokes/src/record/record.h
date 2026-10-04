// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// record.h: a run's record, the cfg text and every form written whole
#ifndef RECORD_H
#define RECORD_H

// A record is plain text. It opens with the cfg as it was read, then each form: a line "form <name> <terms>", then
// one term per line, its coefficient as the exact numerator and denominator in decimal, "e^(<q>)" where the power of
// e is not 0, and each atom by its name with "^<k>" where its power passes 1. Nothing is truncated; two runs that give
// the same forms give the same bytes.

#include "atom_form.h"
#include "run_cfg.h"

#include <stdio.h>

// the record at the cfg's member `member`, a path from the directory the cfg is in, opened and the cfg written into
// it: the file, or NULL where the member is missing or the file does not open
FILE *record_open(const char *cfg_path, const RunCfg *cfg, const char *member);

// one form, its terms in the form's own order
void record_form(FILE *file, const char *name, const AtomForm &form, const AtomBook *book);

// one line of text as it is given
void record_text(FILE *file, const char *text);

// the record closed: 1 where every byte was written
int record_close(FILE *file);

// 1 where a value in this module outgrew the build's width
int record_short(void);

#endif
