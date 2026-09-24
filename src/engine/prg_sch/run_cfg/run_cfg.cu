// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "run_cfg.h"

#include "track.h"
#include "cfg_json.h"
#include "engine.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char CFG_SCHEME[] = "cell_tracking.cfg";

static const unsigned long long CFG_VERSION = 1ULL;

static const char *const CLIMB_NAMES[4] = {"off", "machine", "host", "check"};

static const char *const OUTPUT_NAMES[7] = {"edges", "coherence", "export", "object", "vis", "pool", "nodes"};

typedef struct
{
    const char *name;
    int TreeRules::*rule;
} CfgSwitch;

#define CFG_SWITCH_COUNT 26u

static const CfgSwitch CFG_SWITCHES[CFG_SWITCH_COUNT] = {
    {"pick", &TreeRules::pick},
    {"share", &TreeRules::share},
    {"agree", &TreeRules::agree},
    {"unbound", &TreeRules::unbound},
    {"cast", &TreeRules::cast},
    {"parallax", &TreeRules::parallax},
    {"arc", &TreeRules::arc},
    {"settle", &TreeRules::settle},
    {"focus", &TreeRules::focus},
    {"web", &TreeRules::web},
    {"damp", &TreeRules::damp},
    {"dish", &TreeRules::dish},
    {"vote", &TreeRules::vote},
    {"mutual", &TreeRules::mutual},
    {"tower", &TreeRules::tower},
    {"mass", &TreeRules::mass},
    {"forest", &TreeRules::forest},
    {"cohere", &TreeRules::cohere},
    {"accrue", &TreeRules::accrue},
    {"merge_split", &TreeRules::merge_split},
    {"merge_target", &TreeRules::merge_target},
    {"forward_only", &TreeRules::forward_only},
    {"keep_view", &TreeRules::keep_view},
    {"resolve", &TreeRules::resolve},
    {"sticky", &TreeRules::sticky},
    {"motion_check", &TreeRules::motion_check},
};

static void cfg_append(CfgText *text, const char *piece, size_t size)
{
    const size_t wanted = text->length + size + 1u;
    const size_t room = text->room + ((size_t)(wanted > text->room) * ((2u * wanted) - text->room));
    char *const grown = (char *)realloc(text->bytes, room);
    text->good = text->good && grown;
    text->bytes = grown ? grown : text->bytes;
    text->room = grown ? room : text->room;
    if (text->good)
    {
        memcpy(&text->bytes[text->length], piece, size);
        text->length += size;
        text->bytes[text->length] = '\0';
    }
}

static void cfg_append_text(CfgText *text, const char *piece)
{
    cfg_append(text, piece, strlen(piece));
}

static void cfg_append_quoted(CfgText *text, const char *piece)
{
    if (!piece)
    {
        cfg_append_text(text, "null");
        return;
    }
    cfg_append_text(text, "\"");
    for (const char *at = piece; *at; at += 1u)
    {
        const bool plain = (*at != '"') && (*at != '\\');
        cfg_append(text, "\\", (size_t)!plain);
        cfg_append(text, at, 1u);
    }
    cfg_append_text(text, "\"");
}

char *cfg_copy(const char *piece)
{
    const size_t size = strlen(piece) + 1u;
    char *const copy = (char *)malloc(size);
    return copy ? (char *)memcpy(copy, piece, size) : NULL;
}

