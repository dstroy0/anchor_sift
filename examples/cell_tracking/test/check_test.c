// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The checkers (cell_tracking/src/check) shown to fire. Under the directory named this writes, by hand, a good set for
// each checker and one broken copy for each fault the checker names; check_test.sh runs the checkers on every copy and
// holds each exit and each fault's count against the case's.
//
// points_check's set: two samples, a and b, of two frames in a 2 x 3 x 4 view (24 voxels), two limbs a level. a's
// readings are 20 of value 10 and 28 of 11, b's 8 of 10 and 40 of 12: 48 each, one a voxel of each frame, 96 in all,
// so the contrast is 7 bits and C is 0 below 10, 28 at 10, 56 at 11 and 96 from 12. a's frame 0 holds voxels 3 and 17,
// its frame 1 voxel 23; b's frame 0 nothing, its frame 1 voxels 0, 1 and 2. Every level is positive.
//
// output_check's set: output_test's, restated. chain is 4 frames in a 4 x 5 x 6 view: frame 0 A (voxel 7), B (50) and
// C (100), frame 1 A (8) and D (119), frame 2 nothing, frame 3 E (0) and F (31); A links on at cost 2^32 + 5, and C to
// D is in the gate and not chosen. second is 2 frames in a 1 x 2 x 3 view: P (0) and Q (5), then R (5) and S (0); P
// links to S at cost 0 and Q to R at cost 3. The nodes and the submission below are output_test's rows, worked by hand.
// Each source's prediction agrees with its outside flag: chain's A (0, 1, 2), B (1, 3, 6) past x's high face and
// flagged outside, C (3, 1, 4), then A (0, 1, 2) and D (3, 5, 5) past y's high face and flagged outside; second's P
// (0, 0, 0) and Q (0, 1, 2).
//
// The .divide cases (src/divide/divide.h) add fork, 2 frames in second's view: P (0) and Q (5), then R (5), S (0) and
// T (3); P links to S and Q to R, and T starts. As worked, chain's .divide has A divide, taking D, which started, and
// second's has P divide, taking R from Q, which ends; fork has no .divide. Each .divide's head carries the CRC-64 of
// the .links beside it, taken here a bit at a time, apart from output_check's table.
//
// The .faces cases (src/faces/faces.h) give chain and second a .drift, a .shape and a .faces, worked by hand. chain's
// lags are (-1, 0, 3) onto frame 1, 0 onto frame 2 and (1, 0, 0) onto frame 3, and C's .shape faces x's high face; so
// A is carried back to (1, 1, -1), past x's low face, and has its link in; D back to (4, 4, 2), past z's high face,
// with no link in, so it enters, and with its prediction past a face and no link out it leaves, as B leaves; E back to
// (-1, 0, 0), past z's low face, enters, and F back to (0, 0, 1) does not. second's lag onto frame 1 is (0, 0, 1): R
// back to (0, 1, 1), and S to (0, 0, -1), past x's low face, with its link in. Each .faces carries the CRC-64 of the
// .links beside it. The states are then chain's B 32, D 33 and E 1, and with the .divide files too D is daughter two
// and no start, 40.
//   check_test <directory>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <direct.h>
#define CHECK_TEST_MKDIR(path_) _mkdir(path_)
#else
#include <sys/stat.h>
#define CHECK_TEST_MKDIR(path_) mkdir((path_), 0755)
#endif

#define CHECK_TEST_READINGS 65536u

#define CHECK_TEST_PATH 4096u

#define CHECK_TEST_WORDS 1024u

// the points cases: each breaks the good set one way, and names the fault points_check must count
typedef enum
{
    POINTS_CASE_OK = 0,
    POINTS_CASE_SET_UNREAD,
    POINTS_CASE_READINGS_UNREAD,
    POINTS_CASE_SUM_PAST_64,
    POINTS_CASE_SET_NOT_REBUILT,
    POINTS_CASE_NOT_LISTED,
    POINTS_CASE_POINTS_UNREAD,
    POINTS_CASE_HEAD_DIFFERS,
    POINTS_CASE_HEAD_NOT_REBUILT,
    POINTS_CASE_EMPTY_VIEW,
    POINTS_CASE_COUNT_PAST_VIEW,
    POINTS_CASE_FRAME_SHORT,
    POINTS_CASE_OUT_OF_ORDER,
    POINTS_CASE_OUTSIDE,
    POINTS_CASE_NOT_POSITIVE,
    POINTS_CASE_ZERO_LEVEL,
    POINTS_CASE_PAST_LAST_FRAME,
    POINTS_CASE_READINGS_NOT_VIEW,
    POINTS_CASES
} PointsCase;

static const char *const POINTS_CASE_NAMES[POINTS_CASES] = {
    "good",          "set_unread",   "readings_unread",  "sum_past_64", "set_not_rebuilt", "not_listed",
    "points_unread", "head_differs", "head_not_rebuilt", "empty_view",  "count_past_view", "frame_short",
    "out_of_order",  "outside",      "not_positive",     "zero_level",  "past_last_frame", "readings_not_view"};

// the output cases, likewise
typedef enum
{
    OUTPUT_CASE_OK = 0,
    OUTPUT_CASE_LINKS_FRAMES,
    OUTPUT_CASE_LINKS_VIEW,
    OUTPUT_CASE_PAIR_COUNT,
    OUTPUT_CASE_RANGE,
    OUTPUT_CASE_TWO_OUT,
    OUTPUT_CASE_TWO_IN,
    OUTPUT_CASE_CHOSEN,
    OUTPUT_CASE_LINKS_TRAILING,
    OUTPUT_CASE_LINKS_SHORT,
    OUTPUT_CASE_LINKS_MISSING,
    OUTPUT_CASE_POINTS_TRAILING,
    OUTPUT_CASE_POINTS_SHORT,
    OUTPUT_CASE_POINTS_OUTSIDE,
    OUTPUT_CASE_NODES_DIFFER,
    OUTPUT_CASE_SUBMISSION_DIFFERS,
    OUTPUT_CASE_NODES_HEADER,
    OUTPUT_CASE_NODES_MISSING,
    OUTPUT_CASE_SUBMISSION_PAST,
    OUTPUT_CASE_CARRIAGE,
    OUTPUT_CASES
} OutputCase;

static const char *const OUTPUT_CASE_NAMES[OUTPUT_CASES] = {
    "good",           "links_frames",   "links_view",      "pair_count",
    "range",          "two_out",        "two_in",          "chosen",
    "links_trailing", "links_short",    "links_missing",   "points_trailing",
    "points_short",   "points_outside", "nodes_differ",    "submission_differs",
    "nodes_header",   "nodes_missing",  "submission_past", "carriage"};

// the .divide cases, on chain, second and fork whole: chain's and second's .divide as worked, fork with none; a
// .divide of no divisions beside each; the worked .divide files with the sort's rows in the files; and each fault in
// second's .divide, or in fork's for a division taking from a point that divides
typedef enum
{
    DIVIDE_CASE_OK = 0,
    DIVIDE_CASE_NONE,
    DIVIDE_CASE_ROWS,
    DIVIDE_CASE_HEAD,
    DIVIDE_CASE_FRAMES,
    DIVIDE_CASE_VIEW,
    DIVIDE_CASE_CRC,
    DIVIDE_CASE_COUNT,
    DIVIDE_CASE_PARENT,
    DIVIDE_CASE_ORDER,
    DIVIDE_CASE_ONE,
    DIVIDE_CASE_TWO,
    DIVIDE_CASE_TWO_PAST,
    DIVIDE_CASE_LEFT,
    DIVIDE_CASE_DIVIDES,
    DIVIDE_CASE_SHORT,
    DIVIDE_CASE_TRAILING,
    DIVIDE_CASES
} DivideCase;

static const char *const DIVIDE_CASE_NAMES[DIVIDE_CASES] = {"good",     "none",  "rows",    "head",  "frames",  "view",
                                                            "crc",      "count", "parent",  "order", "one",     "two",
                                                            "two_past", "left",  "divides", "short", "trailing"};

