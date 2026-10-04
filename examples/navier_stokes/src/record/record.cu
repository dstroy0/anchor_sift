// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// record.cu: a run's record (record.h)
#include "record.h"

FILE *record_open(const char *cfg_path, const RunCfg *cfg, const char *member)
{
    std::string name;
    if (run_cfg_text(cfg, member, &name) == 0)
    {
        return NULL;
    }
    const std::string from = cfg_path;
    const size_t slash = from.find_last_of("/\\");
    const std::string path = (slash == std::string::npos) ? name : (from.substr(0u, slash + 1u) + name);
    FILE *const file = fopen(path.c_str(), "wb");
    if (file == NULL)
    {
        return NULL;
    }
    fwrite(cfg->text.data(), 1u, cfg->text.size(), file);
    if (cfg->text.empty() || (cfg->text.back() != '\n'))
    {
        fputc('\n', file);
    }
    return file;
}

void record_form(FILE *file, const char *name, const AtomForm &form, const AtomBook *book)
{
    fprintf(file, "form %s %zu\n", name, atom_form_terms(form));
    atom_form_write(file, form, book->names);
}

void record_text(FILE *file, const char *text)
{
    fputs(text, file);
    fputc('\n', file);
}

int record_close(FILE *file)
{
    const int written = ferror(file) == 0;
    return (fclose(file) == 0) && written;
}

int record_short(void)
{
    return s_sim_rational_wide != 0;
}
