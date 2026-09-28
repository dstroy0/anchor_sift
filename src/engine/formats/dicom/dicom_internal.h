// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the dicom_*.c pieces share: its includes, types and the functions one piece calls in another
#ifndef DICOM_INTERNAL_H
#define DICOM_INTERNAL_H

#include "dicom.h"

#include "exact_integer.h"
#include "zip.h"

#include <limits.h>
#include <stdlib.h>
#include <string.h>

#define DICOM_CHECK(condition_, evacaddr_, error_, kind_)                                                              \
    engine_error_check((condition_), (kind_), ENGINE_MODULE_DICOM, (unsigned int)__LINE__, (const void *)(evacaddr_),  \
                       (error_))

#define DICOM_PREAMBLE 128ull
#define DICOM_UNDEFINED 0xFFFFFFFFull
#define DICOM_ITEM_GROUP 0xFFFEu
#define DICOM_ITEM 0xE000u
#define DICOM_ITEM_END 0xE00Du
#define DICOM_SEQUENCE_END 0xE0DDu

typedef struct
{
    AnchorExactInteger mantissa;
    long long exponent;
} DicomDecimal;

typedef struct
{
    unsigned char *member;
    unsigned long long member_bytes;
    unsigned long long member_crc;
    char *name;
    unsigned long long name_length;
    unsigned long long pixel_at;
    unsigned long long pixel_bytes;
    unsigned int rows;
    unsigned int columns;
    unsigned int bits_allocated;
    unsigned int bits_stored;
    unsigned int high_bit;
    unsigned int has_stored;
    unsigned int has_high;
    unsigned int pixel_representation;
    unsigned int samples;
    unsigned long long pixel_kept;
    unsigned int has_position;
    unsigned int has_orientation;
    unsigned int has_instance;
    DicomDecimal position[3];
    DicomDecimal orientation[6];
    DicomDecimal instance;
    DicomDecimal key;
    const unsigned char *sop;
    unsigned long long sop_length;
} DicomSlice;

typedef struct
{
    char *path;
    char *member;
    DicomSlice *slices;
    unsigned long long *order;
    unsigned long long count;
    unsigned int keyed;
    int valid;
} DicomResident;

typedef struct
{
    const unsigned char *bytes;
    unsigned long long length;
    unsigned long long at;
} DicomWalk;

typedef struct
{
    unsigned int group;
    unsigned int element;
    char vr[2];
    unsigned long long value_at;
    unsigned long long value_length;
    int undefined;
} DicomElement;

extern DicomResident g_dicom_resident;

static const DicomSlice *s_dicom_sorting;

extern unsigned int s_dicom_keyed;

unsigned long long dicom_little(const unsigned char *bytes, unsigned int count);

int dicom_element(DicomWalk *walk, int explicit_vr, DicomElement *element, EngineError *error);

int dicom_skip_sequence(DicomWalk *walk, int explicit_vr, EngineError *error);

int dicom_decimal_list(const unsigned char *text, unsigned long long length, unsigned int want, DicomDecimal *out,
                       EngineError *error);

int dicom_decimal_align(DicomDecimal *value, long long exponent, EngineError *error);

int dicom_slice_key(const DicomDecimal *orientation, DicomSlice *slice, EngineError *error);

int dicom_order_slices(const void *left, const void *right);

void dicom_resident_release(void);

int dicom_gather(const EngineIngestTools *tools, const char *path, const ZipArchive *archive, unsigned long long first,
                 unsigned long long count, EngineError *error);

int dicom_agree(EngineError *error);

int dicom_sort(EngineError *error);

#endif
