// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "vis_png.h"

#include "track.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define VIS_CROP 64u

#define VIS_SCALE 6u

#define VIS_GAP 8u

#define VIS_NO_OBJECT 0xFFFFFFFFu

static unsigned int png_crc(const unsigned char *bytes, size_t count, unsigned int crc)
{
    for (size_t at = 0u; at < count; at += 1u)
    {
        crc ^= bytes[at];
        for (unsigned int bit = 0u; bit < 8u; bit += 1u)
        {
            crc = ((crc & 1u) != 0u) ? ((crc >> 1u) ^ 0xEDB88320u) : (crc >> 1u);
        }
    }
    return crc;
}

static void png_chunk(FILE *handle, const char *type, const unsigned char *data, size_t length)
{
    const unsigned char size[4] = {(unsigned char)(length >> 24u), (unsigned char)(length >> 16u),
                                   (unsigned char)(length >> 8u), (unsigned char)length};
    fwrite(size, 1u, 4u, handle);
    fwrite(type, 1u, 4u, handle);
    if (length > 0u)
    {
        fwrite(data, 1u, length, handle);
    }
    unsigned int crc = png_crc((const unsigned char *)type, 4u, 0xFFFFFFFFu);
    crc = png_crc(data, length, crc) ^ 0xFFFFFFFFu;
    const unsigned char tail[4] = {(unsigned char)(crc >> 24u), (unsigned char)(crc >> 16u), (unsigned char)(crc >> 8u),
                                   (unsigned char)crc};
    fwrite(tail, 1u, 4u, handle);
}

static int write_png_rgb(const char *path, const unsigned char *rgb, unsigned int width, unsigned int height)
{
    const size_t row = 1u + (size_t)width * 3u;
    const size_t raw = row * height;
    const size_t blocks = (raw + 65534u) / 65535u;
    const size_t stream_bytes = 2u + blocks * 5u + raw + 4u;
    unsigned char *const stream = (unsigned char *)malloc(stream_bytes);
    FILE *const handle = fopen(path, "wb");
    if ((stream == NULL) || (handle == NULL))
    {
        free(stream);
        if (handle != NULL)
        {
            fclose(handle);
        }
        return 0;
    }
    size_t at = 0u;
    stream[at] = 0x78u;
    stream[at + 1u] = 0x01u;
    at += 2u;
    unsigned int adler_low = 1u;
    unsigned int adler_high = 0u;
    size_t emitted = 0u;
    size_t block_left = 0u;
    for (unsigned int line = 0u; line < height; line += 1u)
    {
        for (size_t column = 0u; column < row; column += 1u)
        {
            if (block_left == 0u)
            {
                const size_t length = ((raw - emitted) > 65535u) ? 65535u : (raw - emitted);
                stream[at] = ((raw - emitted) <= 65535u) ? 1u : 0u;
                stream[at + 1u] = (unsigned char)(length & 0xFFu);
                stream[at + 2u] = (unsigned char)(length >> 8u);
                stream[at + 3u] = (unsigned char)(~length & 0xFFu);
                stream[at + 4u] = (unsigned char)((~length >> 8u) & 0xFFu);
                at += 5u;
                block_left = length;
            }
            const unsigned char value = (column == 0u) ? 0u : rgb[(size_t)line * width * 3u + (column - 1u)];
            stream[at] = value;
            at += 1u;
            adler_low = (adler_low + value) % 65521u;
            adler_high = (adler_high + adler_low) % 65521u;
            emitted += 1u;
            block_left -= 1u;
        }
    }
    const unsigned int adler = (adler_high << 16u) | adler_low;
    stream[at] = (unsigned char)(adler >> 24u);
    stream[at + 1u] = (unsigned char)(adler >> 16u);
    stream[at + 2u] = (unsigned char)(adler >> 8u);
    stream[at + 3u] = (unsigned char)adler;
    at += 4u;
    static const unsigned char signature[8] = {137u, 80u, 78u, 71u, 13u, 10u, 26u, 10u};
    fwrite(signature, 1u, 8u, handle);
    const unsigned char header[13] = {(unsigned char)(width >> 24u), (unsigned char)(width >> 16u),
                                      (unsigned char)(width >> 8u), (unsigned char)width,
                                      (unsigned char)(height >> 24u), (unsigned char)(height >> 16u),
                                      (unsigned char)(height >> 8u), (unsigned char)height, 8u, 2u, 0u, 0u, 0u};
    png_chunk(handle, "IHDR", header, 13u);
    png_chunk(handle, "IDAT", stream, at);
    png_chunk(handle, "IEND", NULL, 0u);
    const int good = (ferror(handle) == 0);
    fclose(handle);
    free(stream);
    return good;
}

