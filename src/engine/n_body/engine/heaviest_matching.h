#ifndef HEAVIEST_MATCHING_H
#define HEAVIEST_MATCHING_H

#ifdef __cplusplus
extern "C" {
#endif

#if defined(HEAVIEST_MATCHING_BUILD_DLL) && HEAVIEST_MATCHING_BUILD_DLL && defined(_WIN32)
#define HEAVIEST_MATCHING_EXPORT __declspec(dllexport)
#else
#define HEAVIEST_MATCHING_EXPORT
#endif

#define HEAVIEST_MATCHING_REFUSED (-1L)

typedef struct
{
    const unsigned int *before;
    const unsigned int *after;
    const unsigned int *counts;
    unsigned int pairs;
    unsigned int before_count;
    unsigned int after_count;
    unsigned char *chosen;
} HeaviestMatchingRequest;

HEAVIEST_MATCHING_EXPORT long heaviest_matching_run(const HeaviestMatchingRequest *args);

#ifdef __cplusplus
}
#endif

#endif
