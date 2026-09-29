// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// points_check: S0's and S1's files, read apart from the scan by a reader of their own. From the set's scan.set it
// takes the samples the contrast was counted over and sums their .readings; from that sum it rebuilds the set's
// readings, the contrast's bits (the least b with readings >> b == 0) and the contrast C (the running count). scan.set
// must name the same readings and bits. Then each named sample's .points: its head (frames, depth, height, width,
// limbs, bits), the set's readings and C, which must agree across the samples and equal the rebuilt ones; and each
// frame, whose count must fit the view, whose voxels must rise strictly and lie inside the view, and whose levels must
// each be positive (the top limb's top bit clear, and not every limb 0). A sample's readings must be its frames times
// its view, and its .points must end at its last frame. Reads only; every word is little-endian, as the scan writes it.
//   points_check <set> <sample> [<sample> ...]
//
// The formats, restated here from what the scan writes, not read from its code: a change to them must be made here too.
//   scan.set   "readings R", "bits B", "samples S", then the S names, a line each
//   .readings  65536 64-bit counts, one a reading's value, then the footing: held, lo, hi, lo's steps, hi's steps
//   .points    six 32-bit words (frames, depth, height, width, limbs, bits), the readings (64 bits), C (65536 64-bit
//              words), then a frame after another: its count, each point's voxel, each point's levels (limbs words,
//              the lowest first)
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define POINTS_CHECK_READINGS 65536u

#define POINTS_CHECK_FOOTING_WORDS 5u

#define POINTS_CHECK_HEAD_WORDS 6u

#define POINTS_CHECK_PATH 4096u

#define POINTS_CHECK_LINE 4096u

#define POINTS_CHECK_TOP_BIT 0x80000000u

// the faults, each counted and named in the last line
enum
{
    POINTS_CHECK_SET_UNREAD = 0,
    POINTS_CHECK_READINGS_UNREAD,
    POINTS_CHECK_SUM_PAST_64,
    POINTS_CHECK_SET_NOT_REBUILT,
    POINTS_CHECK_NOT_LISTED,
    POINTS_CHECK_POINTS_UNREAD,
    POINTS_CHECK_HEAD_DIFFERS,
    POINTS_CHECK_HEAD_NOT_REBUILT,
    POINTS_CHECK_EMPTY_VIEW,
    POINTS_CHECK_COUNT_PAST_VIEW,
    POINTS_CHECK_FRAME_SHORT,
    POINTS_CHECK_OUT_OF_ORDER,
    POINTS_CHECK_OUTSIDE,
    POINTS_CHECK_NOT_POSITIVE,
    POINTS_CHECK_PAST_LAST_FRAME,
    POINTS_CHECK_READINGS_NOT_VIEW,
    POINTS_CHECK_FAULTS
};

static const char *const POINTS_CHECK_FAULT_NAMES[POINTS_CHECK_FAULTS] = {
    "scan.set does not read",
    "a .readings does not read whole",
    "a sum passes 64 bits",
    "scan.set is not the rebuilt readings and bits",
    "a sample not in scan.set",
    "a .points does not open or its head does not read",
    "a head differs from the first sample's",
    "a head is not the rebuilt readings, bits and C",
    "a view or frame count of 0",
    "a frame's count past its view",
    "a frame stops short",
    "voxels out of order",
    "voxels outside the view",
    "levels not positive",
    "a .points goes on past its last frame",
    "a sample's readings are not its frames times its view"};

typedef struct
{
    char **names;
    unsigned int count;
    unsigned long long readings;
    unsigned int bits;
    unsigned long long *totals;
    unsigned long long *counts;
    unsigned long long *contrast;
    unsigned long long rebuilt_readings;
    unsigned int rebuilt_bits;
} PointsCheckSet;

typedef struct
{
    unsigned int *voxels;
    unsigned int *levels;
    size_t voxel_capacity;
    size_t level_capacity;
} PointsCheckWorkspace;

typedef struct
{
    int recorded;
    unsigned int head[POINTS_CHECK_HEAD_WORDS];
    unsigned long long readings;
    unsigned long long *contrast;
} PointsCheckFirst;

static int points_check_path(char *path, size_t capacity, const char *set, const char *sample, const char *suffix)
{
    const int written = snprintf(path, capacity, "%s/%s/%s%s", set, sample, sample, suffix);
    // a non-negative length is compared whole against the capacity
    return (written > 0) && ((size_t)written < capacity);
}

static int points_check_read(FILE *file, void *words, size_t bytes)
{
    return (bytes == 0u) || (fread(words, 1u, bytes, file) == bytes);
}