static void object_colour(unsigned int object, unsigned char *rgb)
{
    const unsigned int mixed = object * 2654435761u;
    rgb[0] = (unsigned char)(80u + ((mixed >> 3u) % 160u));
    rgb[1] = (unsigned char)(80u + ((mixed >> 11u) % 120u));
    rgb[2] = (unsigned char)(80u + ((mixed >> 19u) % 160u));
}

static void paint_voxel(unsigned char *rgb, unsigned int width, unsigned int left, int row, int column,
                        unsigned int inset, const unsigned char *colour)
{
    if ((row < 0) || (column < 0) || (row >= (int)VIS_CROP) || (column >= (int)VIS_CROP))
    {
        return;
    }
    for (unsigned int down = inset; down < VIS_SCALE - inset; down += 1u)
    {
        for (unsigned int across = inset; across < VIS_SCALE - inset; across += 1u)
        {
            const size_t pixel = ((size_t)((unsigned int)row * VIS_SCALE + down) * width
                                  + left + (unsigned int)column * VIS_SCALE + across) * 3u;
            rgb[pixel] = colour[0];
            rgb[pixel + 1u] = colour[1];
            rgb[pixel + 2u] = colour[2];
        }
    }
}

static void paint_marker(unsigned char *rgb, unsigned int width, unsigned int left, int row, int column,
                         const unsigned char *colour)
{
    for (int step = -2; step <= 2; step += 1)
    {
        paint_voxel(rgb, width, left, row + step, column, 1u, colour);
        paint_voxel(rgb, width, left, row, column + step, 1u, colour);
    }
}

