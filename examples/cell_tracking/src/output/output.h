// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef OUTPUT_H
#define OUTPUT_H

#include <stdio.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define OUTPUT_ERROR (-1L)

// the submission's header, which open_output writes as the file opens
#define OUTPUT_SUBMISSION_HEADER "id,dataset,row_type,node_id,t,z,y,x,source_id,target_id\n"

// the nodes' state column, in the codes of track.h's BODY_ENTERED, BODY_SPLIT and BODY_LEFT: a start whose
// back-prediction lies outside the view entered it, a division's daughter two split from its parent, and an end whose
// prediction lies outside the view left it. A point is none of them, 0, unless its sample has a .faces or a .divide
#define OUTPUT_STATE_ENTERED 0x001u
#define OUTPUT_STATE_SPLIT 0x008u
#define OUTPUT_STATE_LEFT 0x020u

    // S11 on the sort's links, every point kept: each point of each frame a node, each chosen link from frame t to t +
    // 1 an edge, and each division of a sample's .divide (src/divide/divide.h), when it has one, a second link out of
    // its parent, moved from the point daughter two leaves. A sample's .faces (src/faces/faces.h), when it has one,
    // gives each point's state and splits its ends and starts into those the view's faces explain and the rest. `nodes`
    // takes the nodes, one row a point under the nodes header; `submission` takes the submission, each sample's node
    // rows and then its edge rows. Either may be NULL, and then it is not written. `report` takes the counts, a line a
    // sample and the set's; an error's reason goes to stderr
    typedef struct
    {
        const char *set;
        char *const *samples;
        unsigned int count;
        FILE *nodes;
        FILE *submission;
        FILE *report;
    } OutputRequest;

    // reads each sample's .points, .links, and its .faces and .divide when it has them, and checks its graph whole
    // first (the .faces and the .divide each made from these .links, by their CRC-64, and every .faces verdict the one
    // the .links' own links and predictions give; O20: at most one link in to each point, and one out of each but a
    // division's parent, which has two; H4 on each frame pair), counting its ends and starts frame by frame; then
    // writes every sample's rows. A sample with neither file is written as the sort's links alone, every state 0. A
    // sample that breaks writes no sample's rows, and the set errors
    long output_graph_set(const OutputRequest *request);

    // closes a file the output wrote, checked: a write that failed on it, or a close that fails, has lost rows. NULL is
    // no file, which holds. When the file did not close whole its name goes to stderr and 0 is returned; 1 when it did
    int output_close(FILE *file, const char *name);

#ifdef OUTPUT_TEST_FAULTS
    // the test's faults, compiled into test/output_test alone: `output_test_skew` is added to each frame pair's ends
    // before H4 is checked, and `output_test_between`, when set, is called with the request between the two passes
    extern unsigned long long output_test_skew;
    extern void (*output_test_between)(const OutputRequest *request);
#endif

#ifdef __cplusplus
}
#endif

#endif