// the .faces cases, on chain and second whole: each sample's .drift, .shape and .faces as worked; second's .faces
// away; the worked files with chain's and second's .divide too; the worked .faces with the unfaced rows in the files;
// and each fault in chain's .faces, its .links' outside flags, its .drift or its .shape
typedef enum
{
    FACES_CASE_OK = 0,
    FACES_CASE_BARE,
    FACES_CASE_DIVIDED,
    FACES_CASE_ROWS,
    FACES_CASE_HEAD,
    FACES_CASE_FRAMES,
    FACES_CASE_VIEW,
    FACES_CASE_CRC,
    FACES_CASE_COUNT,
    FACES_CASE_BACK,
    FACES_CASE_HESSIAN,
    FACES_CASE_VERDICT,
    FACES_CASE_SHORT,
    FACES_CASE_TRAILING,
    FACES_CASE_OUTSIDE,
    FACES_CASE_PAST_32,
    FACES_CASE_DRIFT_MISSING,
    FACES_CASE_DRIFT_VIEW,
    FACES_CASE_DRIFT_TRAILING,
    FACES_CASE_HESSIAN_LIMBS,
    FACES_CASE_HESSIAN_COUNT,
    FACES_CASE_HESSIAN_SIX,
    FACES_CASE_HESSIAN_SHORT,
    FACES_CASES
} FacesCase;

static const char *const FACES_CASE_NAMES[FACES_CASES] = {
    "good",          "bare",       "divided",        "rows",        "head",        "frames",    "view",       "crc",
    "count",         "back",       "shape",          "verdict",     "short",       "trailing",  "outside",    "past_32",
    "drift_missing", "drift_view", "drift_trailing", "shape_limbs", "shape_count", "shape_six", "shape_short"};

#define CHECK_TEST_NONE 0xFFFFFFFFu

#define CHECK_TEST_NODES_HEADER                                                                                        \
    "sample\ttime\tleaf\tz\ty\tx\tvoxels\tobject\tobject_members\tforward\tdeparture\theld\tobject_link\tobject_links" \
    "\tnull_draws\tnull_at_least\tnull_best\ttower_target\ttower_rounds\tbackward\tbody\tstate\tparent\ttouches"       \
    "\tsplit_from\n"

#define CHECK_TEST_SUBMISSION_HEADER "id,dataset,row_type,node_id,t,z,y,x,source_id,target_id\n"

static const char CHECK_TEST_NODES[] = CHECK_TEST_NODES_HEADER
    "chain\t0\t0\t0\t1\t1\t0\t0\t1\t0\t4294967301\t0\t0\t1\t0\t0\t0\t-1\t0\t-1\t1\t0\t-1\t0\t-1\n"
    "chain\t0\t1\t1\t3\t2\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t2\t0\t-1\t0\t-1\n"
    "chain\t0\t2\t3\t1\t4\t0\t2\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t3\t0\t-1\t0\t-1\n"
    "chain\t1\t0\t0\t1\t2\t0\t0\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t0\t4\t0\t-1\t0\t-1\n"
    "chain\t1\t1\t3\t4\t5\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t5\t0\t-1\t0\t-1\n"
    "chain\t3\t0\t0\t0\t0\t0\t0\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t6\t0\t-1\t0\t-1\n"
    "chain\t3\t1\t1\t0\t1\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t7\t0\t-1\t0\t-1\n"
    "second\t0\t0\t0\t0\t0\t0\t0\t1\t1\t0\t0\t1\t1\t0\t0\t0\t-1\t0\t-1\t1\t0\t-1\t0\t-1\n"
    "second\t0\t1\t0\t1\t2\t0\t1\t1\t0\t3\t0\t0\t1\t0\t0\t0\t-1\t0\t-1\t2\t0\t-1\t0\t-1\n"
    "second\t1\t0\t0\t1\t2\t0\t0\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t1\t3\t0\t-1\t0\t-1\n"
    "second\t1\t1\t0\t0\t0\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t0\t4\t0\t-1\t0\t-1\n";

static const char CHECK_TEST_SUBMISSION[] = CHECK_TEST_SUBMISSION_HEADER "0,chain,node,1,0,0,1,1,-1,-1\n"
                                                                         "1,chain,node,2,0,1,3,2,-1,-1\n"
                                                                         "2,chain,node,3,0,3,1,4,-1,-1\n"
                                                                         "3,chain,node,4,1,0,1,2,-1,-1\n"
                                                                         "4,chain,node,5,1,3,4,5,-1,-1\n"
                                                                         "5,chain,node,6,3,0,0,0,-1,-1\n"
                                                                         "6,chain,node,7,3,1,0,1,-1,-1\n"
                                                                         "7,chain,edge,-1,-1,-1,-1,-1,1,4\n"
                                                                         "8,second,node,1,0,0,0,0,-1,-1\n"
                                                                         "9,second,node,2,0,0,1,2,-1,-1\n"
                                                                         "10,second,node,3,1,0,1,2,-1,-1\n"
                                                                         "11,second,node,4,1,0,0,0,-1,-1\n"
                                                                         "12,second,edge,-1,-1,-1,-1,-1,1,4\n"
                                                                         "13,second,edge,-1,-1,-1,-1,-1,2,3\n";

// the rows with chain's .divide and second's, output_test's worked by hand: chain's A divides, taking D, which started;
// second's P divides, taking R from Q, which ends. Each daughter two's state is split, 8
static const char CHECK_TEST_DIVIDED_NODES[] = CHECK_TEST_NODES_HEADER
    "chain\t0\t0\t0\t1\t1\t0\t0\t1\t0\t4294967301\t0\t0\t2\t0\t0\t0\t-1\t0\t-1\t1\t0\t-1\t0\t-1\n"
    "chain\t0\t1\t1\t3\t2\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t2\t0\t-1\t0\t-1\n"
    "chain\t0\t2\t3\t1\t4\t0\t2\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t3\t0\t-1\t0\t-1\n"
    "chain\t1\t0\t0\t1\t2\t0\t0\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t0\t4\t0\t-1\t0\t-1\n"
    "chain\t1\t1\t3\t4\t5\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t0\t5\t8\t-1\t0\t0\n"
    "chain\t3\t0\t0\t0\t0\t0\t0\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t6\t0\t-1\t0\t-1\n"
    "chain\t3\t1\t1\t0\t1\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t7\t0\t-1\t0\t-1\n"
    "second\t0\t0\t0\t0\t0\t0\t0\t1\t1\t0\t0\t1\t2\t0\t0\t0\t-1\t0\t-1\t1\t0\t-1\t0\t-1\n"
    "second\t0\t1\t0\t1\t2\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t2\t0\t-1\t0\t-1\n"
    "second\t1\t0\t0\t1\t2\t0\t0\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t0\t3\t8\t-1\t0\t0\n"
    "second\t1\t1\t0\t0\t0\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t0\t4\t0\t-1\t0\t-1\n";

// the rows with each sample's .faces as worked: chain's B ends predicted past a face and left, 32; D starts carried
// back past one and ends predicted past another, entered and left, 33; E starts carried back past one, entered, 1
static const char CHECK_TEST_FACED_NODES[] = CHECK_TEST_NODES_HEADER
    "chain\t0\t0\t0\t1\t1\t0\t0\t1\t0\t4294967301\t0\t0\t1\t0\t0\t0\t-1\t0\t-1\t1\t0\t-1\t0\t-1\n"
    "chain\t0\t1\t1\t3\t2\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t2\t32\t-1\t0\t-1\n"
    "chain\t0\t2\t3\t1\t4\t0\t2\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t3\t0\t-1\t0\t-1\n"
    "chain\t1\t0\t0\t1\t2\t0\t0\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t0\t4\t0\t-1\t0\t-1\n"
    "chain\t1\t1\t3\t4\t5\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t5\t33\t-1\t0\t-1\n"
    "chain\t3\t0\t0\t0\t0\t0\t0\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t6\t1\t-1\t0\t-1\n"
    "chain\t3\t1\t1\t0\t1\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t7\t0\t-1\t0\t-1\n"
    "second\t0\t0\t0\t0\t0\t0\t0\t1\t1\t0\t0\t1\t1\t0\t0\t0\t-1\t0\t-1\t1\t0\t-1\t0\t-1\n"
    "second\t0\t1\t0\t1\t2\t0\t1\t1\t0\t3\t0\t0\t1\t0\t0\t0\t-1\t0\t-1\t2\t0\t-1\t0\t-1\n"
    "second\t1\t0\t0\t1\t2\t0\t0\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t1\t3\t0\t-1\t0\t-1\n"
    "second\t1\t1\t0\t0\t0\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t0\t4\t0\t-1\t0\t-1\n";

