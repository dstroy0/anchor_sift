#ifndef SHIFT_AGREEMENT_H
#define SHIFT_AGREEMENT_H

#ifdef __cplusplus
extern "C" {
#endif

#if defined(SHIFT_AGREEMENT_BUILD_DLL) && SHIFT_AGREEMENT_BUILD_DLL && defined(_WIN32)
#define SHIFT_AGREEMENT_EXPORT __declspec(dllexport)
#else
#define SHIFT_AGREEMENT_EXPORT
#endif

#define SHIFT_AGREEMENT_REFUSED (-1L)

#define SHIFT_AGREEMENT_AXES 8u

#define SHIFT_AGREEMENT_PRIME 998244353u

#define SHIFT_AGREEMENT_LONGEST_AXIS (1u << 23u)

typedef struct
{
    unsigned int axes;
    unsigned int extents[SHIFT_AGREEMENT_AXES];
    unsigned int weights[SHIFT_AGREEMENT_AXES];
    const unsigned long long *before;
    const unsigned long long *after;
    int lag[SHIFT_AGREEMENT_AXES];
    unsigned int agreement;
    unsigned int padded[SHIFT_AGREEMENT_AXES];
    unsigned int *counts;
} ShiftAgreementRequest;

SHIFT_AGREEMENT_EXPORT long shift_agreement_host(ShiftAgreementRequest *args);

SHIFT_AGREEMENT_EXPORT long shift_agreement_run(ShiftAgreementRequest *args);

#ifdef __cplusplus
}
#endif

#endif
