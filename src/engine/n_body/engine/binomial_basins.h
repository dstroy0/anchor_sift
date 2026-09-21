#ifndef BINOMIAL_BASINS_H
#define BINOMIAL_BASINS_H

#ifdef __cplusplus
extern "C" {
#endif

#if defined(BINOMIAL_BASINS_BUILD_DLL) && BINOMIAL_BASINS_BUILD_DLL && defined(_WIN32)
#define BINOMIAL_BASINS_EXPORT __declspec(dllexport)
#else
#define BINOMIAL_BASINS_EXPORT
#endif

#define BINOMIAL_BASINS_REFUSED (-1L)

#define BINOMIAL_BASINS_LIMBS 9u

#define BINOMIAL_BASINS_PASS_ORDER 32u

#define BINOMIAL_BASINS_ROOM_LIMIT 0x7FFFFFFFu

typedef struct
{
    const unsigned short *volume;
    unsigned int depth;
    unsigned int height;
    unsigned int width;
    unsigned int smooth_orders[3];
    unsigned int background_orders[3];
    unsigned int room;
    unsigned int *peak_indices;
    unsigned int *sizes;
    unsigned long long *sums;
    unsigned int *peak_limbs;

    unsigned int adjacency_room;
    unsigned int *adjacency;

    unsigned int *adjacency_count;
    unsigned int *labels;
    unsigned int *residual_limbs;

    unsigned long long *positive_words;

    unsigned int joined_room;
    unsigned int *joined;

    unsigned int *joined_count;
} BinomialBasinsRequest;

BINOMIAL_BASINS_EXPORT long binomial_basins_host(const BinomialBasinsRequest *args);

BINOMIAL_BASINS_EXPORT long binomial_basins_run(const BinomialBasinsRequest *args);

#ifdef __cplusplus
}
#endif

#endif
