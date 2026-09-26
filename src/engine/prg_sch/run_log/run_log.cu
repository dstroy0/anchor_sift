// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "run_log.h"

#include "track.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

const char *g_log_path = NULL;

static char s_log_default[4096];

static const char *log_path(void)
{
    if (g_log_path != NULL)
    {
        return g_log_path;
    }
    char directory[sizeof(s_log_default)];
    const int found = engine_program_directory(directory, sizeof(directory));
    const int written = found ? snprintf(s_log_default, sizeof(s_log_default), "%s/logs/track_driver.log", directory)
                              : snprintf(s_log_default, sizeof(s_log_default), "logs/track_driver.log");
    return ((written > 0) && ((size_t)written < sizeof(s_log_default))) ? s_log_default : "logs/track_driver.log";
}

char g_rules_line[256] = {0};

void rules_line(const TreeRules *rules, char *line, size_t room)
{
    const struct
    {
        const char *name;
        int on;
    } every[] = {
        {"pick", rules->pick}, {"share", rules->share}, {"agree", rules->agree}, {"unbound", rules->unbound},
        {"cast", rules->cast}, {"parallax", rules->parallax}, {"arc", rules->arc}, {"settle", rules->settle},
        {"focus", rules->focus}, {"web", rules->web}, {"damp", rules->damp}, {"dish", rules->dish}, {"vote", rules->vote}, {"mutual", rules->mutual}, {"tower", rules->tower}, {"mass", rules->mass}, {"forest", rules->forest}, {"cohere", rules->cohere}, {"accrue", rules->accrue},
        {"merge-split", rules->merge_split},
        {"merge-target", rules->merge_target}, {"forward-only", rules->forward_only},
        {"keep-view", rules->keep_view}, {"resolve", rules->resolve}, {"sticky", rules->sticky},
        {"motion-check", rules->motion_check}, {"climb", rules->climb},
    };
    line[0] = '\0';
    for (unsigned int slot = 0u; slot < (unsigned int)(sizeof(every) / sizeof(every[0])); slot += 1u)
    {
        const size_t at = strlen(line);
        const int fits = (every[slot].on != 0) && ((at + strlen(every[slot].name) + 2u) < room);
        if (fits != 0)
        {
            snprintf(&line[at], room - at, " %s", every[slot].name);
        }
    }
}

FILE *log_open(void)
{
    const char *const path = log_path();
    FILE *const log = engine_directories_make(path, 0) ? fopen(path, "a") : NULL;
    const int sought = (log != NULL) ? fseek(log, 0L, SEEK_END) : -1;
    if ((sought == 0) && (ftell(log) <= 0L))
    {
        fprintf(log, "when\tkind\trules\tsample\tframes\tobjects\tleaves\tlargest\trejoined"
                     "\tedges\tcorrect\tbranched\twrong\tno_link\tmissed"
                     "\tread_ms\tbodies_ms\tstore_ms\tties_ms\tmotion_ms\tlanding_ms\toverlap_ms\tclimb_ms"
                     "\tengines_ms\ttree_ms\tweb_asked\tweb_moved\tweb_capped\tweb_members"
                     "\tdamp_leaves\tdamp_landings\tdamp_deviations\n");
    }
    return log;
}

void log_when(char *when, size_t room)
{
    const time_t now = time(NULL);
    const struct tm *const broken = localtime(&now);
    when[0] = '\0';
    if (broken != NULL)
    {
        strftime(when, room, "%Y-%m-%dT%H:%M:%S", broken);
    }
}

const char *log_rules(void)
{
    return (g_rules_line[0] != '\0') ? &g_rules_line[1] : "none";
}