// the file's place is its end: nothing past what was read
static int points_check_ended(FILE *file)
{
    return (fgetc(file) == EOF) && (feof(file) != 0);
}

// a line of scan.set with its line feed taken off, or 0 when none reads or it does not fit
static int points_check_line(FILE *file, char *line, size_t capacity)
{
    if (fgets(line, (int)capacity, file) == NULL)
    {
        return 0;
    }
    const size_t length = strlen(line);
    if ((length == 0u) || (line[length - 1u] != '\n'))
    {
        return 0;
    }
    line[length - 1u] = '\0';
    return 1;
}

static void points_check_set_free(PointsCheckSet *set)
{
    for (unsigned int at = 0u; (set->names != NULL) && (at < set->count); at += 1u)
    {
        free(set->names[at]);
    }
    free(set->names);
    free(set->totals);
    free(set->counts);
    free(set->contrast);
    memset(set, 0, sizeof(*set));
}

// scan.set's readings, bits and names
static int points_check_set_read(const char *root, PointsCheckSet *set)
{
    char path[POINTS_CHECK_PATH];
    const int written = snprintf(path, sizeof(path), "%s/scan.set", root);
    FILE *const file = ((written > 0) && ((size_t)written < sizeof(path))) ? fopen(path, "rb") : NULL;
    char line[POINTS_CHECK_LINE];
    char rest = '\0';
    int ok = (file != NULL) && points_check_line(file, line, sizeof(line)) &&
             (sscanf(line, "readings %llu%c", &set->readings, &rest) == 1) &&
             points_check_line(file, line, sizeof(line)) && (sscanf(line, "bits %u%c", &set->bits, &rest) == 1) &&
             points_check_line(file, line, sizeof(line)) && (sscanf(line, "samples %u%c", &set->count, &rest) == 1) &&
             (set->count != 0u);
    set->names = ok ? (char **)calloc(set->count, sizeof(char *)) : NULL;
    set->totals = ok ? (unsigned long long *)calloc(set->count, sizeof(unsigned long long)) : NULL;
    ok = ok && (set->names != NULL) && (set->totals != NULL);
    for (unsigned int at = 0u; ok && (at < set->count); at += 1u)
    {
        ok = points_check_line(file, line, sizeof(line)) && (line[0] != '\0');
        set->names[at] = ok ? (char *)malloc(strlen(line) + 1u) : NULL;
        ok = ok && (set->names[at] != NULL);
        if (ok)
        {
            memcpy(set->names[at], line, strlen(line) + 1u);
        }
    }
    ok = ok && points_check_ended(file);
    if (file != NULL)
    {
        fclose(file);
    }
    if (ok == 0)
    {
        printf("  %s does not read: readings, bits, samples and one name a line, and nothing after them\n", path);
    }
    return ok;
}

