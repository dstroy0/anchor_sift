// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "tessera_text.h"

#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#define TESSERA_SEPARATOR '\\'
#else
#define TESSERA_SEPARATOR '/'
#endif

#if defined(_WIN32)
_Alignas(8) static const char s_tessera_pipe[] = "\\\\.\\pipe\\tessera-";
#else
_Alignas(8) static const char s_tessera_socket[] = "/tessera-";
_Alignas(8) static const char s_tessera_socket_end[] = ".sock";
_Alignas(8) static const char s_tessera_local_state[] = "/.local/state/tessera";
_Alignas(8) static const char s_tessera_temporary[] = "/tmp";
#endif
_Alignas(8) static const char s_tessera_folder[] = "tessera";
_Alignas(8) static const char s_tessera_history[] = "hst";
_Alignas(8) static const char s_tessera_lost[] = "lnf.log";

int tessera_text_staged(ScripturaLine *line, const char *text)
{
    const size_t length = strlen(text);
    char *const staged = (char *)calloc((length / 8u) + 1u, 8u);
    if (staged == NULL)
    {
        line->at = line->room;
        return 0;
    }
    memcpy(staged, text, length);
    scriptura_text(line, staged);
    free(staged);
    return 1;
}

void tessera_bytes_hex(ScripturaLine *line, const unsigned char *bytes, unsigned int count)
{
    for (unsigned int byte = 0u; byte < count; byte += 1u)
    {
        scriptura_hex(line, bytes[byte], 2u);
    }
}

static const char *tessera_environment(const char *name)
{
    const char *const value = getenv(name);
    return ((value != NULL) && (value[0] != '\0')) ? value : NULL;
}

static int tessera_line_done(ScripturaLine *line)
{
    return scriptura_finish(line) != 0ull;
}

int tessera_path_endpoint(const unsigned char device[TESSERA_DEVICE_BYTES], char *path, unsigned int room)
{
    ScripturaLine line = {path, room, 0ull};
#if defined(_WIN32)
    scriptura_text(&line, s_tessera_pipe);
    tessera_bytes_hex(&line, device, TESSERA_DEVICE_BYTES);
#else
    const char *runtime = tessera_environment("TESSERA_RUNTIME");
    runtime = (runtime != NULL) ? runtime : tessera_environment("XDG_RUNTIME_DIR");
    if (runtime != NULL)
    {
        tessera_text_staged(&line, runtime);
    }
    else
    {
        scriptura_text(&line, s_tessera_temporary);
    }
    scriptura_text(&line, s_tessera_socket);
    tessera_bytes_hex(&line, device, TESSERA_DEVICE_BYTES);
    scriptura_text(&line, s_tessera_socket_end);
#endif
    return tessera_line_done(&line);
}

int tessera_path_state(const unsigned char device[TESSERA_DEVICE_BYTES], char *path, unsigned int room)
{
    ScripturaLine line = {path, room, 0ull};
    const char *const chosen = tessera_environment("TESSERA_STATE");
    if (chosen != NULL)
    {
        tessera_text_staged(&line, chosen);
    }
    else
    {
#if defined(_WIN32)
        const char *const local = tessera_environment("LOCALAPPDATA");
        if (local == NULL)
        {
            return 0;
        }
        tessera_text_staged(&line, local);
        scriptura_character(&line, TESSERA_SEPARATOR);
        scriptura_text(&line, s_tessera_folder);
#else
        const char *const state = tessera_environment("XDG_STATE_HOME");
        const char *const home = tessera_environment("HOME");
        if ((state == NULL) && (home == NULL))
        {
            return 0;
        }
        tessera_text_staged(&line, (state != NULL) ? state : home);
        if (state != NULL)
        {
            scriptura_character(&line, TESSERA_SEPARATOR);
            scriptura_text(&line, s_tessera_folder);
        }
        else
        {
            scriptura_text(&line, s_tessera_local_state);
        }
#endif
    }
    scriptura_character(&line, TESSERA_SEPARATOR);
    tessera_bytes_hex(&line, device, TESSERA_DEVICE_BYTES);
    return tessera_line_done(&line);
}

int tessera_path_lost(const unsigned char device[TESSERA_DEVICE_BYTES], char *path, unsigned int room)
{
    if (!tessera_path_state(device, path, room))
    {
        return 0;
    }
    ScripturaLine line = {path, room, 0ull};
    line.at = strlen(path);
    scriptura_character(&line, TESSERA_SEPARATOR);
    scriptura_text(&line, s_tessera_history);
    scriptura_character(&line, TESSERA_SEPARATOR);
    scriptura_text(&line, s_tessera_lost);
    return tessera_line_done(&line);
}
