// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// dicom_element.c: data elements, items and sequences
#include "dicom_internal.h"

DicomResident g_dicom_resident;

unsigned int s_dicom_keyed;

unsigned long long dicom_little(const unsigned char *bytes, unsigned int count)
{
    unsigned long long value = 0ull;
    for (unsigned int place = count; place > 0u; place -= 1u)
    {
        value = (value << 8u) | (unsigned long long)bytes[place - 1u];
    }
    return value;
}

static int dicom_long_form(const char vr[2])
{
    static const char LONG_FORMS[13][2] = {{'O', 'B'}, {'O', 'D'}, {'O', 'F'}, {'O', 'L'}, {'O', 'V'},
                                           {'O', 'W'}, {'S', 'Q'}, {'U', 'C'}, {'U', 'N'}, {'U', 'R'},
                                           {'U', 'T'}, {'S', 'V'}, {'U', 'V'}};
    for (unsigned int form = 0u; form < 13u; form += 1u)
    {
        if ((vr[0] == LONG_FORMS[form][0]) && (vr[1] == LONG_FORMS[form][1]))
        {
            return 1;
        }
    }
    return 0;
}

int dicom_element(DicomWalk *walk, int explicit_vr, DicomElement *element, EngineError *error)
{
    if (!DICOM_CHECK((walk->at <= walk->length) && ((walk->length - walk->at) >= 8ull), &walk->at, error,
                     ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    const unsigned char *const head = walk->bytes + walk->at;
    // a tag's group and element are 16 bit fields, and fit an unsigned int exactly
    element->group = (unsigned int)dicom_little(head, 2u);
    // a tag's group and element are 16 bit fields, and fit an unsigned int exactly
    element->element = (unsigned int)dicom_little(head + 2u, 2u);
    element->vr[0] = ' ';
    element->vr[1] = ' ';
    unsigned long long length = 0ull;
    unsigned long long header = 8ull;
    if (element->group == DICOM_ITEM_GROUP)
    {
        length = dicom_little(head + 4u, 4u);
    }
    else if (explicit_vr != 0)
    {
        // a VR is two ASCII characters, each fits in a char
        element->vr[0] = (char)head[4];
        // a VR is two ASCII characters, each fits in a char
        element->vr[1] = (char)head[5];
        if (dicom_long_form(element->vr))
        {
            if (!DICOM_CHECK((walk->length - walk->at) >= 12ull, head, error, ENGINE_ERROR_REQUEST))
            {
                return 0;
            }
            length = dicom_little(head + 8u, 4u);
            header = 12ull;
        }
        else
        {
            length = dicom_little(head + 6u, 2u);
        }
    }
    else
    {
        length = dicom_little(head + 4u, 4u);
    }
    element->value_at = walk->at + header;
    element->undefined = (length == DICOM_UNDEFINED) ? 1 : 0;
    element->value_length = (element->undefined != 0) ? 0ull : length;
    if (!DICOM_CHECK((element->undefined != 0) || (element->value_length <= (walk->length - element->value_at)), head,
                     error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    walk->at = element->value_at;
    return 1;
}

static int dicom_skip_item(DicomWalk *walk, int explicit_vr, EngineError *error)
{
    for (;;)
    {
        DicomElement element;
        if (!dicom_element(walk, explicit_vr, &element, error))
        {
            return 0;
        }
        if ((element.group == DICOM_ITEM_GROUP) && (element.element == DICOM_ITEM_END))
        {
            return 1;
        }
        if (element.undefined != 0)
        {
            const int nested_explicit = ((element.vr[0] == 'U') && (element.vr[1] == 'N')) ? 0 : explicit_vr;
            if (!dicom_skip_sequence(walk, nested_explicit, error))
            {
                return 0;
            }
            continue;
        }
        walk->at = element.value_at + element.value_length;
    }
}

int dicom_skip_sequence(DicomWalk *walk, int explicit_vr, EngineError *error)
{
    for (;;)
    {
        DicomElement element;
        if (!dicom_element(walk, explicit_vr, &element, error))
        {
            return 0;
        }
        if (!DICOM_CHECK(element.group == DICOM_ITEM_GROUP, walk->bytes + element.value_at, error,
                         ENGINE_ERROR_REQUEST))
        {
            return 0;
        }
        if (element.element == DICOM_SEQUENCE_END)
        {
            return 1;
        }
        if (!DICOM_CHECK(element.element == DICOM_ITEM, walk->bytes + element.value_at, error, ENGINE_ERROR_REQUEST))
        {
            return 0;
        }
        if (element.undefined != 0)
        {
            if (!dicom_skip_item(walk, explicit_vr, error))
            {
                return 0;
            }
            continue;
        }
        walk->at = element.value_at + element.value_length;
    }
}