bool open_output(TreeRules *rules, RunInputs *inputs, unsigned int output, const char *path)
{
    free(inputs->outputs[output]);
    inputs->outputs[output] = path ? cfg_copy(path) : NULL;
    const char *const kept = inputs->outputs[output];
    FILE **const files[7] = {&rules->edges, &rules->coherence, NULL, NULL, &rules->vis_index, &rules->pool,
                             &rules->nodes};
    if (files[output] && *files[output])
    {
        fclose(*files[output]);
        *files[output] = NULL;
    }
    rules->export_directory = (output == 2u) ? kept : rules->export_directory;
    rules->object_directory = (output == 3u) ? kept : rules->object_directory;
    rules->object = (output == 3u) ? !!kept : rules->object;
    rules->vis_directory = (output == 4u) ? kept : rules->vis_directory;
    if (kept && !engine_directories_make(kept, (output >= 2u) && (output <= 4u)))
    {
        fprintf(stderr, "  could not make the directories of %s\n", kept);
        return false;
    }
    if (!kept || !files[output])
    {
        return !path || kept;
    }
    char index_path[ENGINE_PATH_ROOM];
    const int written = snprintf(index_path, sizeof(index_path), "%s/index.html", kept);
    if ((written <= 0) || ((size_t)written >= sizeof(index_path)))
    {
        fprintf(stderr, "  %s/index.html is longer than a path may be\n", kept);
        return false;
    }
    FILE *const file = fopen((output == 4u) ? index_path : kept, "w");
    *files[output] = file;
    if (!file)
    {
        fprintf(stderr, "  could not open %s\n", (output == 4u) ? index_path : kept);
        return false;
    }
    if (output == 0u)
    {
        fprintf(file, "sample\ttime\tstatus\ttrue_z\ttrue_y\ttrue_x\tview_z\tview_y\tview_x\tcarried_z\tcarried_y"
                      "\tcarried_x\tbody_voxels\tfollows\theld\tnull_draws\tnull_at_least\tnull_best\tnull_held"
                      "\tarm_object\ttruth_onward\tlinked_onward"
                      "\ttruth_leaf\tchosen_leaf\tbest_leaf\ttruth_shared\tchosen_shared\tbest_shared\ttruth_mutual"
                      "\tone_object\tobject_links\tobject_links_truth\tunified_links\tunified_holds_truth\tmembers"
                      "\ttruth_weight\tlinked_weight\ttruth_web\tlinked_web\n");
    }
    if (output == 5u)
    {
        fprintf(file, "sample\ttime\tstatus\tobject\tcandidate\tis_truth\tis_linked\tmeeting\tstep\tmagnitude"
                      "\tcandidate_voxels\tcandidate_leaves\tobject_voxels\tobject_leaves\n");
    }
    if (output == 6u)
    {
        fprintf(file, "sample\ttime\tleaf\tz\ty\tx\tvoxels\tobject\tobject_members\tforward\tdeparture\theld"
                      "\tobject_link\tobject_links\tnull_draws\tnull_at_least\tnull_best"
                      "\ttower_target\ttower_rounds\tbackward\tbody\tstate\tparent\ttouches\tsplit_from\n");
    }
    if (output == 1u)
    {
        fprintf(file, "sample\ttime\tstatus\tsize_A\tleaves_A\tsize_B\town_z\town_y\town_x\tview_z\tview_y"
                      "\tview_x\ttrue_z\ttrue_y\ttrue_x\tagree_own\tagree_view\tagree_true\tland_B"
                      "\tland_max\tland_sumsq\tland_objects\n");
    }
    if (output == 4u)
    {
        fprintf(file,
                "<!doctype html><meta charset=utf-8><title>What the engine sees</title><style>body{background:#111;"
                "color:#ddd;font:14px sans-serif;margin:16px}figure{margin:0 0 28px}img{image-rendering:pixelated;"
                "max-width:100%%}figcaption{max-width:1100px;margin-top:6px}b{color:#fff}</style><h1>Failing edges, "
                "as the engine holds them</h1><p>Left: frame t at the source node's z. Right: frame t+1 at the "
                "target node's z. Both crops are centred on the source node. Positive voxels are tinted by object; "
                "object boundaries in the object's colour. Green outline: the source cell (left) and the true "
                "target (right). Red outline: an object the tree linked the cell to. Yellow: linked and true. Green "
                "plus: answer key nodes. White plus: the cell's peak. Magenta plus: where the tree carried that peak. "
                "White cells: other answer key nodes on the slice.</p>\n");
    }
    return true;
}

