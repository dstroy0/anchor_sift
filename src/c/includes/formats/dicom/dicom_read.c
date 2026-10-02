// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// dicom_read.c: holding, describing and reading a series
#include "dicom_internal.h"

static int dicom_open(const EngineIngestTools *tools, const char *path, const char *member, EngineError *error)
{
    DicomResident *const resident = &g_dicom_resident;
    if (!DICOM_CHECK((tools != NULL) && (path != NULL) && (member != NULL), &path, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    if ((resident->valid != 0) && (strcmp(resident->path, path) == 0) && (strcmp(resident->member, member) == 0))
    {
        return 1;
    }
    dicom_resident_release();
    const ZipArchive *const archive = zip_archive_cached(tools, path, error);
    unsigned long long first = 0ull;
    unsigned long long count = 0ull;
    if ((archive == NULL) || !zip_folder_find(archive, member, &first, &count) ||
        !DICOM_CHECK(count != 0ull, member, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    if (!dicom_gather(tools, path, archive, first, count, error) || !dicom_agree(error) || !dicom_sort(error))
    {
        dicom_resident_release();
        return 0;
    }
    resident->path = (char *)malloc(strlen(path) + 1u);
    resident->member = (char *)malloc(strlen(member) + 1u);
    if (!DICOM_CHECK((resident->path != NULL) && (resident->member != NULL), resident, error, ENGINE_ERROR_RESOURCE))
    {
        dicom_resident_release();
        return 0;
    }
    memcpy(resident->path, path, strlen(path) + 1u);
    memcpy(resident->member, member, strlen(member) + 1u);
    resident->valid = 1;
    return 1;
}

static void dicom_extent(EngineArrayExtent *extent)
{
    const DicomResident *const resident = &g_dicom_resident;
    const DicomSlice *const lead = &resident->slices[0];
    memset(extent, 0, sizeof(*extent));
    extent->rank = 4u;
    extent->sizes[0] = 1ull;
    extent->sizes[1] = resident->count;
    extent->sizes[2] = lead->rows;
    extent->sizes[3] = lead->columns;
    memcpy(extent->axes, "tzyx", 4u);
    extent->element_bytes = lead->bits_allocated / 8u;
    extent->element_kind = (lead->pixel_representation != 0u) ? ENGINE_ELEMENT_SIGNED : ENGINE_ELEMENT_UNSIGNED;
}

int dicom_zip_has_member(const EngineIngestTools *tools, const char *path, const char *member)
{
    EngineError probe;
    memset(&probe, 0, sizeof(probe));
    const ZipArchive *const archive = (member != NULL) ? zip_archive_cached(tools, path, &probe) : NULL;
    unsigned long long first = 0ull;
    unsigned long long count = 0ull;
    if ((archive == NULL) || !zip_folder_find(archive, member, &first, &count))
    {
        return 0;
    }
    for (unsigned long long slot = first; slot < (first + count); slot += 1ull)
    {
        ZipEntry entry;
        if (!zip_entry_at(archive, slot, &entry, &probe))
        {
            return 0;
        }
        if ((entry.name_length == 0ull) || (entry.name[entry.name_length - 1ull] == '/'))
        {
            continue;
        }
        unsigned char *const member = (unsigned char *)malloc((size_t)entry.uncompressed + 1u);
        const int read = (member != NULL) && (zip_member_read(tools, path, archive, &entry, member, entry.uncompressed,
                                                              &probe) != ZIP_ERROR);
        const int preamble_valid = read && (entry.uncompressed >= (DICOM_PREAMBLE + 4ull)) &&
                                   (memcmp(member + DICOM_PREAMBLE, "DICM", 4u) == 0);
        free(member);
        return preamble_valid ? 1 : 0;
    }
    return 0;
}

long dicom_describe(const EngineDescribeRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return -1L;
    }
    if (!DICOM_CHECK(request->extent != NULL, request, request->error, ENGINE_ERROR_REQUEST) ||
        !dicom_open(request->tools, request->path, request->member, request->error))
    {
        return -1L;
    }
    dicom_extent(request->extent);
    return 0L;
}

static unsigned long long dicom_sign_extend(const DicomSlice *slice, unsigned char *pixels)
{
    const unsigned int element_bytes = slice->bits_allocated / 8u;
    const unsigned int width = 8u * element_bytes;
    const unsigned long long mask = (width >= 64u) ? ~0ull : ((1ull << width) - 1ull);
    const unsigned int low = (slice->high_bit + 1u) - slice->bits_stored;
    const unsigned long long field = (slice->bits_stored >= 64u) ? ~0ull : ((1ull << slice->bits_stored) - 1ull);
    const unsigned long long sign = 1ull << (slice->bits_stored - 1u);
    const unsigned long long elements = slice->pixel_bytes / element_bytes;
    unsigned long long kept = 0ull;
    for (unsigned long long element = 0ull; element < elements; element += 1ull)
    {
        unsigned char *const at = pixels + (element * element_bytes);
        unsigned long long word = 0ull;
        for (unsigned int place = element_bytes; place > 0u; place -= 1u)
        {
            word = (word << 8u) | (unsigned long long)at[place - 1u];
        }
        const unsigned long long stored = (word >> low) & field;
        const unsigned long long extended = ((stored & sign) != 0ull) ? ((stored | ~field) & mask) : stored;
        const unsigned long long canonical = (extended << low) & mask;
        kept |= (canonical != word) ? 1ull : 0ull;
        for (unsigned int place = 0u; place < element_bytes; place += 1u)
        {
            // one byte of the extended word is taken whole
            at[place] = (unsigned char)((extended >> (8u * place)) & 0xFFull);
        }
    }
    return kept;
}

static void dicom_side_release(EngineSideBytes *side)
{
    free(side->pixel_at);
    free(side->pixel_kept);
    free(side->byte_start);
    free(side->bytes);
    free(side->name_start);
    free(side->names);
    free(side->member_crc);
    free(side->member_bytes);
    memset(side, 0, sizeof(*side));
}

static int dicom_side_fill(EngineSideBytes *side, EngineError *error)
{
    const DicomResident *const resident = &g_dicom_resident;
    unsigned long long kept = 0ull;
    unsigned long long named = 0ull;
    for (unsigned long long slot = 0ull; slot < resident->count; slot += 1ull)
    {
        const DicomSlice *const slice = &resident->slices[slot];
        kept += slice->member_bytes - ((slice->pixel_kept != 0ull) ? 0ull : slice->pixel_bytes);
        named += slice->name_length;
    }
    memset(side, 0, sizeof(*side));
    side->pixel_at = (unsigned long long *)calloc((size_t)resident->count + 1u, sizeof(unsigned long long));
    side->pixel_kept = (unsigned long long *)calloc((size_t)resident->count + 1u, sizeof(unsigned long long));
    side->byte_start = (unsigned long long *)calloc((size_t)resident->count + 1u, sizeof(unsigned long long));
    side->bytes = (unsigned char *)malloc((size_t)kept + 1u);
    side->name_start = (unsigned long long *)calloc((size_t)resident->count + 1u, sizeof(unsigned long long));
    side->names = (char *)malloc((size_t)named + 1u);
    side->member_crc = (unsigned long long *)calloc((size_t)resident->count + 1u, sizeof(unsigned long long));
    side->member_bytes = (unsigned long long *)calloc((size_t)resident->count + 1u, sizeof(unsigned long long));
    if (!DICOM_CHECK((side->pixel_at != NULL) && (side->pixel_kept != NULL) && (side->byte_start != NULL) &&
                         (side->bytes != NULL) && (side->name_start != NULL) && (side->names != NULL) &&
                         (side->member_crc != NULL) && (side->member_bytes != NULL),
                     side, error, ENGINE_ERROR_RESOURCE))
    {
        dicom_side_release(side);
        return 0;
    }
    unsigned long long byte_at = 0ull;
    unsigned long long name_at = 0ull;
    for (unsigned long long place = 0ull; place < resident->count; place += 1ull)
    {
        const DicomSlice *const slice = &resident->slices[resident->order[place]];
        const unsigned long long after =
            (slice->pixel_kept != 0ull) ? slice->pixel_at : (slice->pixel_at + slice->pixel_bytes);
        side->pixel_at[place] = slice->pixel_at;
        side->pixel_kept[place] = slice->pixel_kept;
        side->byte_start[place] = byte_at;
        memcpy(side->bytes + byte_at, slice->member, (size_t)slice->pixel_at);
        byte_at += slice->pixel_at;
        memcpy(side->bytes + byte_at, slice->member + after, (size_t)(slice->member_bytes - after));
        byte_at += slice->member_bytes - after;
        side->name_start[place] = name_at;
        memcpy(side->names + name_at, slice->name, (size_t)slice->name_length);
        name_at += slice->name_length;
        side->member_crc[place] = slice->member_crc;
        side->member_bytes[place] = slice->member_bytes;
    }
    side->byte_start[resident->count] = byte_at;
    side->name_start[resident->count] = name_at;
    side->leaves = resident->count;
    return 1;
}

long long dicom_read(const EngineArrayRead *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return -1LL;
    }
    EngineError *const error = request->error;
    if (!DICOM_CHECK((request->extent != NULL) && (request->out != NULL), request, error, ENGINE_ERROR_REQUEST) ||
        !dicom_open(request->tools, request->path, request->member, error))
    {
        return -1LL;
    }
    EngineArrayExtent found;
    dicom_extent(&found);
    const DicomResident *const resident = &g_dicom_resident;
    const unsigned long long slice_bytes = resident->slices[0].pixel_bytes;
    const unsigned long long total = slice_bytes * resident->count;
    int agrees = (found.rank == request->extent->rank) && (found.element_bytes == request->extent->element_bytes) &&
                 (found.element_kind == request->extent->element_kind) && (request->first == 0ull) &&
                 (request->end == 1ull) && (total <= request->out_capacity);
    for (unsigned int axis = 0u; agrees && (axis < found.rank); axis += 1u)
    {
        agrees = (found.sizes[axis] == request->extent->sizes[axis]);
    }
    if (!DICOM_CHECK(agrees, request->extent, error, ENGINE_ERROR_REQUEST))
    {
        dicom_resident_release();
        return -1LL;
    }
    for (unsigned long long place = 0ull; place < resident->count; place += 1ull)
    {
        DicomSlice *const slice = &resident->slices[resident->order[place]];
        unsigned char *const pixels = request->out + (place * slice_bytes);
        memcpy(pixels, slice->member + slice->pixel_at, (size_t)slice_bytes);
        if (slice->pixel_representation != 0u)
        {
            slice->pixel_kept = dicom_sign_extend(slice, pixels);
        }
    }
    const int sided = (request->side == NULL) || dicom_side_fill(request->side, error);
    dicom_resident_release();
    // the total fits the caller's capacity, a size in memory, and so fits a long long
    return sided ? (long long)total : -1LL;
}
