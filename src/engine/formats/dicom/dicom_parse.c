// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// dicom_parse.c: the parse of a file and the gathering of a series
#include "dicom_internal.h"

static const char dicom_explicit_little[] = "1.2.840.10008.1.2.1";

static const char dicom_implicit_little[] = "1.2.840.10008.1.2";

static int dicom_us(const DicomWalk *walk, const DicomElement *element, unsigned int *out, EngineError *error)
{
    if (!DICOM_CHECK(element->value_length >= 2ull, walk->bytes + element->value_at, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    // a US value is 16 bits, and fits an unsigned int exactly
    *out = (unsigned int)dicom_little(walk->bytes + element->value_at, 2u);
    return 1;
}

static int dicom_transfer_syntax(const unsigned char *value, unsigned long long length, int *explicit_vr,
                                 EngineError *error)
{
    unsigned long long end = length;
    while ((end > 0ull) && ((value[end - 1ull] == '\0') || (value[end - 1ull] == ' ')))
    {
        end -= 1ull;
    }
    const unsigned long long explicit_length = sizeof(dicom_explicit_little) - 1u;
    const unsigned long long implicit_length = sizeof(dicom_implicit_little) - 1u;
    if ((end == explicit_length) && (memcmp(value, dicom_explicit_little, (size_t)explicit_length) == 0))
    {
        *explicit_vr = 1;
        return 1;
    }
    if ((end == implicit_length) && (memcmp(value, dicom_implicit_little, (size_t)implicit_length) == 0))
    {
        *explicit_vr = 0;
        return 1;
    }
    return DICOM_CHECK(0, value, error, ENGINE_ERROR_REQUEST);
}

static int dicom_parse(DicomSlice *slice, EngineError *error)
{
    const unsigned char *const bytes = slice->member;
    if (!DICOM_CHECK((slice->member_bytes >= (DICOM_PREAMBLE + 4ull)) &&
                         (memcmp(bytes + DICOM_PREAMBLE, "DICM", 4u) == 0),
                     bytes, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    DicomWalk walk = {bytes, slice->member_bytes, DICOM_PREAMBLE + 4ull};
    int explicit_vr = -1;
    while (((walk.length - walk.at) >= 8ull) && (dicom_little(bytes + walk.at, 2u) == 0x0002ull))
    {
        DicomElement element;
        if (!dicom_element(&walk, 1, &element, error) ||
            !DICOM_CHECK(element.undefined == 0, bytes + element.value_at, error, ENGINE_ERROR_REQUEST))
        {
            return 0;
        }
        if ((element.element == 0x0010u) &&
            !dicom_transfer_syntax(bytes + element.value_at, element.value_length, &explicit_vr, error))
        {
            return 0;
        }
        walk.at = element.value_at + element.value_length;
    }
    if (!DICOM_CHECK(explicit_vr >= 0, bytes, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    unsigned int seen_pixels = 0u;
    unsigned int seen_rows = 0u;
    unsigned int seen_columns = 0u;
    unsigned int seen_bits = 0u;
    unsigned int seen_samples = 0u;
    unsigned long long pixel_value_length = 0ull;
    while ((seen_pixels == 0u) && (walk.at < walk.length))
    {
        DicomElement element;
        if (!dicom_element(&walk, explicit_vr, &element, error))
        {
            return 0;
        }
        const unsigned char *const value = bytes + element.value_at;
        const unsigned int tag_group = element.group;
        const unsigned int tag_element = element.element;
        if ((tag_group == 0x7FE0u) && (tag_element == 0x0010u))
        {
            if (!DICOM_CHECK(element.undefined == 0, value, error, ENGINE_ERROR_REQUEST))
            {
                return 0;
            }
            slice->pixel_at = element.value_at;
            pixel_value_length = element.value_length;
            seen_pixels = 1u;
            continue;
        }
        if (element.undefined != 0)
        {
            const int nested_explicit = ((element.vr[0] == 'U') && (element.vr[1] == 'N')) ? 0 : explicit_vr;
            if (!dicom_skip_sequence(&walk, nested_explicit, error))
            {
                return 0;
            }
            continue;
        }
        int ok = 1;
        if ((tag_group == 0x0028u) && (tag_element == 0x0002u))
        {
            ok = dicom_us(&walk, &element, &slice->samples, error);
            seen_samples = 1u;
        }
        else if ((tag_group == 0x0028u) && (tag_element == 0x0010u))
        {
            ok = dicom_us(&walk, &element, &slice->rows, error);
            seen_rows = 1u;
        }
        else if ((tag_group == 0x0028u) && (tag_element == 0x0011u))
        {
            ok = dicom_us(&walk, &element, &slice->columns, error);
            seen_columns = 1u;
        }
        else if ((tag_group == 0x0028u) && (tag_element == 0x0100u))
        {
            ok = dicom_us(&walk, &element, &slice->bits_allocated, error);
            seen_bits = 1u;
        }
        else if ((tag_group == 0x0028u) && (tag_element == 0x0101u))
        {
            ok = dicom_us(&walk, &element, &slice->bits_stored, error);
            slice->has_stored = 1u;
        }
        else if ((tag_group == 0x0028u) && (tag_element == 0x0102u))
        {
            ok = dicom_us(&walk, &element, &slice->high_bit, error);
            slice->has_high = 1u;
        }
        else if ((tag_group == 0x0028u) && (tag_element == 0x0103u))
        {
            ok = dicom_us(&walk, &element, &slice->pixel_representation, error);
        }
        else if ((tag_group == 0x0020u) && (tag_element == 0x0032u) && (element.value_length != 0ull))
        {
            ok = dicom_decimal_list(value, element.value_length, 3u, slice->position, error);
            slice->has_position = 1u;
        }
        else if ((tag_group == 0x0020u) && (tag_element == 0x0037u) && (element.value_length != 0ull))
        {
            ok = dicom_decimal_list(value, element.value_length, 6u, slice->orientation, error);
            slice->has_orientation = 1u;
        }
        else if ((tag_group == 0x0020u) && (tag_element == 0x0013u) && (element.value_length != 0ull))
        {
            ok = dicom_decimal_list(value, element.value_length, 1u, &slice->instance, error);
            slice->has_instance = 1u;
        }
        else if ((tag_group == 0x0008u) && (tag_element == 0x0018u))
        {
            unsigned long long end = element.value_length;
            while ((end > 0ull) && ((value[end - 1ull] == '\0') || (value[end - 1ull] == ' ')))
            {
                end -= 1ull;
            }
            slice->sop = value;
            slice->sop_length = end;
        }
        if (!ok)
        {
            return 0;
        }
        walk.at = element.value_at + element.value_length;
    }
    if (!DICOM_CHECK((seen_pixels != 0u) && (seen_rows != 0u) && (seen_columns != 0u) && (seen_bits != 0u) &&
                         (seen_samples != 0u) && ((slice->bits_allocated % 8u) == 0u) && (slice->bits_allocated != 0u),
                     bytes, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    slice->pixel_bytes =
        (unsigned long long)slice->rows * slice->columns * slice->samples * (slice->bits_allocated / 8u);
    const int representation_valid =
        (slice->pixel_representation == 0u) ||
        ((slice->has_stored != 0u) && (slice->has_high != 0u) && (slice->bits_stored != 0u) &&
         (slice->high_bit < slice->bits_allocated) && (slice->bits_stored <= (slice->high_bit + 1u)));
    return DICOM_CHECK(slice->pixel_bytes <= pixel_value_length, bytes + slice->pixel_at, error,
                       ENGINE_ERROR_REQUEST) &&
           DICOM_CHECK(representation_valid, &slice->bits_stored, error, ENGINE_ERROR_REQUEST);
}

void dicom_resident_release(void)
{
    DicomResident *const resident = &g_dicom_resident;
    for (unsigned long long slot = 0ull; (resident->slices != NULL) && (slot < resident->count); slot += 1ull)
    {
        free(resident->slices[slot].member);
        free(resident->slices[slot].name);
    }
    free(resident->slices);
    free(resident->order);
    free(resident->path);
    free(resident->member);
    memset(resident, 0, sizeof(*resident));
}

static int dicom_prefix_length(const unsigned char *name, unsigned long long length, unsigned long long *prefix)
{
    unsigned long long last = length;
    while ((last > 0ull) && (name[last - 1ull] != '/'))
    {
        last -= 1ull;
    }
    *prefix = last;
    return (last != 0ull) ? 1 : 0;
}

int dicom_gather(const EngineIngestTools *tools, const char *path, const ZipArchive *archive, unsigned long long first,
                 unsigned long long count, EngineError *error)
{
    DicomResident *const resident = &g_dicom_resident;
    resident->slices = (DicomSlice *)calloc((size_t)count + 1u, sizeof(DicomSlice));
    resident->order = (unsigned long long *)calloc((size_t)count + 1u, sizeof(unsigned long long));
    if (!DICOM_CHECK((resident->slices != NULL) && (resident->order != NULL), &resident->slices, error,
                     ENGINE_ERROR_RESOURCE))
    {
        return 0;
    }
    const unsigned char *series = NULL;
    unsigned long long series_length = 0ull;
    for (unsigned long long slot = first; slot < (first + count); slot += 1ull)
    {
        ZipEntry entry;
        if (!zip_entry_at(archive, slot, &entry, error))
        {
            return 0;
        }
        if ((entry.name_length == 0ull) || (entry.name[entry.name_length - 1ull] == '/'))
        {
            continue;
        }
        unsigned long long prefix = 0ull;
        const int named = dicom_prefix_length(entry.name, entry.name_length, &prefix);
        if (series == NULL)
        {
            series = entry.name;
            series_length = prefix;
        }
        if (!DICOM_CHECK(named && (prefix == series_length) && (memcmp(entry.name, series, (size_t)prefix) == 0),
                         entry.name, error, ENGINE_ERROR_REQUEST))
        {
            return 0;
        }
        DicomSlice *const slice = &resident->slices[resident->count];
        slice->member = (unsigned char *)malloc((size_t)entry.uncompressed + 1u);
        slice->name = (char *)malloc((size_t)entry.name_length + 1u);
        if (!DICOM_CHECK((slice->member != NULL) && (slice->name != NULL), &entry, error, ENGINE_ERROR_RESOURCE))
        {
            resident->count += 1ull;
            return 0;
        }
        resident->count += 1ull;
        memcpy(slice->name, entry.name, (size_t)entry.name_length);
        slice->name[entry.name_length] = '\0';
        slice->name_length = entry.name_length;
        slice->member_crc = entry.crc;
        slice->member_bytes = entry.uncompressed;
        if ((zip_member_read(tools, path, archive, &entry, slice->member, entry.uncompressed, error) == ZIP_ERROR) ||
            !dicom_parse(slice, error))
        {
            return 0;
        }
    }
    return DICOM_CHECK(resident->count != 0ull, archive, error, ENGINE_ERROR_REQUEST);
}

int dicom_agree(EngineError *error)
{
    DicomResident *const resident = &g_dicom_resident;
    const DicomSlice *const lead = &resident->slices[0];
    unsigned int keyed = 1u;
    for (unsigned long long slot = 0ull; slot < resident->count; slot += 1ull)
    {
        const DicomSlice *const slice = &resident->slices[slot];
        if (!DICOM_CHECK((slice->rows == lead->rows) && (slice->columns == lead->columns) &&
                             (slice->bits_allocated == lead->bits_allocated) && (slice->samples == lead->samples) &&
                             (slice->pixel_representation == lead->pixel_representation),
                         slice, error, ENGINE_ERROR_REQUEST))
        {
            return 0;
        }
        keyed = ((keyed != 0u) && (slice->has_position != 0u) && (lead->has_orientation != 0u)) ? 1u : 0u;
    }
    resident->keyed = keyed;
    return DICOM_CHECK(lead->samples == 1u, lead, error, ENGINE_ERROR_REQUEST);
}

int dicom_sort(EngineError *error)
{
    DicomResident *const resident = &g_dicom_resident;
    long long key_floor = 0ll;
    long long instance_floor = 0ll;
    for (unsigned long long slot = 0ull; slot < resident->count; slot += 1ull)
    {
        DicomSlice *const slice = &resident->slices[slot];
        resident->order[slot] = slot;
        if ((resident->keyed != 0u) && !dicom_slice_key(resident->slices[0].orientation, slice, error))
        {
            return 0;
        }
        key_floor = ((slot == 0ull) || (slice->key.exponent < key_floor)) ? slice->key.exponent : key_floor;
        instance_floor =
            ((slot == 0ull) || (slice->instance.exponent < instance_floor)) ? slice->instance.exponent : instance_floor;
    }
    for (unsigned long long slot = 0ull; slot < resident->count; slot += 1ull)
    {
        DicomSlice *const slice = &resident->slices[slot];
        if (((resident->keyed != 0u) && !dicom_decimal_align(&slice->key, key_floor, error)) ||
            ((slice->has_instance != 0u) && !dicom_decimal_align(&slice->instance, instance_floor, error)))
        {
            return 0;
        }
    }
    s_dicom_sorting = resident->slices;
    s_dicom_keyed = resident->keyed;
    qsort(resident->order, (size_t)resident->count, sizeof(unsigned long long), dicom_order_slices);
    s_dicom_sorting = NULL;
    return 1;
}