static bool cfg_refuse(const char *path, const char *text, size_t at, const char *reason)
{
    size_t line = 1u;
    size_t column = 1u;
    for (size_t byte = 0u; byte < at; byte += 1u)
    {
        const bool newline = (text[byte] == '\n');
        line += (size_t)newline;
        column = newline ? 1u : (column + 1u);
    }
    fprintf(stderr, "  %s:%zu:%zu: %s\n", path, line, column, reason);
    return false;
}

bool apply_cfg(const char *path, TreeRules *rules, RunInputs *inputs)
{
    FILE *const file = fopen(path, "rb");
    if (!file)
    {
        fprintf(stderr, "  could not open %s\n", path);
        return false;
    }
    fseek(file, 0L, SEEK_END);
    const long size = ftell(file);
    fseek(file, 0L, SEEK_SET);
    const size_t length = (size_t)((size > 0L) ? size : 0L);
    char *const text = (char *)malloc(length + 1u);
    const unsigned int room = (unsigned int)(length / 2u) + 4u;
    CfgJsonToken *const tokens = (CfgJsonToken *)malloc((size_t)room * sizeof(CfgJsonToken));
    bool good = text && tokens && (fread(text, 1u, length, file) == length);
    fclose(file);
    CfgJsonParse parse;
    memset(&parse, 0, sizeof(parse));
    good = good && cfg_json_parse(text, length, tokens, room, &parse);
    if (text && tokens && parse.reason)
    {
        fprintf(stderr, "  %s:%zu:%zu: %s\n", path, parse.line, parse.column, parse.reason);
    }
    good = good && ((tokens[0].kind == CFG_JSON_OBJECT) || cfg_refuse(path, text, 0u, "a .cfg is one object"));
    unsigned int key = 1u;
    unsigned long long number = 0ULL;
    char word[1024];
    for (unsigned int member = 0u; good && (member < tokens[0].count); member += 1u)
    {
        const unsigned int value = key + 1u;
        const CfgJsonToken *const token = &tokens[value];
        if (cfg_json_names(text, &tokens[key], "scheme"))
        {
            good = (cfg_json_string(text, token, word, sizeof(word)) && (strcmp(word, CFG_SCHEME) == 0))
                || cfg_refuse(path, text, token->start, "scheme is not cell_tracking.cfg");
        }
        else if (cfg_json_names(text, &tokens[key], "version"))
        {
            good = (cfg_json_unsigned(text, token, &number) && (number == CFG_VERSION))
                || cfg_refuse(path, text, token->start, "this tracker reads .cfg version 1");
        }
        else if (cfg_json_names(text, &tokens[key], "floor") && (token->kind == CFG_JSON_OBJECT))
        {
            unsigned int setting = value + 1u;
            for (unsigned int inner = 0u; good && (inner < token->count); inner += 1u)
            {
                const CfgJsonToken *const held = &tokens[setting + 1u];
                const bool boolean = (held->kind == CFG_JSON_TRUE) || (held->kind == CFG_JSON_FALSE);
                good = (cfg_json_names(text, &tokens[setting], "entropy")
                        || cfg_refuse(path, text, tokens[setting].start, "floor takes entropy"))
                    && (boolean || cfg_refuse(path, text, held->start, "entropy is true or false; the noise keys lie "
                                                                       "beside each sample in the set"));
                inputs->floor_entropy = good ? (held->kind == CFG_JSON_TRUE) : inputs->floor_entropy;
                setting = tokens[setting + 1u].past;
            }
        }
        else if (cfg_json_names(text, &tokens[key], "track") && (token->kind == CFG_JSON_OBJECT))
        {
            unsigned int rule = value + 1u;
            for (unsigned int inner = 0u; good && (inner < token->count); inner += 1u)
            {
                const CfgJsonToken *const setting = &tokens[rule + 1u];
                bool known = false;
                for (unsigned int slot = 0u; slot < CFG_SWITCH_COUNT; slot += 1u)
                {
                    const bool named = cfg_json_names(text, &tokens[rule], CFG_SWITCHES[slot].name);
                    const bool boolean = (setting->kind == CFG_JSON_TRUE) || (setting->kind == CFG_JSON_FALSE);
                    good = good && (!named || boolean || cfg_refuse(path, text, setting->start, "a rule takes true or false"));
                    rules->*CFG_SWITCHES[slot].rule = (named && boolean) ? (setting->kind == CFG_JSON_TRUE)
                                                                         : rules->*CFG_SWITCHES[slot].rule;
                    known = known || named;
                }
                if (cfg_json_names(text, &tokens[rule], "climb"))
                {
                    const bool read = cfg_json_string(text, setting, word, sizeof(word));
                    int mode = -1;
                    for (int slot = 0; read && (slot < 4); slot += 1)
                    {
                        mode = (strcmp(word, CLIMB_NAMES[slot]) == 0) ? slot : mode;
                    }
                    good = (mode >= 0) || cfg_refuse(path, text, setting->start, "climb is off, machine, host or check");
                    rules->climb = (mode >= 0) ? mode : rules->climb;
                    known = true;
                }
                if (cfg_json_names(text, &tokens[rule], "null_draws"))
                {
                    good = (cfg_json_unsigned(text, setting, &number) && (number < 4096ULL))
                        || cfg_refuse(path, text, setting->start, "null_draws is a count below 4096");
                    rules->null_draws = good ? (unsigned int)number : rules->null_draws;
                    known = true;
                }
                if (cfg_json_names(text, &tokens[rule], "arms"))
                {
                    good = (cfg_json_unsigned(text, setting, &number) && (number < 64ULL))
                        || cfg_refuse(path, text, setting->start, "arms is a count below 64");
                    rules->arms = good ? (unsigned int)number : rules->arms;
                    known = true;
                }
                good = good && (known || cfg_refuse(path, text, tokens[rule].start, "track has no such rule"));
                rule = tokens[rule + 1u].past;
            }
        }
        else if (cfg_json_names(text, &tokens[key], "input") && (token->kind == CFG_JSON_OBJECT))
        {
            const unsigned int source = cfg_json_member(text, tokens, value, "source");
            const unsigned int set = cfg_json_member(text, tokens, value, "set");
            const unsigned int axes = cfg_json_member(text, tokens, value, "axes");
            const unsigned int samples = cfg_json_member(text, tokens, value, "samples");
            const unsigned int first = cfg_json_member(text, tokens, value, "first");
            const unsigned int species = cfg_json_member(text, tokens, value, "species");
            const unsigned int voxel = cfg_json_member(text, tokens, value, "voxel_pm");
            const unsigned int membrane = cfg_json_member(text, tokens, value, "membrane_pm");
            const unsigned int named = (unsigned int)!!source + (unsigned int)!!set + (unsigned int)!!axes
                                     + (unsigned int)!!samples + (unsigned int)!!first + (unsigned int)!!species
                                     + (unsigned int)!!voxel + (unsigned int)!!membrane;
            good = (named == token->count)
                || cfg_refuse(path, text, token->start, "input takes source, set, axes, samples, first, species, voxel_pm "
                                                        "and membrane_pm");
            const unsigned int paths[3] = {source, set, axes};
            char **const held[3] = {&inputs->source, &inputs->set, &inputs->axes};
            const char *const refusals[3] = {"source is the dataset's directory, a path or null",
                                             "set is the directory the engine's .iapx live in, a path or null",
                                             "axes names the source's axes in order from t z y x c, or null"};
            for (unsigned int slot = 0u; good && (slot < 3u); slot += 1u)
            {
                if (paths[slot] == 0u)
                {
                    continue;
                }
                const bool none = (tokens[paths[slot]].kind == CFG_JSON_NULL);
                good = none || cfg_json_string(text, &tokens[paths[slot]], word, sizeof(word))
                    || cfg_refuse(path, text, tokens[paths[slot]].start, refusals[slot]);
                free(*held[slot]);
                *held[slot] = (good && !none) ? cfg_copy(word) : NULL;
            }
            if (good && species)
            {
                good = cfg_json_string(text, &tokens[species], word, sizeof(word))
                    || cfg_refuse(path, text, tokens[species].start, "species is a name");
                free(inputs->species);
                inputs->species = good ? cfg_copy(word) : NULL;
            }
            if (good && voxel)
            {
                good = ((tokens[voxel].kind == CFG_JSON_ARRAY) && (tokens[voxel].count == 3u))
                    || cfg_refuse(path, text, tokens[voxel].start, "voxel_pm is three integers, z y x, in picometers");
                for (unsigned int axis = 0u; good && (axis < 3u); axis += 1u)
                {
                    good = cfg_json_unsigned(text, &tokens[voxel + 1u + axis], &inputs->voxel_pm[axis])
                        || cfg_refuse(path, text, tokens[voxel + 1u + axis].start, "a voxel size is a whole number of picometers");
                }
            }
            if (good && membrane)
            {
                good = cfg_json_unsigned(text, &tokens[membrane], &inputs->membrane_pm)
                    || cfg_refuse(path, text, tokens[membrane].start, "membrane_pm is a whole number of picometers");
            }
            if (good && samples)
            {
                good = (tokens[samples].kind == CFG_JSON_ARRAY) || cfg_refuse(path, text, tokens[samples].start, "samples is a list");
                for (unsigned int slot = 0u; slot < inputs->count; slot += 1u)
                {
                    free(inputs->samples[slot]);
                }
                free(inputs->samples);
                inputs->count = 0u;
                inputs->samples = (char **)calloc((size_t)tokens[samples].count + 1u, sizeof(char *));
                for (unsigned int slot = 0u; good && (slot < tokens[samples].count); slot += 1u)
                {
                    const unsigned int element = samples + 1u + slot;
                    good = cfg_json_string(text, &tokens[element], word, sizeof(word))
                        || cfg_refuse(path, text, tokens[element].start, "a sample is a name");
                    inputs->samples[slot] = good ? cfg_copy(word) : NULL;
                    inputs->count += (unsigned int)good;
                }
            }
            if (good && first)
            {
                good = (cfg_json_unsigned(text, &tokens[first], &number) && (number < (1ULL << 20u)))
                    || cfg_refuse(path, text, tokens[first].start, "first is a count");
                inputs->first = (unsigned int)number;
            }
        }
        else if (cfg_json_names(text, &tokens[key], "output") && (token->kind == CFG_JSON_OBJECT))
        {
            unsigned int output = value + 1u;
            for (unsigned int inner = 0u; good && (inner < token->count); inner += 1u)
            {
                const CfgJsonToken *const setting = &tokens[output + 1u];
                int slot = -1;
                for (int name = 0; name < (int)(sizeof(OUTPUT_NAMES) / sizeof(OUTPUT_NAMES[0])); name += 1)
                {
                    slot = cfg_json_names(text, &tokens[output], OUTPUT_NAMES[name]) ? name : slot;
                }
                const bool none = (setting->kind == CFG_JSON_NULL);
                good = ((slot >= 0) || cfg_refuse(path, text, tokens[output].start, "output has no such output"))
                    && (none || cfg_json_string(text, setting, word, sizeof(word))
                        || cfg_refuse(path, text, setting->start, "an output is a path or null"))
                    && open_output(rules, inputs, (unsigned int)slot, none ? NULL : word);
                output = tokens[output + 1u].past;
            }
        }
        else if (cfg_json_names(text, &tokens[key], "view") && (token->kind == CFG_JSON_OBJECT))
        {
            free(inputs->view);
            inputs->view = (char *)malloc(token->end - token->start + 1u);
            good = inputs->view;
            if (good)
            {
                memcpy(inputs->view, &text[token->start], token->end - token->start);
                inputs->view[token->end - token->start] = '\0';
            }
        }
        else
        {
            good = cfg_refuse(path, text, tokens[key].start, "a .cfg has scheme, version, floor, track, input, output and view, "
                                                             "and floor, track, input, output and view are objects");
        }
        key = tokens[value].past;
    }
    rules->climb += (int)((rules->climb == 0) && (rules->sticky || rules->null_draws)) * 1;
    free(text);
    free(tokens);
    return good;
}

