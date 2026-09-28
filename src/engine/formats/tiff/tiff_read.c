// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// tiff_read.c: the layout and the entry points
#include "tiff_internal.h"

static int tiff_layout(TiffFile *file, const TiffPage *page, const char *text, unsigned long long pages,
                       unsigned int pages_known, TiffLayout *layout)
{
    memset(layout, 0, sizeof(*layout));
    if (file->reason != NULL)
    {
        return file->reason == NULL;
    }
    if ((text != NULL) && (strncmp(text, "ImageJ=", 7u) == 0))
    {
        tiff_imagej(file, text, pages, pages_known, layout);
    }
    else if ((text != NULL) && (tiff_ome_start(text) != NULL))
    {
        tiff_ome(file, page, text, pages, pages_known, layout);
    }
    else if ((page->next != 0ull) != (pages > 1ull))
    {
        return tiff_fail(file, "the page count does not match the chain of pages");
    }
    else if (pages > 1ull)
    {
        tiff_layout_axis(layout, '\0', pages, 1ull);
    }
    unsigned long long total = page->page_bytes;
    for (unsigned int axis = 0u; axis < layout->leading; axis += 1u)
    {
        tiff_multiply(file, total, layout->extent[axis], &total);
    }
    return file->reason == NULL;
}

static void tiff_extent(const TiffPage *page, const TiffLayout *layout, EngineArrayExtent *extent)
{
    memset(extent, 0, sizeof(*extent));
    for (unsigned int axis = 0u; axis < layout->leading; axis += 1u)
    {
        extent->sizes[axis] = layout->extent[axis];
        extent->axes[axis] = layout->axes[axis];
    }
    extent->sizes[layout->leading] = page->height;
    extent->axes[layout->leading] = 'y';
    extent->sizes[layout->leading + 1u] = page->width;
    extent->axes[layout->leading + 1u] = 'x';
    extent->rank = layout->leading + 2u;
    extent->element_bytes = page->element_bytes;
    extent->element_kind = page->element_kind;
}

static int tiff_extent_equal(const EngineArrayExtent *expected, const EngineArrayExtent *given)
{
    int equal = (expected->rank == given->rank) && (expected->element_bytes == given->element_bytes) &&
                (expected->element_kind == given->element_kind);
    for (unsigned int axis = 0u; equal && (axis < expected->rank); axis += 1u)
    {
        equal = (expected->sizes[axis] == given->sizes[axis]) && (expected->axes[axis] == given->axes[axis]);
    }
    return equal;
}

static void tiff_report(const TiffFile *file)
{
    fprintf(stderr, "tiff: %s: %s\n", (file->path != NULL) ? file->path : "(no path)", file->reason);
}

long tiff_describe(const EngineDescribeRequest *request)
{
    TiffFile file;
    TiffChain chain = {NULL, 0ull, 0ull, 0ull};
    TiffPage first;
    memset(&first, 0, sizeof(first));
    tiff_open(&file, request->path, request->member, request->tools);
    unsigned long long offset = file.first_ifd;
    while ((file.reason == NULL) && (offset != 0ull))
    {
        TiffPage page;
        unsigned long long *offsets = NULL;
        unsigned long long *counts = NULL;
        tiff_chain_add(&file, &chain, offset);
        tiff_page(&file, offset, &page);
        tiff_page_chunks(&file, &page, &offsets, &counts);
        free(offsets);
        free(counts);
        if (chain.count == 1ull)
        {
            first = page;
        }
        else if ((file.reason == NULL) && !tiff_page_same(&first, &page))
        {
            tiff_fail(&file, "the pages differ in width, height or sample type");
        }
        offset = page.next;
    }
    char *const text = tiff_description(&file, &first.description);
    TiffLayout layout;
    tiff_layout(&file, &first, text, chain.count, 1u, &layout);
    free(text);
    free(chain.offsets);
    if (file.reason != NULL)
    {
        tiff_report(&file);
        return -1L;
    }
    tiff_extent(&first, &layout, request->extent);
    return 0L;
}