// the rows with the .faces and the .divide files both: D is daughter two, no start, split and left, 40
static const char CHECK_TEST_FACED_DIVIDED_NODES[] = CHECK_TEST_NODES_HEADER
    "chain\t0\t0\t0\t1\t1\t0\t0\t1\t0\t4294967301\t0\t0\t2\t0\t0\t0\t-1\t0\t-1\t1\t0\t-1\t0\t-1\n"
    "chain\t0\t1\t1\t3\t2\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t2\t32\t-1\t0\t-1\n"
    "chain\t0\t2\t3\t1\t4\t0\t2\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t3\t0\t-1\t0\t-1\n"
    "chain\t1\t0\t0\t1\t2\t0\t0\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t0\t4\t0\t-1\t0\t-1\n"
    "chain\t1\t1\t3\t4\t5\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t0\t5\t40\t-1\t0\t0\n"
    "chain\t3\t0\t0\t0\t0\t0\t0\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t6\t1\t-1\t0\t-1\n"
    "chain\t3\t1\t1\t0\t1\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t7\t0\t-1\t0\t-1\n"
    "second\t0\t0\t0\t0\t0\t0\t0\t1\t1\t0\t0\t1\t2\t0\t0\t0\t-1\t0\t-1\t1\t0\t-1\t0\t-1\n"
    "second\t0\t1\t0\t1\t2\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t2\t0\t-1\t0\t-1\n"
    "second\t1\t0\t0\t1\t2\t0\t0\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t0\t3\t8\t-1\t0\t0\n"
    "second\t1\t1\t0\t0\t0\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t0\t4\t0\t-1\t0\t-1\n";

static const char CHECK_TEST_DIVIDED_SUBMISSION[] = CHECK_TEST_SUBMISSION_HEADER "0,chain,node,1,0,0,1,1,-1,-1\n"
                                                                                 "1,chain,node,2,0,1,3,2,-1,-1\n"
                                                                                 "2,chain,node,3,0,3,1,4,-1,-1\n"
                                                                                 "3,chain,node,4,1,0,1,2,-1,-1\n"
                                                                                 "4,chain,node,5,1,3,4,5,-1,-1\n"
                                                                                 "5,chain,node,6,3,0,0,0,-1,-1\n"
                                                                                 "6,chain,node,7,3,1,0,1,-1,-1\n"
                                                                                 "7,chain,edge,-1,-1,-1,-1,-1,1,4\n"
                                                                                 "8,chain,edge,-1,-1,-1,-1,-1,1,5\n"
                                                                                 "9,second,node,1,0,0,0,0,-1,-1\n"
                                                                                 "10,second,node,2,0,0,1,2,-1,-1\n"
                                                                                 "11,second,node,3,1,0,1,2,-1,-1\n"
                                                                                 "12,second,node,4,1,0,0,0,-1,-1\n"
                                                                                 "13,second,edge,-1,-1,-1,-1,-1,1,4\n"
                                                                                 "14,second,edge,-1,-1,-1,-1,-1,1,3\n";

// fork's rows, undivided: P links to S and Q to R, and T starts
static const char CHECK_TEST_FORK_NODES[] =
    "fork\t0\t0\t0\t0\t0\t0\t0\t1\t1\t0\t0\t1\t1\t0\t0\t0\t-1\t0\t-1\t1\t0\t-1\t0\t-1\n"
    "fork\t0\t1\t0\t1\t2\t0\t1\t1\t0\t3\t0\t0\t1\t0\t0\t0\t-1\t0\t-1\t2\t0\t-1\t0\t-1\n"
    "fork\t1\t0\t0\t1\t2\t0\t0\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t1\t3\t0\t-1\t0\t-1\n"
    "fork\t1\t1\t0\t0\t0\t0\t1\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t0\t4\t0\t-1\t0\t-1\n"
    "fork\t1\t2\t0\t1\t0\t0\t2\t1\t-1\t0\t0\t-1\t0\t0\t0\t0\t-1\t0\t-1\t5\t0\t-1\t0\t-1\n";

typedef struct
{
    unsigned int words[CHECK_TEST_WORDS];
    unsigned int count;
} CheckTestWords;

static void check_test_put(CheckTestWords *words, unsigned int word)
{
    if (words->count < CHECK_TEST_WORDS)
    {
        words->words[words->count] = word;
    }
    words->count += 1u;
}

static int check_test_join(char *path, size_t capacity, const char *one, const char *two)
{
    const int written = snprintf(path, capacity, "%s/%s", one, two);
    // a non-negative length is compared whole against the capacity
    return (written > 0) && ((size_t)written < capacity);
}

static int check_test_sample_path(char *path, size_t capacity, const char *set, const char *sample, const char *suffix)
{
    const int written = snprintf(path, capacity, "%s/%s/%s%s", set, sample, sample, suffix);
    return (written > 0) && ((size_t)written < capacity);
}

// a file of `bytes` bytes, less `short_by` from its end
static int check_test_file(const char *path, const void *bytes, size_t length, size_t short_by)
{
    FILE *const file = fopen(path, "wb");
    const size_t kept = (short_by < length) ? (length - short_by) : 0u;
    const int written = (file != NULL) && ((kept == 0u) || (fwrite(bytes, 1u, kept, file) == kept));
    const int closed = (file != NULL) && (fclose(file) == 0);
    return written && closed;
}

static int check_test_directory(const char *set, const char *sample)
{
    char path[CHECK_TEST_PATH];
    (void)CHECK_TEST_MKDIR(set);
    if ((sample == NULL) || (check_test_join(path, sizeof(path), set, sample) == 0))
    {
        return sample == NULL;
    }
    (void)CHECK_TEST_MKDIR(path);
    return 1;
}

// one points sample: its .readings (the counts and a footing) and its .points (the head, the readings, C and its
// frames), each frame given as counts, voxels and levels. `trailing` adds a word past the last frame and `short_by`
// takes bytes off the .points' end
typedef struct
{
    unsigned int head[6];
    unsigned long long counts[3];
    unsigned int frame_counts[2];
    unsigned int voxels[4];
    unsigned int levels[12];
    int trailing;
    size_t short_by;
    size_t readings_short_by;
    int no_points;
    int no_readings;
} CheckTestPoints;

static int check_test_points_write(const char *set, const char *sample, const CheckTestPoints *points,
                                   const unsigned long long *contrast, unsigned long long readings)
{
    char path[CHECK_TEST_PATH];
    int ok = check_test_directory(set, sample);
    unsigned long long *const words =
        (unsigned long long *)calloc(CHECK_TEST_READINGS + 5u, sizeof(unsigned long long));
    ok = ok && (words != NULL);
    if (ok && (points->no_readings == 0))
    {
        words[10] = points->counts[0];
        words[11] = points->counts[1];
        words[12] = points->counts[2];
        // a footing held, lo 10, hi 12, a step each
        words[CHECK_TEST_READINGS + 0u] = 1ull;
        words[CHECK_TEST_READINGS + 1u] = 10ull;
        words[CHECK_TEST_READINGS + 2u] = 12ull;
        words[CHECK_TEST_READINGS + 3u] = 1ull;
        words[CHECK_TEST_READINGS + 4u] = 1ull;
        ok = check_test_sample_path(path, sizeof(path), set, sample, ".readings") &&
             check_test_file(path, words, (CHECK_TEST_READINGS + 5u) * sizeof(unsigned long long),
                             points->readings_short_by);
    }
    free(words);
    if ((ok == 0) || (points->no_points != 0))
    {
        return ok;
    }
    // the .points whole, in one buffer: the head, the readings, C, then the frames and a trailing word
    const size_t capacity = (6u * 4u) + 8u + (CHECK_TEST_READINGS * 8u) + (4u * (2u + 4u + 12u + 1u));
    unsigned char *const bytes = (unsigned char *)malloc(capacity);
    if (bytes == NULL)
    {
        return 0;
    }
    size_t used = 0u;
    memcpy(&bytes[used], points->head, sizeof(points->head));
    used += sizeof(points->head);
    memcpy(&bytes[used], &readings, sizeof(readings));
    used += sizeof(readings);
    memcpy(&bytes[used], contrast, CHECK_TEST_READINGS * sizeof(unsigned long long));
    used += CHECK_TEST_READINGS * sizeof(unsigned long long);
    unsigned int taken = 0u;
    for (unsigned int frame = 0u; frame < points->head[0]; frame += 1u)
    {
        const unsigned int count = points->frame_counts[frame];
        memcpy(&bytes[used], &count, sizeof(count));
        used += sizeof(count);
        // a count past the voxels and levels the sample holds (count_past_view's 25) is written alone, and the file
        // ends at it: points_check stops at the count
        if (((taken + count) > (sizeof(points->voxels) / sizeof(points->voxels[0]))) ||
            (((taken + count) * points->head[4]) > (sizeof(points->levels) / sizeof(points->levels[0]))))
        {
            break;
        }
        memcpy(&bytes[used], &points->voxels[taken], count * sizeof(unsigned int));
        used += count * sizeof(unsigned int);
        memcpy(&bytes[used], &points->levels[taken * points->head[4]], count * points->head[4] * sizeof(unsigned int));
        used += count * points->head[4] * sizeof(unsigned int);
        taken += count;
    }
    if (points->trailing != 0)
    {
        const unsigned int word = 0u;
        memcpy(&bytes[used], &word, sizeof(word));
        used += sizeof(word);
    }
    ok = check_test_sample_path(path, sizeof(path), set, sample, ".points") &&
         check_test_file(path, bytes, used, points->short_by);
    free(bytes);
    return ok;
}

