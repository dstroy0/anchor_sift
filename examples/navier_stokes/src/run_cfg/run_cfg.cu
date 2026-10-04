// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// run_cfg.cu: reading a cfg (run_cfg.h)
#include "run_cfg.h"

int run_cfg_open(const char *path, RunCfg *cfg, ScripturaLine *line)
{
    FILE *const file = fopen(path, "rb");
    if (file == NULL)
    {
        scriptura_text(line, "  the cfg does not open\n");
        return 0;
    }
    cfg->text.clear();
    char block[4096];
    size_t got = 0u;
    while ((got = fread(block, 1u, sizeof(block), file)) > 0u)
    {
        cfg->text.insert(cfg->text.end(), block, block + got);
    }
    fclose(file);
    // a token takes at least one byte of the text
    cfg->tokens.assign(cfg->text.size() + 1u, CfgJsonToken());
    CfgJsonParse parse;
    if (cfg_json_parse(cfg->text.data(), cfg->text.size(), cfg->tokens.data(), (unsigned int)cfg->tokens.size(),
                       &parse) == 0)
    {
        scriptura_text(line, "  the cfg does not parse: ");
        scriptura_text(line, parse.reason);
        scriptura_character(line, '\n');
        return 0;
    }
    return 1;
}

unsigned int run_cfg_find(const RunCfg *cfg, const char *path)
{
    unsigned int at = 0u;
    char part[256];
    const char *walk = path;
    while (*walk != '\0')
    {
        size_t length = 0u;
        while ((walk[length] != '\0') && (walk[length] != '.') && (length + 1u < sizeof(part)))
        {
            part[length] = walk[length];
            length += 1u;
        }
        part[length] = '\0';
        if ((cfg->tokens[at].kind != CFG_JSON_OBJECT) ||
            ((at = cfg_json_member(cfg->text.data(), cfg->tokens.data(), at, part)) == 0u))
        {
            return 0u;
        }
        walk += length;
        if (*walk == '.')
        {
            walk += 1;
        }
    }
    return at;
}

// the decimal string at token `at` read exactly: 1, or 0 where it does not read
static int run_cfg_decimal(const RunCfg *cfg, unsigned int at, SimRational *value)
{
    const CfgJsonToken *const token = &cfg->tokens[at];
    if (token->kind != CFG_JSON_STRING)
    {
        return 0;
    }
    const char *const text = &cfg->text[token->start];
    const size_t length = token->end - token->start;
    const void *const point = memchr(text, '.', length);
    // the point lies inside the text. The places after it number fewer than the text's bytes
    const unsigned int places = (point != NULL) ? (unsigned int)(length - 1u - (size_t)((const char *)point - text)) : 0u;
    if ((anchor_exact_from_decimal(text, length, places, &value->numerator) != ANCHOR_EXACT_OK) ||
        (sim_exact_power(10ull, places, &value->denominator) == 0))
    {
        return 0;
    }
    sim_rational_settle(value);
    return 1;
}

int run_cfg_rational(const RunCfg *cfg, const char *path, SimRational *value)
{
    const unsigned int at = run_cfg_find(cfg, path);
    return (at != 0u) && run_cfg_decimal(cfg, at, value);
}

int run_cfg_count(const RunCfg *cfg, const char *path, unsigned long long *value)
{
    const unsigned int at = run_cfg_find(cfg, path);
    return (at != 0u) && cfg_json_unsigned(cfg->text.data(), &cfg->tokens[at], value);
}

int run_cfg_rationals(const RunCfg *cfg, const char *path, std::vector<SimRational> *values)
{
    const unsigned int at = run_cfg_find(cfg, path);
    if ((at == 0u) || (cfg->tokens[at].kind != CFG_JSON_ARRAY) || (cfg->tokens[at].count == 0u))
    {
        return 0;
    }
    values->clear();
    unsigned int element = at + 1u;
    for (unsigned int index = 0u; index < cfg->tokens[at].count; index += 1u)
    {
        SimRational value;
        if (run_cfg_decimal(cfg, element, &value) == 0)
        {
            return 0;
        }
        values->push_back(value);
        element = cfg->tokens[element].next;
    }
    return 1;
}

int run_cfg_text(const RunCfg *cfg, const char *path, std::string *value)
{
    const unsigned int at = run_cfg_find(cfg, path);
    if ((at == 0u) || (cfg->tokens[at].kind != CFG_JSON_STRING) || (cfg->tokens[at].end == cfg->tokens[at].start))
    {
        return 0;
    }
    value->assign(&cfg->text[cfg->tokens[at].start], cfg->tokens[at].end - cfg->tokens[at].start);
    return 1;
}

void run_cfg_missing(ScripturaLine *line, const char *members)
{
    scriptura_text(line, "  the cfg lacks a value, or one does not read: ");
    scriptura_text(line, members);
    scriptura_character(line, '\n');
}

int run_cfg_short(void)
{
    return s_sim_rational_wide != 0;
}