static int tiff_read_planes(TiffFile *file, const EngineArrayRead *request, const TiffPage *first,
                            const TiffLayout *layout, TiffScratch *scratch, TiffChain *chain)
{
    unsigned long long inner = 1ull;
    unsigned long long top = (request->end - 1ull) * layout->stride[0u];
    for (unsigned int axis = 1u; axis < layout->leading; axis += 1u)
    {
        inner *= layout->extent[axis];
        top += (layout->extent[axis] - 1ull) * layout->stride[axis];
    }
    unsigned long long next = first->next;
    tiff_chain_add(file, chain, file->first_ifd);
    while ((file->reason == NULL) && (chain->count <= top))
    {
        if (next == 0ull)
        {
            return tiff_fail(file, "the file has fewer pages than its extent");
        }
        tiff_chain_add(file, chain, next);
        tiff_ifd_next(file, next, &next);
    }
    const unsigned long long plane_first = request->first * inner;
    const unsigned long long plane_end = request->end * inner;
    for (unsigned long long plane = plane_first; (file->reason == NULL) && (plane < plane_end); plane += 1ull)
    {
        unsigned long long remainder = plane;
        unsigned long long page_index = 0ull;
        for (unsigned int axis = layout->leading; axis > 0u; axis -= 1u)
        {
            page_index += (remainder % layout->extent[axis - 1u]) * layout->stride[axis - 1u];
            remainder /= layout->extent[axis - 1u];
        }
        TiffPage page;
        tiff_page(file, chain->offsets[page_index], &page);
        if ((file->reason == NULL) && !tiff_page_same(first, &page))
        {
            return tiff_fail(file, "the pages differ in width, height or sample type");
        }
        tiff_page_rows(file, &page, scratch, 0ull, page.height,
                       &request->out[(plane - plane_first) * first->page_bytes]);
    }
    return file->reason == NULL;
}

long long tiff_read(const EngineArrayRead *request)
{
    TiffFile file;
    TiffScratch scratch = {NULL, 0ull, NULL, 0ull};
    TiffChain chain = {NULL, 0ull, 0ull, 0ull};
    TiffPage first;
    TiffLayout layout;
    EngineArrayExtent expected;
    const EngineArrayExtent *const given = request->extent;
    unsigned long long total = 0ull;
    tiff_open(&file, request->path, request->member, request->tools);
    tiff_page(&file, file.first_ifd, &first);
    char *const text = tiff_description(&file, &first.description);
    const unsigned long long pages = (first.next == 0ull) ? 1ull : ((given->rank == 3u) ? given->sizes[0u] : 0ull);
    tiff_layout(&file, &first, text, pages, 0u, &layout);
    free(text);
    tiff_extent(&first, &layout, &expected);
    if ((file.reason == NULL) && !tiff_extent_equal(&expected, given))
    {
        tiff_fail(&file, "the extent given is not this file's extent");
    }
    if ((file.reason == NULL) && ((request->first > request->end) || (request->end > expected.sizes[0u])))
    {
        tiff_fail(&file, "a range outside axis 0");
    }
    unsigned long long per_index = expected.element_bytes;
    for (unsigned int axis = 1u; (file.reason == NULL) && (axis < expected.rank); axis += 1u)
    {
        tiff_multiply(&file, per_index, expected.sizes[axis], &per_index);
    }
    tiff_multiply(&file, per_index, request->end - request->first, &total);
    if ((file.reason == NULL) && (total > request->out_capacity))
    {
        tiff_fail(&file, "the output buffer is smaller than the range");
    }
    const unsigned int writing = (file.reason == NULL);
    if (writing && (layout.leading == 0u))
    {
        tiff_page_rows(&file, &first, &scratch, request->first, request->end, request->out);
    }
    else if (writing && (request->end > request->first))
    {
        tiff_read_planes(&file, request, &first, &layout, &scratch, &chain);
    }
    free(scratch.packed);
    free(scratch.chunk);
    free(chain.offsets);
    if (file.reason != NULL)
    {
        if (writing && (total > 0ull))
        {
            memset(request->out, 0, (size_t)total);
        }
        tiff_report(&file);
        return -1LL;
    }
    return (long long)total;
}