// the good samples a and b
static void check_test_points_ok(CheckTestPoints *a, CheckTestPoints *b)
{
    memset(a, 0, sizeof(*a));
    memset(b, 0, sizeof(*b));
    const unsigned int head[6] = {2u, 2u, 3u, 4u, 2u, 7u};
    memcpy(a->head, head, sizeof(head));
    memcpy(b->head, head, sizeof(head));
    a->counts[0] = 20ull;
    a->counts[1] = 28ull;
    b->counts[0] = 8ull;
    b->counts[2] = 40ull;
    a->frame_counts[0] = 2u;
    a->frame_counts[1] = 1u;
    const unsigned int a_voxels[3] = {3u, 17u, 23u};
    const unsigned int a_levels[6] = {5u, 0u, 0u, 1u, 1u, 0x7FFFFFFFu};
    memcpy(a->voxels, a_voxels, sizeof(a_voxels));
    memcpy(a->levels, a_levels, sizeof(a_levels));
    b->frame_counts[0] = 0u;
    b->frame_counts[1] = 3u;
    const unsigned int b_voxels[3] = {0u, 1u, 2u};
    const unsigned int b_levels[6] = {1u, 0u, 2u, 0u, 0u, 3u};
    memcpy(b->voxels, b_voxels, sizeof(b_voxels));
    memcpy(b->levels, b_levels, sizeof(b_levels));
}

static int check_test_points_case(const char *root, PointsCase which)
{
    char set[CHECK_TEST_PATH];
    char name[256];
    snprintf(name, sizeof(name), "points_%s", POINTS_CASE_NAMES[which]);
    if ((check_test_join(set, sizeof(set), root, name) == 0) || (check_test_directory(set, NULL) == 0))
    {
        return 0;
    }
    CheckTestPoints a;
    CheckTestPoints b;
    check_test_points_ok(&a, &b);
    switch (which)
    {
    case POINTS_CASE_READINGS_UNREAD:
        b.readings_short_by = 8u;
        break;
    case POINTS_CASE_SUM_PAST_64:
        a.counts[0] = 0x8000000000000000ull;
        b.counts[0] = 0x8000000000000000ull;
        break;
    case POINTS_CASE_POINTS_UNREAD:
        b.no_points = 1;
        break;
    case POINTS_CASE_HEAD_DIFFERS: {
        // b's levels at three limbs, each still positive
        const unsigned int levels[9] = {1u, 0u, 0u, 2u, 0u, 0u, 0u, 3u, 0u};
        b.head[4] = 3u;
        memcpy(b.levels, levels, sizeof(levels));
    }
    break;
    case POINTS_CASE_EMPTY_VIEW:
        b.head[0] = 0u;
        break;
    case POINTS_CASE_COUNT_PAST_VIEW:
        a.frame_counts[0] = 25u;
        a.frame_counts[1] = 0u;
        a.head[0] = 1u;
        break;
    case POINTS_CASE_FRAME_SHORT:
        b.short_by = 4u;
        break;
    case POINTS_CASE_OUT_OF_ORDER:
        a.voxels[0] = 17u;
        a.voxels[1] = 3u;
        break;
    case POINTS_CASE_OUTSIDE:
        a.voxels[2] = 24u;
        break;
    case POINTS_CASE_NOT_POSITIVE:
        a.levels[3] = 0x80000000u;
        break;
    case POINTS_CASE_ZERO_LEVEL:
        a.levels[0] = 0u;
        break;
    case POINTS_CASE_PAST_LAST_FRAME:
        a.trailing = 1;
        break;
    case POINTS_CASE_READINGS_NOT_VIEW:
        b.counts[2] = 39ull;
        break;
    default:
        break;
    }
    // the set's C and readings from the counts the samples hold (at values 10, 11 and 12), as the scan sums them; in
    // sum_past_64 the sum wraps, which is the case
    unsigned long long *const contrast = (unsigned long long *)calloc(CHECK_TEST_READINGS, sizeof(unsigned long long));
    if (contrast == NULL)
    {
        return 0;
    }
    unsigned long long running = 0ull;
    for (unsigned int value = 0u; value < CHECK_TEST_READINGS; value += 1u)
    {
        running += ((value >= 10u) && (value <= 12u)) ? (a.counts[value - 10u] + b.counts[value - 10u]) : 0ull;
        contrast[value] = running;
    }
    if (which == POINTS_CASE_HEAD_NOT_REBUILT)
    {
        contrast[11] += 1ull;
    }
    unsigned int bits = 0u;
    while ((bits < 64u) && ((running >> bits) != 0ull))
    {
        bits += 1u;
    }
    a.head[5] = bits;
    b.head[5] = bits;
    int ok = check_test_points_write(set, "a", &a, contrast, running) &&
             check_test_points_write(set, "b", &b, contrast, running);
    if (which == POINTS_CASE_NOT_LISTED)
    {
        ok = ok && check_test_points_write(set, "c", &a, contrast, running);
    }
    free(contrast);
    char path[CHECK_TEST_PATH];
    char text[256];
    const unsigned long long named = (which == POINTS_CASE_SET_NOT_REBUILT) ? (running + 1ull) : running;
    const int length = (which == POINTS_CASE_SET_UNREAD)
                           ? snprintf(text, sizeof(text), "readings %llu\nbits %u\nsamples 2\na\n", named, bits)
                           : snprintf(text, sizeof(text), "readings %llu\nbits %u\nsamples 2\na\nb\n", named, bits);
    return ok && (length > 0) && check_test_join(path, sizeof(path), set, "scan.set") &&
           check_test_file(path, text, (size_t)length, 0u);
}

// the .links header: frames, the view, the weights 16, 1, 1 and the cost's terms
static void check_test_links_head(CheckTestWords *words, unsigned int frames, unsigned int depth, unsigned int height,
                                  unsigned int width)
{
    const unsigned int head[8] = {frames, depth, height, width, 16u, 1u, 1u, 1u};
    for (unsigned int at = 0u; at < 8u; at += 1u)
    {
        check_test_put(words, head[at]);
    }
}

static void check_test_pair(CheckTestWords *words, unsigned int sources, unsigned int targets, unsigned int gate,
                            unsigned int chosen)
{
    const unsigned int record[11] = {sources, targets, gate, gate, chosen, 0u, 0u, 0u, 0u, 0u, 0u};
    for (unsigned int at = 0u; at < 11u; at += 1u)
    {
        check_test_put(words, record[at]);
    }
}

// a source record: its prediction z, y, x, and its flags (outside 1, carried 2)
static void check_test_source(CheckTestWords *words, unsigned int z, unsigned int y, unsigned int x, unsigned int flags)
{
    const unsigned int record[4] = {z, y, x, flags};
    for (unsigned int at = 0u; at < 4u; at += 1u)
    {
        check_test_put(words, record[at]);
    }
}

