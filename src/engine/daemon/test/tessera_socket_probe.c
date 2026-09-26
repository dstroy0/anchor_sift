// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// a client with no device of its own: it submits one job for the device named on its command line through the
// endpoint tessera_path_endpoint names ($TESSERA_RUNTIME in a container), with no daemon path, so only a daemon
// already listening there, or a socket systemd holds, can answer. It prints what came back.
#include "tessera.h"

#include <stdio.h>
#include <string.h>

static int probe_hex(const char *text, unsigned char *bytes, unsigned int count)
{
    if (strlen(text) != (2u * count))
    {
        return 0;
    }
    for (unsigned int byte = 0u; byte < count; byte += 1u)
    {
        unsigned int value = 0u;
        if (sscanf(text + (2u * byte), "%2x", &value) != 1)
        {
            return 0;
        }
        // two hex digits are one byte
        bytes[byte] = (unsigned char)value;
    }
    return 1;
}

int main(int count, char **arguments)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    TesseraJobAsk ask;
    memset(&ask, 0, sizeof(ask));
    if ((count < 2) || !probe_hex(arguments[1], ask.device, TESSERA_DEVICE_BYTES))
    {
        printf("  tessera socket probe: the device's UUID as 32 lowercase hex digits is the one argument\n");
        return 2;
    }
    char endpoint[ENGINE_PATH_ROOM];
    const int named = tessera_path_endpoint(ask.device, endpoint, ENGINE_PATH_ROOM);
    printf("  endpoint %s\n", named ? endpoint : "(none)");
    ask.signum.bytes[0] = 0x50u;
    ask.declared = 1ull;
    ask.holding_microseconds = 1000000ull;
    ask.sweep_microseconds = 20000ull;
    ask.idle_microseconds = 1000000ull;
    ask.daemon_path = NULL;
    ask.error = &error;
    TesseraClient *client = NULL;
    TesseraTicket ticket;
    const long answer = tessera_job_submit(&ask, &client, &ticket);
    printf("  submit %s (error kind %d, module %d, site %u, status %d)\n", (answer == 0L) ? "admitted" : "refused",
           (int)error.kind, (int)error.module, error.site, error.status);
    if (answer == 0L)
    {
        tessera_job_release(client, &ticket, &error);
    }
    return (answer == 0L) ? 0 : 1;
}