bool first_samples(RunInputs *inputs, bool from_source)
{
    const char *const directory = from_source ? inputs->source : inputs->set;
    char **names = NULL;
    const size_t count = (directory != NULL)
                       ? (size_t)(from_source ? engine_source_samples(directory, &names) : engine_set_samples(directory, &names))
                       : 0u;
    const size_t kept = (count < inputs->first) ? count : inputs->first;
    for (size_t slot = kept; slot < count; slot += 1u)
    {
        free(names[slot]);
    }
    for (unsigned int slot = 0u; slot < inputs->count; slot += 1u)
    {
        free(inputs->samples[slot]);
    }
    free(inputs->samples);
    inputs->samples = names;
    inputs->count = (unsigned int)kept;
    return kept != 0u;
}

bool write_cfg(const TreeRules *rules, const RunInputs *inputs, CfgText *out)
{
    memset(out, 0, sizeof(*out));
    out->good = true;
    cfg_append_text(out, "{\n  \"scheme\": \"cell_tracking.cfg\",\n  \"version\": 1,\n  \"floor\": {\n    \"entropy\": ");
    cfg_append_text(out, inputs->floor_entropy ? "true" : "false");
    cfg_append_text(out, "\n  },\n  \"track\": {\n");
    for (unsigned int slot = 0u; slot < CFG_SWITCH_COUNT; slot += 1u)
    {
        char line[128];
        snprintf(line, sizeof(line), "    \"%s\": %s,\n", CFG_SWITCHES[slot].name, (rules->*CFG_SWITCHES[slot].rule) ? "true" : "false");
        cfg_append_text(out, line);
    }
    char line[128];
    snprintf(line, sizeof(line), "    \"climb\": \"%s\",\n    \"null_draws\": %u\n  },\n", CLIMB_NAMES[(unsigned int)rules->climb & 3u],
             rules->null_draws);
    cfg_append_text(out, line);
    cfg_append_text(out, "  \"input\": {\n    \"source\": ");
    cfg_append_quoted(out, inputs->source);
    cfg_append_text(out, ",\n    \"set\": ");
    cfg_append_quoted(out, inputs->set);
    cfg_append_text(out, ",\n    \"axes\": ");
    cfg_append_quoted(out, inputs->axes);
    cfg_append_text(out, ",\n    \"samples\": [");
    for (unsigned int slot = 0u; slot < inputs->count; slot += 1u)
    {
        cfg_append_text(out, slot ? ", " : "");
        cfg_append_quoted(out, inputs->samples[slot]);
    }
    snprintf(line, sizeof(line), "],\n    \"first\": %u,\n    \"species\": ", inputs->first);
    cfg_append_text(out, line);
    cfg_append_quoted(out, inputs->species);
    snprintf(line, sizeof(line), ",\n    \"voxel_pm\": [%llu, %llu, %llu],\n    \"membrane_pm\": %llu\n  },\n  \"output\": {\n",
             inputs->voxel_pm[0], inputs->voxel_pm[1], inputs->voxel_pm[2], inputs->membrane_pm);
    cfg_append_text(out, line);
    for (unsigned int slot = 0u; slot < 7u; slot += 1u)
    {
        snprintf(line, sizeof(line), "    \"%s\": ", OUTPUT_NAMES[slot]);
        cfg_append_text(out, line);
        cfg_append_quoted(out, inputs->outputs[slot]);
        cfg_append_text(out, (slot < 6u) ? ",\n" : "\n  },\n");
    }
    cfg_append_text(out, "  \"view\": ");
    cfg_append_text(out, inputs->view ? inputs->view : "{}");
    cfg_append_text(out, "\n}\n");
    return out->good;
}