static void check_test_gate(CheckTestWords *words, unsigned int source, unsigned int target, unsigned long long cost,
                            unsigned int chosen)
{
    const unsigned int record[7] = {source,
                                    target,
                                    (unsigned int)(cost & 0xFFFFFFFFull),
                                    (unsigned int)(cost >> 32u),
                                    1u,
                                    0u,
                                    chosen ? 0x7u : 0x2u};
    for (unsigned int at = 0u; at < 7u; at += 1u)
    {
        check_test_put(words, record[at]);
    }
}

// a sample's .points for output_check: the head, the readings and C (0 here, which output_check passes over), then
// each frame's count, voxels and levels, each level `limbs` words of 0xA5A5A5A5
static int check_test_graph_points(const char *set, const char *sample, const unsigned int head[6],
                                   const unsigned int *counts, const unsigned int *voxels, int trailing, int short_by)
{
    CheckTestWords frames;
    memset(&frames, 0, sizeof(frames));
    unsigned int taken = 0u;
    for (unsigned int frame = 0u; frame < head[0]; frame += 1u)
    {
        check_test_put(&frames, counts[frame]);
        for (unsigned int at = 0u; at < counts[frame]; at += 1u)
        {
            check_test_put(&frames, voxels[taken + at]);
        }
        for (unsigned int at = 0u; at < (counts[frame] * head[4]); at += 1u)
        {
            check_test_put(&frames, 0xA5A5A5A5u);
        }
        taken += counts[frame];
    }
    if (trailing != 0)
    {
        check_test_put(&frames, 0u);
    }
    const size_t length = 24u + 8u + (CHECK_TEST_READINGS * 8u) + ((size_t)frames.count * 4u);
    unsigned char *const bytes = (unsigned char *)calloc(length, 1u);
    if ((bytes == NULL) || (frames.count > CHECK_TEST_WORDS))
    {
        free(bytes);
        return 0;
    }
    memcpy(bytes, head, 24u);
    memcpy(&bytes[24u + 8u + (CHECK_TEST_READINGS * 8u)], frames.words, (size_t)frames.count * 4u);
    char path[CHECK_TEST_PATH];
    const int ok = check_test_directory(set, sample) &&
                   check_test_sample_path(path, sizeof(path), set, sample, ".points") &&
                   check_test_file(path, bytes, length, (size_t)short_by);
    free(bytes);
    return ok;
}

static int check_test_graph_links(const char *set, const char *sample, const CheckTestWords *words)
{
    char path[CHECK_TEST_PATH];
    return (words->count <= CHECK_TEST_WORDS) && check_test_sample_path(path, sizeof(path), set, sample, ".links") &&
           check_test_file(path, words->words, (size_t)words->count * 4u, 0u);
}

// a text file with one byte of it changed, a line taken off its end, a line put past it, or every LF made CR LF
static int check_test_text(const char *path, const char *text, OutputCase which, OutputCase changes, size_t at,
                           char becomes)
{
    const size_t length = strlen(text);
    char *const copy = (char *)malloc((2u * length) + 64u);
    if (copy == NULL)
    {
        return 0;
    }
    size_t used = 0u;
    for (size_t place = 0u; place < length; place += 1u)
    {
        if ((which == OUTPUT_CASE_CARRIAGE) && (changes == OUTPUT_CASE_CARRIAGE) && (text[place] == '\n'))
        {
            copy[used] = '\r';
            used += 1u;
        }
        copy[used] = ((which == changes) && (place == at) && (which != OUTPUT_CASE_CARRIAGE)) ? becomes : text[place];
        used += 1u;
    }
    if ((which == changes) && (which == OUTPUT_CASE_NODES_MISSING))
    {
        // the last row taken off: back to the line feed before the last
        used -= 1u;
        while ((used > 0u) && (copy[used - 1u] != '\n'))
        {
            used -= 1u;
        }
    }
    if ((which == changes) && (which == OUTPUT_CASE_SUBMISSION_PAST))
    {
        const char *const over_limit = "14,second,edge,-1,-1,-1,-1,-1,3,4\n";
        memcpy(&copy[used], over_limit, strlen(over_limit));
        used += strlen(over_limit);
    }
    const int ok = check_test_file(path, copy, used, 0u);
    free(copy);
    return ok;
}

// chain's and second's .points and .links in `set`, chain broken one way by the case; `astray` flags A's prediction
// outside the view, though it lies in it
static int check_test_graph(const char *set, OutputCase which, int astray)
{
    const unsigned int head[6] = {4u, 4u, 5u, 6u, 2u, 34u};
    const unsigned int counts[4] = {3u, 2u, 0u, 2u};
    const unsigned int voxels[7] = {7u, 50u, 100u, 8u, 119u, 0u, (which == OUTPUT_CASE_POINTS_OUTSIDE) ? 120u : 31u};
    CheckTestWords words;
    memset(&words, 0, sizeof(words));
    check_test_links_head(&words, (which == OUTPUT_CASE_LINKS_FRAMES) ? 3u : 4u, 4u, 5u,
                          (which == OUTPUT_CASE_LINKS_VIEW) ? 7u : 6u);
    const unsigned int doubled = ((which == OUTPUT_CASE_TWO_OUT) || (which == OUTPUT_CASE_TWO_IN)) ? 1u : 0u;
    check_test_pair(&words, (which == OUTPUT_CASE_PAIR_COUNT) ? 4u : 3u, 2u, 2u + doubled,
                    (which == OUTPUT_CASE_CHOSEN) ? 2u : (1u + doubled));
    check_test_source(&words, 0u, 1u, 2u, astray ? 1u : 0u);
    check_test_source(&words, 1u, 3u, 6u, 1u);
    check_test_source(&words, 3u, 1u, 4u, 2u);
    check_test_gate(&words, 0u, (which == OUTPUT_CASE_RANGE) ? 2u : 0u, 0x100000005ull, 1);
    if (which == OUTPUT_CASE_TWO_OUT)
    {
        check_test_gate(&words, 0u, 1u, 7ull, 1);
    }
    if (which == OUTPUT_CASE_TWO_IN)
    {
        check_test_gate(&words, 1u, 0u, 7ull, 1);
    }
    check_test_gate(&words, 2u, 1u, 9ull, 0);
    check_test_pair(&words, 2u, 0u, 0u, 0u);
    check_test_source(&words, 0u, 1u, 2u, 2u);
    check_test_source(&words, 3u, 5u, 5u, 3u);
    if (which != OUTPUT_CASE_LINKS_SHORT)
    {
        check_test_pair(&words, 0u, 2u, 0u, 0u);
    }
    if (which == OUTPUT_CASE_LINKS_TRAILING)
    {
        check_test_put(&words, 0u);
    }
    int ok = check_test_graph_points(set, "chain", head, counts, voxels, which == OUTPUT_CASE_POINTS_TRAILING,
                                     (which == OUTPUT_CASE_POINTS_SHORT) ? 4 : 0) &&
             ((which == OUTPUT_CASE_LINKS_MISSING) || check_test_graph_links(set, "chain", &words));
    // second, whole in every case
    const unsigned int second_head[6] = {2u, 1u, 2u, 3u, 0u, 34u};
    const unsigned int second_counts[2] = {2u, 2u};
    const unsigned int second_voxels[4] = {0u, 5u, 5u, 0u};
    CheckTestWords second;
    memset(&second, 0, sizeof(second));
    check_test_links_head(&second, 2u, 1u, 2u, 3u);
    check_test_pair(&second, 2u, 2u, 3u, 2u);
    check_test_source(&second, 0u, 0u, 0u, 0u);
    check_test_source(&second, 0u, 1u, 2u, 0u);
    check_test_gate(&second, 0u, 0u, 5ull, 0);
    check_test_gate(&second, 0u, 1u, 0ull, 1);
    check_test_gate(&second, 1u, 0u, 3ull, 1);
    return ok && check_test_graph_points(set, "second", second_head, second_counts, second_voxels, 0, 0) &&
           check_test_graph_links(set, "second", &second);
}