int render_case(const EngineBuffers *buffers, const CoherenceInputs *inputs, const VisCase *view)
{
    const size_t voxels = (size_t)buffers->depth * buffers->height * buffers->width;
    const unsigned int plane = buffers->height * buffers->width;
    const unsigned int panel = VIS_CROP * VIS_SCALE;
    const unsigned int width = 2u * panel + VIS_GAP;
    const unsigned int height = panel;
    unsigned char *const rgb = (unsigned char *)calloc((size_t)width * height * 3u, 1u);
    unsigned short *const raw[2] = {(unsigned short *)malloc((size_t)plane * sizeof(unsigned short)),
                                    (unsigned short *)malloc((size_t)plane * sizeof(unsigned short))};
    unsigned int *const object[2] = {(unsigned int *)malloc((size_t)VIS_CROP * VIS_CROP * sizeof(unsigned int)),
                                     (unsigned int *)malloc((size_t)VIS_CROP * VIS_CROP * sizeof(unsigned int))};
    int good = (rgb != NULL) && (raw[0] != NULL) && (raw[1] != NULL) && (object[0] != NULL) && (object[1] != NULL);

    const int top = (view->from[2] - (int)(VIS_CROP / 2u) < 0) ? 0
                  : ((view->from[2] + (int)(VIS_CROP / 2u) > (int)buffers->height) ? (int)buffers->height - (int)VIS_CROP
                                                                                  : view->from[2] - (int)(VIS_CROP / 2u));
    const int left_column = (view->from[3] - (int)(VIS_CROP / 2u) < 0) ? 0
                          : ((view->from[3] + (int)(VIS_CROP / 2u) > (int)buffers->width) ? (int)buffers->width - (int)VIS_CROP
                                                                                          : view->from[3] - (int)(VIS_CROP / 2u));
    const int slice[2] = {view->from[1], view->to[1]};
    const unsigned int times[2] = {view->earlier->time, view->later->time};
    const unsigned int offsets[2] = {view->offset_before, view->offset_after};
    const TreeFrame *const tree[2] = {view->earlier, view->later};
    unsigned int brightest = 1u;
    for (unsigned int side = 0u; (good != 0) && (side < 2u); side += 1u)
    {
        good = (times[side] < inputs->volume_frames) && (slice[side] >= 0) && ((unsigned int)slice[side] < buffers->depth);
        if (good != 0)
        {
            memcpy(raw[side], &inputs->volume[((size_t)times[side] * voxels) + ((size_t)slice[side] * plane)],
                   (size_t)plane * sizeof(unsigned short));
        }
        for (unsigned int down = 0u; (good != 0) && (down < VIS_CROP); down += 1u)
        {
            for (unsigned int across = 0u; across < VIS_CROP; across += 1u)
            {
                const unsigned int flat = (unsigned int)(top + (int)down) * buffers->width + (unsigned int)(left_column + (int)across);
                const unsigned int voxel = (unsigned int)slice[side] * plane + flat;
                brightest = (raw[side][flat] > brightest) ? raw[side][flat] : brightest;
                unsigned int id = VIS_NO_OBJECT;
                if (((buffers->positive[side][voxel / 64u] >> (voxel % 64u)) & 1ULL) != 0ULL)
                {
                    const int leaf = view->leaf_at_peak[side][buffers->labels[side][voxel]];
                    if (leaf >= 0)
                    {
                        id = inputs->unified_of[offsets[side] + tree[side]->object_of[(unsigned int)leaf]];
                    }
                }
                object[side][down * VIS_CROP + across] = id;
            }
        }
    }

    const unsigned int *const links_begin = &inputs->unified_start[view->cell];
    const unsigned char green[3] = {40u, 255u, 60u};
    const unsigned char red[3] = {255u, 50u, 40u};
    const unsigned char yellow[3] = {255u, 230u, 30u};
    const unsigned char white[3] = {255u, 255u, 255u};
    const unsigned char magenta[3] = {255u, 60u, 255u};
    for (unsigned int side = 0u; (good != 0) && (side < 2u); side += 1u)
    {
        const unsigned int left = side * (panel + VIS_GAP);
        for (unsigned int down = 0u; down < VIS_CROP; down += 1u)
        {
            for (unsigned int across = 0u; across < VIS_CROP; across += 1u)
            {
                const unsigned int flat = (unsigned int)(top + (int)down) * buffers->width + (unsigned int)(left_column + (int)across);
                const unsigned int gray = (unsigned int)raw[side][flat] * 255u / brightest;
                const unsigned int id = object[side][down * VIS_CROP + across];
                unsigned char colour[3] = {(unsigned char)gray, (unsigned char)gray, (unsigned char)gray};
                if (id != VIS_NO_OBJECT)
                {
                    unsigned char own[3];
                    object_colour(id, own);
                    int boundary = 0;
                    const int neighbours[4][2] = {{-1, 0}, {1, 0}, {0, -1}, {0, 1}};
                    for (unsigned int which = 0u; which < 4u; which += 1u)
                    {
                        const int near_row = (int)down + neighbours[which][0];
                        const int near_column = (int)across + neighbours[which][1];
                        const unsigned int near = ((near_row < 0) || (near_column < 0) || (near_row >= (int)VIS_CROP)
                                                   || (near_column >= (int)VIS_CROP))
                                                ? id
                                                : object[side][(unsigned int)near_row * VIS_CROP + (unsigned int)near_column];
                        boundary = boundary || (near != id);
                    }
                    for (unsigned int channel = 0u; channel < 3u; channel += 1u)
                    {
                        colour[channel] = (unsigned char)((gray * 5u + (unsigned int)own[channel] * 3u) / 8u);
                    }
                    if (boundary != 0)
                    {
                        const unsigned char *highlight = own;
                        int linked = 0;
                        for (unsigned int link = links_begin[0]; link < links_begin[1]; link += 1u)
                        {
                            linked = linked || ((unsigned int)(inputs->unified_link[link] & 0xFFFFFFFFULL) == id);
                        }
                        if ((side == 0u) && (id == view->cell))
                        {
                            highlight = green;
                        }
                        else if ((side == 1u) && (linked != 0) && (id == view->true_target))
                        {
                            highlight = yellow;
                        }
                        else if ((side == 1u) && (id == view->true_target))
                        {
                            highlight = green;
                        }
                        else if ((side == 1u) && (linked != 0))
                        {
                            highlight = red;
                        }
                        colour[0] = highlight[0];
                        colour[1] = highlight[1];
                        colour[2] = highlight[2];
                    }
                }
                paint_voxel(rgb, width, left, (int)down, (int)across, 0u, colour);
            }
        }
        for (unsigned int node = 0u; node < inputs->key->node_count; node += 1u)
        {
            const int *const place = &inputs->key->node_coordinates[(size_t)node * 4u];
            if ((place[0] >= 0) && ((unsigned int)place[0] == times[side]) && (place[1] == slice[side]))
            {
                paint_voxel(rgb, width, left, place[2] - top, place[3] - left_column, 2u, white);
            }
        }
    }
    if (good != 0)
    {
        const unsigned int peak = view->earlier->peaks[view->source_leaf];
        const unsigned int peak_rest = peak % plane;
        const int peak_place[3] = {(int)(peak / plane), (int)(peak_rest / buffers->width), (int)(peak_rest % buffers->width)};
        paint_marker(rgb, width, 0u, view->from[2] - top, view->from[3] - left_column, green);
        paint_marker(rgb, width, 0u, peak_place[1] - top, peak_place[2] - left_column, white);
        paint_marker(rgb, width, panel + VIS_GAP, view->to[2] - top, view->to[3] - left_column, green);
        const int *const lag = (view->earlier->forward_lag != NULL) ? &view->earlier->forward_lag[3u * view->source_leaf]
                                                                     : view->earlier->lag_to_next;
        paint_marker(rgb, width, panel + VIS_GAP, peak_place[1] + lag[1] - top, peak_place[2] + lag[2] - left_column,
                     magenta);

        char path[ENGINE_PATH_ROOM];
        const int written = snprintf(path, sizeof(path), "%s/%s_t%u_edge%u.png", inputs->vis_directory, inputs->sample,
                                     view->earlier->time, view->edge);
        good = (written > 0) && ((size_t)written < sizeof(path)) && write_png_rgb(path, rgb, width, height);
        unsigned int linked_count = links_begin[1] - links_begin[0];
        int linked_true = 0;
        for (unsigned int link = links_begin[0]; link < links_begin[1]; link += 1u)
        {
            linked_true = linked_true || ((unsigned int)(inputs->unified_link[link] & 0xFFFFFFFFULL) == view->true_target);
        }
        const unsigned long long view_share = (view->cell_size > 0u) ? (view->agree_view * 200ULL + view->cell_size) / (2ULL * view->cell_size) : 0ULL;
        const unsigned long long true_share = (view->cell_size > 0u) ? (view->agree_true * 200ULL + view->cell_size) / (2ULL * view->cell_size) : 0ULL;
        const unsigned long long landing_share = (view->agree_view > 0ULL) ? ((unsigned long long)view->land_true * 200ULL + view->agree_view) / (2ULL * view->agree_view) : 0ULL;
        fprintf(inputs->vis_index,
                "<figure><img src=\"%s_t%u_edge%u.png\"><figcaption><b>%s</b> %s frame %u&rarr;%u &middot; "
                "source node z%d y%d x%d, target node z%d y%d x%d (step %d %d %d) &middot; peak z%d y%d x%d carried by "
                "lag %d %d %d to z%d &middot; view lag %d %d %d &middot; cell %zu voxels in %u bodies, true target %u "
                "voxels &middot; agrees %llu%% at view lag, %llu%% at true step &middot; at view lag %llu%% lands in "
                "true target, spread over %u objects &middot; tree linked it to %u object%s%s</figcaption></figure>\n",
                inputs->sample, view->earlier->time, view->edge, EDGE_STATUS_NAMES[view->status], inputs->sample,
                view->earlier->time, view->later->time, view->from[1], view->from[2], view->from[3], view->to[1],
                view->to[2], view->to[3], view->to[1] - view->from[1], view->to[2] - view->from[2],
                view->to[3] - view->from[3], peak_place[0], peak_place[1], peak_place[2], lag[0], lag[1], lag[2],
                peak_place[0] + lag[0], view->earlier->lag_to_next[0], view->earlier->lag_to_next[1],
                view->earlier->lag_to_next[2], view->cell_size, view->leaves, view->target_size, view_share,
                true_share, landing_share, view->land_objects, linked_count, (linked_count == 1u) ? "" : "s",
                (linked_true != 0) ? ", including the true target" : "");
        fflush(inputs->vis_index);
    }
    free(rgb);
    free(raw[0]);
    free(raw[1]);
    free(object[0]);
    free(object[1]);
    return good;
}