// every sample's .readings summed; the set's readings, bits and C rebuilt from the sum; the footings' ranges printed
static int points_check_rebuild(const char *root, PointsCheckSet *set, unsigned long long *faults)
{
    set->counts = (unsigned long long *)calloc(POINTS_CHECK_READINGS, sizeof(unsigned long long));
    set->contrast = (unsigned long long *)calloc(POINTS_CHECK_READINGS, sizeof(unsigned long long));
    unsigned long long *const one = (unsigned long long *)malloc(POINTS_CHECK_READINGS * sizeof(unsigned long long));
    if ((set->counts == NULL) || (set->contrast == NULL) || (one == NULL))
    {
        printf("  the counts' memory could not be reserved\n");
        free(one);
        return 0;
    }
    unsigned long long found_count = 0ull;
    unsigned long long least[POINTS_CHECK_FOOTING_WORDS];
    unsigned long long maximum[POINTS_CHECK_FOOTING_WORDS];
    for (unsigned int word = 0u; word < POINTS_CHECK_FOOTING_WORDS; word += 1u)
    {
        least[word] = ~0ull;
        maximum[word] = 0ull;
    }
    int complete = 1;
    for (unsigned int at = 0u; at < set->count; at += 1u)
    {
        char path[POINTS_CHECK_PATH];
        unsigned long long footing[POINTS_CHECK_FOOTING_WORDS];
        FILE *const file =
            points_check_path(path, sizeof(path), root, set->names[at], ".readings") ? fopen(path, "rb") : NULL;
        const int read = (file != NULL) && points_check_read(file, one, POINTS_CHECK_READINGS * sizeof(*one)) &&
                         points_check_read(file, footing, sizeof(footing)) && points_check_ended(file);
        if (file != NULL)
        {
            fclose(file);
        }
        if (read == 0)
        {
            printf("  %s: its .readings does not read whole: 65536 counts and a footing of 5 words, nothing after\n",
                   set->names[at]);
            faults[POINTS_CHECK_READINGS_UNREAD] += 1ull;
            complete = 0;
            continue;
        }
        unsigned long long total = 0ull;
        for (unsigned int value = 0u; value < POINTS_CHECK_READINGS; value += 1u)
        {
            const int fits = (one[value] <= (~0ull - total)) && (one[value] <= (~0ull - set->counts[value]));
            faults[POINTS_CHECK_SUM_PAST_64] += fits ? 0ull : 1ull;
            complete = complete && fits;
            total += fits ? one[value] : 0ull;
            set->counts[value] += fits ? one[value] : 0ull;
        }
        set->totals[at] = total;
        found_count += (footing[0] == 1ull) ? 1ull : 0ull;
        for (unsigned int word = 1u; (footing[0] == 1ull) && (word < POINTS_CHECK_FOOTING_WORDS); word += 1u)
        {
            least[word] = (footing[word] < least[word]) ? footing[word] : least[word];
            maximum[word] = (footing[word] > maximum[word]) ? footing[word] : maximum[word];
        }
    }
    free(one);
    unsigned long long running = 0ull;
    for (unsigned int value = 0u; value < POINTS_CHECK_READINGS; value += 1u)
    {
        const int fits = set->counts[value] <= (~0ull - running);
        faults[POINTS_CHECK_SUM_PAST_64] += fits ? 0ull : 1ull;
        complete = complete && fits;
        running += fits ? set->counts[value] : 0ull;
        set->contrast[value] = running;
    }
    set->rebuilt_readings = running;
    set->rebuilt_bits = 0u;
    while ((set->rebuilt_bits < 64u) && ((running >> set->rebuilt_bits) != 0ull))
    {
        set->rebuilt_bits += 1u;
    }
    const int agrees = complete && (set->rebuilt_readings == set->readings) && (set->rebuilt_bits == set->bits);
    faults[POINTS_CHECK_SET_NOT_REBUILT] += agrees ? 0ull : 1ull;
    printf("  rebuilt from the %u samples' .readings: %llu readings, so the contrast is %u bits; scan.set reads %llu"
           " readings and %u bits: %s\n",
           set->count, set->rebuilt_readings, set->rebuilt_bits, set->readings, set->bits,
           agrees ? "the same" : "NOT the same");
    printf(
        "  the footings as stored: held on %llu of %u; lo %llu to %llu, hi %llu to %llu, lo's steps %llu to %llu, hi's"
        " steps %llu to %llu\n",
        found_count, set->count, least[1], maximum[1], least[2], maximum[2], least[3], maximum[3], least[4],
        maximum[4]);
    return complete;
}

static int points_check_reserve(PointsCheckWorkspace *capacity, size_t voxels, size_t levels)
{
    if (voxels > capacity->voxel_capacity)
    {
        unsigned int *const grown = (unsigned int *)realloc(capacity->voxels, (voxels + 1u) * sizeof(unsigned int));
        capacity->voxels = (grown != NULL) ? grown : capacity->voxels;
        capacity->voxel_capacity = (grown != NULL) ? voxels : capacity->voxel_capacity;
    }
    if (levels > capacity->level_capacity)
    {
        unsigned int *const grown = (unsigned int *)realloc(capacity->levels, (levels + 1u) * sizeof(unsigned int));
        capacity->levels = (grown != NULL) ? grown : capacity->levels;
        capacity->level_capacity = (grown != NULL) ? levels : capacity->level_capacity;
    }
    return (voxels <= capacity->voxel_capacity) && (levels <= capacity->level_capacity);
}