static int check_test_output_case(const char *root, OutputCase which)
{
    char set[CHECK_TEST_PATH];
    char name[256];
    snprintf(name, sizeof(name), "output_%s", OUTPUT_CASE_NAMES[which]);
    if ((check_test_join(set, sizeof(set), root, name) == 0) || (check_test_directory(set, NULL) == 0))
    {
        return 0;
    }
    int ok = check_test_graph(set, which, 0);
    // the files: a byte of a row changed in chain's first row (its x, 1 to 9), in the submission's row 9's x, or in the
    // nodes header's first letter
    char path[CHECK_TEST_PATH];
    const size_t header = strlen(CHECK_TEST_NODES_HEADER);
    const size_t nodes_at = (which == OUTPUT_CASE_NODES_HEADER) ? 0u : (header + strlen("chain\t0\t0\t0\t1\t"));
    const char nodes_becomes = (which == OUTPUT_CASE_NODES_HEADER) ? 'S' : '9';
    const char *const ninth = strstr(CHECK_TEST_SUBMISSION, "9,second,node,2,0,0,1,");
    const size_t submission_at =
        (ninth != NULL) ? (size_t)(ninth - CHECK_TEST_SUBMISSION) + strlen("9,second,node,2,0,0,1,") : 0u;
    const OutputCase nodes_change = ((which == OUTPUT_CASE_NODES_DIFFER) || (which == OUTPUT_CASE_NODES_HEADER) ||
                                     (which == OUTPUT_CASE_NODES_MISSING) || (which == OUTPUT_CASE_CARRIAGE))
                                        ? which
                                        : OUTPUT_CASE_OK;
    const OutputCase submission_change =
        ((which == OUTPUT_CASE_SUBMISSION_DIFFERS) || (which == OUTPUT_CASE_SUBMISSION_PAST)) ? which : OUTPUT_CASE_OK;
    ok = ok && check_test_join(path, sizeof(path), set, "nodes.tsv") &&
         check_test_text(path, CHECK_TEST_NODES, which, (nodes_change == OUTPUT_CASE_OK) ? OUTPUT_CASES : nodes_change,
                         nodes_at, nodes_becomes) &&
         check_test_join(path, sizeof(path), set, "submission.csv") &&
         check_test_text(path, CHECK_TEST_SUBMISSION, which,
                         (submission_change == OUTPUT_CASE_OK) ? OUTPUT_CASES : submission_change, submission_at, '7');
    return ok;
}

// the whole file's CRC-64/XZ, a bit at a time, restated apart from output_check's table: the reflected polynomial
// 0xC96C5795D7870F42, from all ones, ended complemented; 0 when the file does not read
static int check_test_crc(const char *path, unsigned long long *crc)
{
    FILE *const file = fopen(path, "rb");
    unsigned long long running = ~0ull;
    int byte = (file != NULL) ? fgetc(file) : EOF;
    while (byte != EOF)
    {
        running ^= (unsigned long long)byte;
        for (unsigned int bit = 0u; bit < 8u; bit += 1u)
        {
            running = ((running & 1ull) != 0ull) ? ((running >> 1u) ^ 0xC96C5795D7870F42ull) : (running >> 1u);
        }
        byte = fgetc(file);
    }
    const int complete = (file != NULL) && (ferror(file) == 0);
    if (file != NULL)
    {
        fclose(file);
    }
    *crc = ~running;
    return complete;
}

// a file beside a sample's .links, its name the sample's with `suffix`: frames and the view, the CRC-64 of the .links
// with `skew` added, then `blocks` blocks, each its count and that many records of `record_words` words from
// `records`, and `extra` words of 0 past the last. `head_words` of the head are written, all six unless the case cuts
// it, and `short_by` words are taken off the end
static int check_test_beside(const char *set, const char *sample, const char *suffix, const unsigned int view[4],
                             unsigned long long skew, unsigned int blocks, const unsigned int *counts,
                             const unsigned int *records, unsigned int record_words, unsigned int extra,
                             unsigned int head_words, unsigned int short_by)
{
    char path[CHECK_TEST_PATH];
    unsigned long long crc = 0ull;
    if ((check_test_sample_path(path, sizeof(path), set, sample, ".links") == 0) || (check_test_crc(path, &crc) == 0))
    {
        return 0;
    }
    crc += skew;
    CheckTestWords words;
    memset(&words, 0, sizeof(words));
    const unsigned int head[6] = {
        view[0], view[1], view[2], view[3], (unsigned int)(crc & 0xFFFFFFFFull), (unsigned int)(crc >> 32u)};
    for (unsigned int at = 0u; at < head_words; at += 1u)
    {
        check_test_put(&words, head[at]);
    }
    unsigned int taken = 0u;
    for (unsigned int block = 0u; (head_words == 6u) && (block < blocks); block += 1u)
    {
        check_test_put(&words, counts[block]);
        for (unsigned int at = 0u; at < (counts[block] * record_words); at += 1u)
        {
            check_test_put(&words, records[taken + at]);
        }
        taken += counts[block] * record_words;
    }
    for (unsigned int at = 0u; at < extra; at += 1u)
    {
        check_test_put(&words, 0u);
    }
    return (words.count <= CHECK_TEST_WORDS) && check_test_sample_path(path, sizeof(path), set, sample, suffix) &&
           check_test_file(path, words.words, (size_t)words.count * 4u, (size_t)short_by * 4u);
}

// a sample's .divide: each frame pair's count and its divisions from `divisions`, four words each (check_test_beside)
static int check_test_divide(const char *set, const char *sample, const unsigned int view[4], unsigned long long skew,
                             const unsigned int *counts, const unsigned int *divisions, unsigned int extra,
                             unsigned int head_words, unsigned int short_by)
{
    return check_test_beside(set, sample, ".divide", view, skew, (view[0] > 0u) ? (view[0] - 1u) : 0u, counts,
                             divisions, 4u, extra, head_words, short_by);
}

// a sample's .drift: frames, the view and the weights 16, 1, 1, then each frame's positives (its points here) and
// after frame 0 its lag from `lags`, three words a frame from frame 0's, and an agreement of 1; `extra` words of 0
// past the last frame
static int check_test_drift(const char *set, const char *sample, const unsigned int view[4], const unsigned int *counts,
                            const unsigned int *lags, unsigned int extra)
{
    CheckTestWords words;
    memset(&words, 0, sizeof(words));
    const unsigned int head[7] = {view[0], view[1], view[2], view[3], 16u, 1u, 1u};
    for (unsigned int at = 0u; at < 7u; at += 1u)
    {
        check_test_put(&words, head[at]);
    }
    for (unsigned int frame = 0u; frame < view[0]; frame += 1u)
    {
        check_test_put(&words, counts[frame]);
        for (unsigned int axis = 0u; (frame > 0u) && (axis < 3u); axis += 1u)
        {
            check_test_put(&words, lags[(3u * frame) + axis]);
        }
        if (frame > 0u)
        {
            check_test_put(&words, 1u);
        }
    }
    for (unsigned int at = 0u; at < extra; at += 1u)
    {
        check_test_put(&words, 0u);
    }
    char path[CHECK_TEST_PATH];
    return (words.count <= CHECK_TEST_WORDS) && check_test_sample_path(path, sizeof(path), set, sample, ".drift") &&
           check_test_file(path, words.words, (size_t)words.count * 4u, 0u);
}

// a sample's .shape: frames, the view, the .points' limbs and `hessian_limbs`, then each frame's count, each point's
// faces from `faces`, and each point's six differences of `hessian_limbs` words, each 0x5A5A5A5A; `short_by` words are
// taken off the end
static int check_test_hessian(const char *set, const char *sample, const unsigned int view[4], unsigned int limbs,
                              unsigned int hessian_limbs, const unsigned int *counts, const unsigned int *faces,
                              unsigned int short_by)
{
    CheckTestWords words;
    memset(&words, 0, sizeof(words));
    const unsigned int head[6] = {view[0], view[1], view[2], view[3], limbs, hessian_limbs};
    for (unsigned int at = 0u; at < 6u; at += 1u)
    {
        check_test_put(&words, head[at]);
    }
    unsigned int taken = 0u;
    for (unsigned int frame = 0u; frame < view[0]; frame += 1u)
    {
        check_test_put(&words, counts[frame]);
        for (unsigned int at = 0u; at < counts[frame]; at += 1u)
        {
            check_test_put(&words, faces[taken + at]);
        }
        for (unsigned int at = 0u; at < (counts[frame] * 6u * hessian_limbs); at += 1u)
        {
            check_test_put(&words, 0x5A5A5A5Au);
        }
        taken += counts[frame];
    }
    char path[CHECK_TEST_PATH];
    return (words.count <= CHECK_TEST_WORDS) && check_test_sample_path(path, sizeof(path), set, sample, ".shape") &&
           check_test_file(path, words.words, (size_t)words.count * 4u, (size_t)short_by * 4u);
}

// chain's and second's .drift, .shape and .faces as worked (the head comment), chain's broken one way by the case;
// second has no .faces in bare
static int check_test_faces_files(const char *set, FacesCase which)
{
    unsigned int view[4] = {4u, 4u, 5u, 6u};
    const unsigned int counts[4] = {3u, 2u, 0u, 2u};
    // the lags onto frames 1, 2 and 3, three words a frame from frame 0's, which the .drift does not hold
    unsigned int lags[12] = {0u, 0u, 0u, 0xFFFFFFFFu, 0u, 3u, 0u, 0u, 0u, 1u, 0u, 0u};
    lags[9] = (which == FACES_CASE_PAST_32) ? 0x80000000u : lags[9];
    unsigned int drift_view[4] = {4u, 4u, 5u, 6u};
    drift_view[3] = (which == FACES_CASE_DRIFT_VIEW) ? 7u : drift_view[3];
    int ok = (which == FACES_CASE_DRIFT_MISSING) ||
             check_test_drift(set, "chain", drift_view, counts, lags, (which == FACES_CASE_DRIFT_TRAILING) ? 1u : 0u);
    unsigned int hessian_counts[4] = {3u, 2u, 0u, 2u};
    hessian_counts[0] = (which == FACES_CASE_HESSIAN_COUNT) ? 2u : hessian_counts[0];
    unsigned int hessian[7] = {0u, 0u, 0x20u, 0u, 0u, 0u, 0u};
    hessian[1] = (which == FACES_CASE_HESSIAN_SIX) ? 0x40u : hessian[1];
    ok = ok && check_test_hessian(set, "chain", view, 2u, (which == FACES_CASE_HESSIAN_LIMBS) ? 2u : 3u, hessian_counts,
                                  hessian, (which == FACES_CASE_HESSIAN_SHORT) ? 1u : 0u);
    // each point's back-prediction and flags: entering 1, leaving 2, first 4, last 8, then the faces its
    // back-prediction crosses at bit 8, its prediction at bit 16 and its .shape at bit 24
    unsigned int points[28] = {0u,          1u, 1u,          0x00000004u,  // A: first
                               1u,          3u, 2u,          0x00200006u,  // B: first, left past x's high face
                               3u,          1u, 4u,          0x20000004u,  // C: first, its .shape's x high face
                               1u,          1u, 0xFFFFFFFFu, 0x00001000u,  // A: back past x's low face, linked in
                               4u,          4u, 2u,          0x00080203u,  // D: entered past z's high, left past y's
                               0xFFFFFFFFu, 0u, 0u,          0x00000109u,  // E: last, entered past z's low face
                               0u,          0u, 1u,          0x00000008u}; // F: last
    unsigned int faces_counts[4] = {3u, 2u, 0u, 2u};
    faces_counts[0] = (which == FACES_CASE_COUNT) ? 2u : faces_counts[0];
    points[12] = (which == FACES_CASE_BACK) ? 0u : points[12];
    points[11] = (which == FACES_CASE_HESSIAN) ? 0x10000004u : points[11];
    points[19] = (which == FACES_CASE_VERDICT) ? 0x00080202u : points[19];
    view[0] = (which == FACES_CASE_FRAMES) ? 3u : view[0];
    view[3] = (which == FACES_CASE_VIEW) ? 7u : view[3];
    ok = ok && check_test_beside(set, "chain", ".faces", view, (which == FACES_CASE_CRC) ? 1ull : 0ull, view[0],
                                 faces_counts, points, 4u, (which == FACES_CASE_TRAILING) ? 1u : 0u,
                                 (which == FACES_CASE_HEAD) ? 3u : 6u, (which == FACES_CASE_SHORT) ? 4u : 0u);
    // second: the lag (0, 0, 1) onto frame 1; no .shape faces; P and Q first, R and S last, S back past x's low face
    const unsigned int second_view[4] = {2u, 1u, 2u, 3u};
    const unsigned int second_counts[2] = {2u, 2u};
    const unsigned int second_lags[6] = {0u, 0u, 0u, 0u, 0u, 1u};
    const unsigned int second_hessian[4] = {0u, 0u, 0u, 0u};
    const unsigned int second_points[16] = {0u, 0u, 0u, 0x4u, 0u, 1u, 2u,          0x4u,
                                            0u, 1u, 1u, 0x8u, 0u, 0u, 0xFFFFFFFFu, 0x1008u};
    ok = ok && check_test_drift(set, "second", second_view, second_counts, second_lags, 0u) &&
         check_test_hessian(set, "second", second_view, 0u, 1u, second_counts, second_hessian, 0u);
    return ok && ((which == FACES_CASE_BARE) || check_test_beside(set, "second", ".faces", second_view, 0ull, 2u,
                                                                  second_counts, second_points, 4u, 0u, 6u, 0u));
}

static int check_test_faces_case(const char *root, FacesCase which)
{
    char set[CHECK_TEST_PATH];
    char name[256];
    snprintf(name, sizeof(name), "faces_%s", FACES_CASE_NAMES[which]);
    if ((check_test_join(set, sizeof(set), root, name) == 0) || (check_test_directory(set, NULL) == 0))
    {
        return 0;
    }
    int ok = check_test_graph(set, OUTPUT_CASE_OK, which == FACES_CASE_OUTSIDE) && check_test_faces_files(set, which);
    if (which == FACES_CASE_DIVIDED)
    {
        // divide_good's: chain's A takes D, which starts; second's P takes R from Q
        const unsigned int chain_view[4] = {4u, 4u, 5u, 6u};
        const unsigned int chain_counts[3] = {1u, 0u, 0u};
        const unsigned int chain_divisions[4] = {0u, 0u, 1u, CHECK_TEST_NONE};
        const unsigned int pair_view[4] = {2u, 1u, 2u, 3u};
        const unsigned int pair_counts[1] = {1u};
        const unsigned int pair_divisions[4] = {0u, 1u, 0u, 1u};
        ok = ok && check_test_divide(set, "chain", chain_view, 0ull, chain_counts, chain_divisions, 0u, 6u, 0u) &&
             check_test_divide(set, "second", pair_view, 0ull, pair_counts, pair_divisions, 0u, 6u, 0u);
    }
    const char *const nodes = (which == FACES_CASE_DIVIDED)
                                  ? CHECK_TEST_FACED_DIVIDED_NODES
                                  : ((which == FACES_CASE_ROWS) ? CHECK_TEST_NODES : CHECK_TEST_FACED_NODES);
    const char *const submission =
        (which == FACES_CASE_DIVIDED) ? CHECK_TEST_DIVIDED_SUBMISSION : CHECK_TEST_SUBMISSION;
    char path[CHECK_TEST_PATH];
    return ok && check_test_join(path, sizeof(path), set, "nodes.tsv") &&
           check_test_file(path, nodes, strlen(nodes), 0u) &&
           check_test_join(path, sizeof(path), set, "submission.csv") &&
           check_test_file(path, submission, strlen(submission), 0u);
}

// fork: 2 frames in second's view, P (0) and Q (5), then R (5), S (0) and T (3); P links to S at cost 0 and Q to R at
// cost 3, and P to T is in the gate and not chosen, so T starts
static int check_test_fork(const char *set)
{
    const unsigned int head[6] = {2u, 1u, 2u, 3u, 0u, 34u};
    const unsigned int counts[2] = {2u, 3u};
    const unsigned int voxels[5] = {0u, 5u, 5u, 0u, 3u};
    CheckTestWords words;
    memset(&words, 0, sizeof(words));
    check_test_links_head(&words, 2u, 1u, 2u, 3u);
    check_test_pair(&words, 2u, 3u, 3u, 2u);
    check_test_source(&words, 0u, 0u, 0u, 0u);
    check_test_source(&words, 0u, 1u, 2u, 0u);
    check_test_gate(&words, 0u, 1u, 0ull, 1);
    check_test_gate(&words, 0u, 2u, 4ull, 0);
    check_test_gate(&words, 1u, 0u, 3ull, 1);
    return check_test_graph_points(set, "fork", head, counts, voxels, 0, 0) &&
           check_test_graph_links(set, "fork", &words);
}