// one sample's .points against the set, its faults added to `faults`; 1 when it holds none
static int points_check_sample(const char *root, const char *sample, const PointsCheckSet *set, PointsCheckFirst *first,
                               PointsCheckWorkspace *capacity, unsigned long long *faults,
                               unsigned long long *points_seen)
{
    unsigned long long mine[POINTS_CHECK_FAULTS];
    memset(mine, 0, sizeof(mine));
    unsigned int listed = set->count;
    for (unsigned int at = 0u; at < set->count; at += 1u)
    {
        listed = ((listed == set->count) && (strcmp(set->names[at], sample) == 0)) ? at : listed;
    }
    mine[POINTS_CHECK_NOT_LISTED] += (listed == set->count) ? 1ull : 0ull;
    char path[POINTS_CHECK_PATH];
    FILE *const file = points_check_path(path, sizeof(path), root, sample, ".points") ? fopen(path, "rb") : NULL;
    unsigned int head[POINTS_CHECK_HEAD_WORDS];
    unsigned long long readings = 0ull;
    unsigned long long *const contrast =
        (unsigned long long *)malloc(POINTS_CHECK_READINGS * sizeof(unsigned long long));
    int ok = (file != NULL) && (contrast != NULL) && points_check_read(file, head, sizeof(head)) &&
             points_check_read(file, &readings, sizeof(readings)) &&
             points_check_read(file, contrast, POINTS_CHECK_READINGS * sizeof(unsigned long long));
    if (ok == 0)
    {
        printf("  %s: its .points does not open, or its head does not read\n", sample);
        faults[POINTS_CHECK_POINTS_UNREAD] += 1ull;
        faults[POINTS_CHECK_NOT_LISTED] += mine[POINTS_CHECK_NOT_LISTED];
        if (file != NULL)
        {
            fclose(file);
        }
        free(contrast);
        return 0;
    }
    unsigned int contrast_differs = POINTS_CHECK_READINGS;
    for (unsigned int value = 0u; value < POINTS_CHECK_READINGS; value += 1u)
    {
        contrast_differs = ((contrast_differs == POINTS_CHECK_READINGS) && (contrast[value] != set->contrast[value]))
                               ? value
                               : contrast_differs;
    }
    const int rebuilt = (head[5] == set->rebuilt_bits) && (readings == set->rebuilt_readings) &&
                        (contrast_differs == POINTS_CHECK_READINGS);
    mine[POINTS_CHECK_HEAD_NOT_REBUILT] += rebuilt ? 0ull : 1ull;
    if (first->recorded == 0)
    {
        first->recorded = 1;
        memcpy(first->head, head, sizeof(head));
        first->readings = readings;
        memcpy(first->contrast, contrast, POINTS_CHECK_READINGS * sizeof(unsigned long long));
    }
    const int agrees = (head[4] == first->head[4]) && (head[5] == first->head[5]) && (readings == first->readings) &&
                       (memcmp(contrast, first->contrast, POINTS_CHECK_READINGS * sizeof(unsigned long long)) == 0);
    mine[POINTS_CHECK_HEAD_DIFFERS] += agrees ? 0ull : 1ull;
    free(contrast);
    const unsigned long long plane = (unsigned long long)head[2] * head[3];
    const unsigned long long view = plane * head[1];
    mine[POINTS_CHECK_EMPTY_VIEW] += ((head[0] == 0u) || (view == 0ull)) ? 1ull : 0ull;
    const unsigned int limbs = head[4];
    unsigned long long points = 0ull;
    unsigned int least = 0xFFFFFFFFu;
    unsigned int maximum = 0u;
    unsigned int frame = 0u;
    for (frame = 0u; ok && (frame < head[0]); frame += 1u)
    {
        unsigned int count = 0u;
        ok = points_check_read(file, &count, sizeof(count));
        if (ok && ((unsigned long long)count > view))
        {
            mine[POINTS_CHECK_COUNT_PAST_VIEW] += 1ull;
            ok = 0;
        }
        // a count within the view is below 2^32, and its levels are stored only when their words fit a size_t
        const unsigned long long words = (unsigned long long)count * limbs;
        ok = ok && ((limbs == 0u) || ((words / limbs) == count)) && (words <= (SIZE_MAX / sizeof(unsigned int))) &&
             points_check_reserve(capacity, (size_t)count, (size_t)words) &&
             points_check_read(file, capacity->voxels, (size_t)count * sizeof(unsigned int)) &&
             points_check_read(file, capacity->levels, (size_t)words * sizeof(unsigned int));
        if (ok == 0)
        {
            mine[POINTS_CHECK_FRAME_SHORT] += (mine[POINTS_CHECK_COUNT_PAST_VIEW] == 0ull) ? 1ull : 0ull;
            break;
        }
        for (unsigned int point = 0u; point < count; point += 1u)
        {
            mine[POINTS_CHECK_OUT_OF_ORDER] +=
                ((point != 0u) && (capacity->voxels[point] <= capacity->voxels[point - 1u])) ? 1ull : 0ull;
            mine[POINTS_CHECK_OUTSIDE] += ((unsigned long long)capacity->voxels[point] >= view) ? 1ull : 0ull;
            const unsigned int *const level = &capacity->levels[(size_t)point * limbs];
            int nonzero = 0;
            for (unsigned int limb = 0u; limb < limbs; limb += 1u)
            {
                nonzero = nonzero || (level[limb] != 0u);
            }
            const int positive = (limbs != 0u) && nonzero && ((level[limbs - 1u] & POINTS_CHECK_TOP_BIT) == 0u);
            mine[POINTS_CHECK_NOT_POSITIVE] += positive ? 0ull : 1ull;
        }
        points += count;
        least = (count < least) ? count : least;
        maximum = (count > maximum) ? count : maximum;
    }
    const int ended = ok && points_check_ended(file);
    mine[POINTS_CHECK_PAST_LAST_FRAME] += (ok && (ended == 0)) ? 1ull : 0ull;
    fclose(file);
    // a sample's readings are every voxel of every frame, read once; a sample not in scan.set has no readings to hold
    const unsigned long long total = (listed != set->count) ? set->totals[listed] : 0ull;
    const int counted =
        (listed != set->count) && (head[0] != 0u) && (view <= (~0ull / head[0])) && (total == (view * head[0]));
    mine[POINTS_CHECK_READINGS_NOT_VIEW] += ((listed != set->count) && (counted == 0)) ? 1ull : 0ull;
    unsigned long long fault_count = 0ull;
    for (unsigned int fault = 0u; fault < POINTS_CHECK_FAULTS; fault += 1u)
    {
        faults[fault] += mine[fault];
        fault_count += mine[fault];
    }
    *points_seen += points;
    printf("  %-16s %4u of %4u frames of %u x %u x %u, %9llu points, %u to %u a frame; limbs %u, bits %u; not positive"
           " %llu, out of order %llu, outside %llu; C %s; readings %llu %s frames x view; %llu faults\n",
           sample, frame, head[0], head[1], head[2], head[3], points, (points != 0ull) ? least : 0u, maximum, limbs,
           head[5], mine[POINTS_CHECK_NOT_POSITIVE], mine[POINTS_CHECK_OUT_OF_ORDER], mine[POINTS_CHECK_OUTSIDE],
           (contrast_differs == POINTS_CHECK_READINGS) ? "is the rebuilt" : "differs from the rebuilt", total,
           counted ? "=" : "!=", fault_count);
    if (contrast_differs != POINTS_CHECK_READINGS)
    {
        printf("  %-16s C first differs at value %u\n", sample, contrast_differs);
    }
    return fault_count == 0ull;
}

int main(int count, char **arguments)
{
    const uint32_t probe = 1u;
    if (*(const unsigned char *)&probe != 1u)
    {
        printf("  this host is not little-endian, and the files are\n");
        return 2;
    }
    if (count < 3)
    {
        printf("  usage: points_check <set> <sample> [<sample> ...]\n");
        return 2;
    }
    const char *const root = arguments[1];
    unsigned long long faults[POINTS_CHECK_FAULTS];
    memset(faults, 0, sizeof(faults));
    PointsCheckSet set;
    memset(&set, 0, sizeof(set));
    if (points_check_set_read(root, &set) == 0)
    {
        faults[POINTS_CHECK_SET_UNREAD] += 1ull;
        printf("  faults: %s 1\n", POINTS_CHECK_FAULT_NAMES[POINTS_CHECK_SET_UNREAD]);
        points_check_set_free(&set);
        return 1;
    }
    (void)points_check_rebuild(root, &set, faults);
    PointsCheckFirst first;
    memset(&first, 0, sizeof(first));
    first.contrast = (unsigned long long *)malloc(POINTS_CHECK_READINGS * sizeof(unsigned long long));
    PointsCheckWorkspace workspace;
    memset(&workspace, 0, sizeof(workspace));
    if (first.contrast == NULL)
    {
        printf("  the first head's memory could not be reserved\n");
        points_check_set_free(&set);
        return 1;
    }
    unsigned int clean = 0u;
    unsigned long long points = 0ull;
    for (int at = 2; at < count; at += 1)
    {
        clean += points_check_sample(root, arguments[at], &set, &first, &workspace, faults, &points) ? 1u : 0u;
    }
    unsigned long long total = 0ull;
    printf("  checked %d samples, %u with no fault, %llu points; faults:", count - 2, clean, points);
    for (unsigned int fault = 0u; fault < POINTS_CHECK_FAULTS; fault += 1u)
    {
        printf("%s %s %llu", (fault == 0u) ? "" : ",", POINTS_CHECK_FAULT_NAMES[fault], faults[fault]);
        total += faults[fault];
    }
    printf("\n  %llu faults\n", total);
    free(first.contrast);
    free(workspace.voxels);
    free(workspace.levels);
    points_check_set_free(&set);
    return (total == 0ull) ? 0 : 1;
}