static int check_test_divide_case(const char *root, DivideCase which)
{
    char set[CHECK_TEST_PATH];
    char name[256];
    snprintf(name, sizeof(name), "divide_%s", DIVIDE_CASE_NAMES[which]);
    if ((check_test_join(set, sizeof(set), root, name) == 0) || (check_test_directory(set, NULL) == 0))
    {
        return 0;
    }
    int ok = check_test_graph(set, OUTPUT_CASE_OK, 0) && check_test_fork(set);
    const unsigned int chain_view[4] = {4u, 4u, 5u, 6u};
    const unsigned int pair_view[4] = {2u, 1u, 2u, 3u};
    const unsigned int none[3] = {0u, 0u, 0u};
    // chain: A divides, keeping its link to A and taking D, which starts
    const unsigned int chain_counts[3] = {1u, 0u, 0u};
    const unsigned int chain_divisions[4] = {0u, 0u, 1u, CHECK_TEST_NONE};
    ok = ok && check_test_divide(set, "chain", chain_view, 0ull, (which == DIVIDE_CASE_NONE) ? none : chain_counts,
                                 chain_divisions, 0u, 6u, 0u);
    // second: P divides, keeping its link to S and taking R from Q; broken one way by the case
    unsigned int view[4] = {2u, 1u, 2u, 3u};
    view[0] = (which == DIVIDE_CASE_FRAMES) ? 3u : view[0];
    view[3] = (which == DIVIDE_CASE_VIEW) ? 4u : view[3];
    unsigned int counts[2] = {(which == DIVIDE_CASE_COUNT) ? 3u : ((which == DIVIDE_CASE_NONE) ? 0u : 1u), 0u};
    unsigned int divisions[12] = {0u, 1u, 0u, 1u};
    switch (which)
    {
    case DIVIDE_CASE_PARENT:
        divisions[0] = 2u;
        break;
    case DIVIDE_CASE_ONE:
        divisions[1] = 0u;
        divisions[2] = 1u;
        divisions[3] = 0u;
        break;
    case DIVIDE_CASE_TWO:
        divisions[2] = 1u;
        divisions[3] = 0u;
        break;
    case DIVIDE_CASE_TWO_PAST:
        divisions[2] = 2u;
        divisions[3] = CHECK_TEST_NONE;
        break;
    case DIVIDE_CASE_LEFT:
        divisions[3] = CHECK_TEST_NONE;
        break;
    case DIVIDE_CASE_ORDER: {
        // Q divides first, taking S from P; then P, which comes before Q
        const unsigned int two[8] = {1u, 0u, 1u, 0u, 0u, 1u, 0u, 1u};
        memcpy(divisions, two, sizeof(two));
        counts[0] = 2u;
    }
    break;
    default:
        break;
    }
    ok = ok && check_test_divide(set, "second", view, (which == DIVIDE_CASE_CRC) ? 1ull : 0ull, counts, divisions,
                                 (which == DIVIDE_CASE_TRAILING) ? 1u : 0u, (which == DIVIDE_CASE_HEAD) ? 3u : 6u,
                                 (which == DIVIDE_CASE_SHORT) ? 4u : 0u);
    // fork: no .divide, but one of no divisions beside each sample, and for a division taking from a point that
    // divides: P takes T, which starts, and then Q, keeping its link to R, takes S from P
    const unsigned int fork_counts[1] = {2u};
    const unsigned int fork_divisions[8] = {0u, 1u, 2u, CHECK_TEST_NONE, 1u, 0u, 1u, 0u};
    if ((which == DIVIDE_CASE_NONE) || (which == DIVIDE_CASE_DIVIDES))
    {
        ok = ok && check_test_divide(set, "fork", pair_view, 0ull, (which == DIVIDE_CASE_NONE) ? none : fork_counts,
                                     fork_divisions, 0u, 6u, 0u);
    }
    // the files: the divided rows, but the sort's with no divisions and in the case whose files are the sort's; fork's
    // rows after, its ids counting on from the others'
    const int divided = (which != DIVIDE_CASE_NONE) && (which != DIVIDE_CASE_ROWS);
    const unsigned int first = divided ? 15u : 14u;
    char nodes[4096];
    char submission[4096];
    const int nodes_length = snprintf(nodes, sizeof(nodes), "%s%s",
                                      divided ? CHECK_TEST_DIVIDED_NODES : CHECK_TEST_NODES, CHECK_TEST_FORK_NODES);
    const int submission_length = snprintf(submission, sizeof(submission),
                                           "%s%u,fork,node,1,0,0,0,0,-1,-1\n%u,fork,node,2,0,0,1,2,-1,-1\n"
                                           "%u,fork,node,3,1,0,1,2,-1,-1\n%u,fork,node,4,1,0,0,0,-1,-1\n"
                                           "%u,fork,node,5,1,0,1,0,-1,-1\n%u,fork,edge,-1,-1,-1,-1,-1,1,4\n"
                                           "%u,fork,edge,-1,-1,-1,-1,-1,2,3\n",
                                           divided ? CHECK_TEST_DIVIDED_SUBMISSION : CHECK_TEST_SUBMISSION, first,
                                           first + 1u, first + 2u, first + 3u, first + 4u, first + 5u, first + 6u);
    char path[CHECK_TEST_PATH];
    // a non-negative length is compared whole against the capacity
    return ok && (nodes_length > 0) && ((size_t)nodes_length < sizeof(nodes)) && (submission_length > 0) &&
           ((size_t)submission_length < sizeof(submission)) && check_test_join(path, sizeof(path), set, "nodes.tsv") &&
           check_test_file(path, nodes, (size_t)nodes_length, 0u) &&
           check_test_join(path, sizeof(path), set, "submission.csv") &&
           check_test_file(path, submission, (size_t)submission_length, 0u);
}

int main(int count, char **arguments)
{
    if (count != 2)
    {
        printf("  usage: check_test <directory>\n");
        return 2;
    }
    (void)CHECK_TEST_MKDIR(arguments[1]);
    unsigned int written = 0u;
    for (unsigned int which = 0u; which < (unsigned int)POINTS_CASES; which += 1u)
    {
        const int ok = check_test_points_case(arguments[1], (PointsCase)which);
        written += ok ? 1u : 0u;
        printf("  %s points_%s\n", ok ? "wrote" : "COULD NOT WRITE", POINTS_CASE_NAMES[which]);
    }
    for (unsigned int which = 0u; which < (unsigned int)OUTPUT_CASES; which += 1u)
    {
        const int ok = check_test_output_case(arguments[1], (OutputCase)which);
        written += ok ? 1u : 0u;
        printf("  %s output_%s\n", ok ? "wrote" : "COULD NOT WRITE", OUTPUT_CASE_NAMES[which]);
    }
    for (unsigned int which = 0u; which < (unsigned int)DIVIDE_CASES; which += 1u)
    {
        const int ok = check_test_divide_case(arguments[1], (DivideCase)which);
        written += ok ? 1u : 0u;
        printf("  %s divide_%s\n", ok ? "wrote" : "COULD NOT WRITE", DIVIDE_CASE_NAMES[which]);
    }
    for (unsigned int which = 0u; which < (unsigned int)FACES_CASES; which += 1u)
    {
        const int ok = check_test_faces_case(arguments[1], (FacesCase)which);
        written += ok ? 1u : 0u;
        printf("  %s faces_%s\n", ok ? "wrote" : "COULD NOT WRITE", FACES_CASE_NAMES[which]);
    }
    const unsigned int cases = (unsigned int)(POINTS_CASES + OUTPUT_CASES + DIVIDE_CASES + FACES_CASES);
    printf("  wrote %u of %u cases\n", written, cases);
    return (written == cases) ? 0 : 1;
}
