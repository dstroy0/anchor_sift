// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// obsignatio_hash.cu: the hash, chunks and their kernel
#include "obsignatio_internal.h"

int obsignatio_mode_valid(unsigned int mode, const unsigned char *key)
{
    const int unkeyed = (mode == OBSIGNATIO_MODE_HASH) || (mode == OBSIGNATIO_MODE_CONTEXT);
    const int keyed = (mode == OBSIGNATIO_MODE_KEYED) || (mode == OBSIGNATIO_MODE_MATERIAL);
    return (unkeyed && (key == NULL)) || (keyed && (key != NULL));
}

ObsignatioKey obsignatio_key_load(const unsigned char *key)
{
    ObsignatioKey loaded;
    if (key == NULL)
    {
        loaded.words[0] = OBSIGNATIO_IV0;
        loaded.words[1] = OBSIGNATIO_IV1;
        loaded.words[2] = OBSIGNATIO_IV2;
        loaded.words[3] = OBSIGNATIO_IV3;
        loaded.words[4] = OBSIGNATIO_IV4;
        loaded.words[5] = OBSIGNATIO_IV5;
        loaded.words[6] = OBSIGNATIO_IV6;
        loaded.words[7] = OBSIGNATIO_IV7;
        return loaded;
    }
    for (unsigned int word = 0u; word < OBSIGNATIO_CHAINING_WORDS; word += 1u)
    {
        loaded.words[word] = 0u;
        for (unsigned int byte = 0u; byte < 4u; byte += 1u)
        {
            // an unsigned char widens to unsigned int exactly. The shift into the top byte stays defined
            loaded.words[word] |= (unsigned int)key[(word * 4u) + byte] << (8u * byte);
        }
    }
    return loaded;
}

extern "C" long obsignatio_signum(const ObsignatioSignumRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return OBSIGNATIO_ERROR;
    }
    EngineError *const error = request->error;
    if (OBSIGNATIO_CHECK(((request->bytes != NULL) || (request->count == 0ull)) &&
                             ((request->out != NULL) || (request->out_bytes == 0ull)) &&
                             obsignatio_mode_valid(request->mode, request->key),
                         request, error) == 0)
    {
        return OBSIGNATIO_ERROR;
    }
    const ObsignatioKey key = obsignatio_key_load(request->key);
    const ObsignatioSource source = {request->bytes, NULL, 0ull, 0ull, request->count};
    obsignatio_digest(key.words, request->mode, &source, request->out, request->out_bytes);
    return 0L;
}
#if (defined(__CUDACC__))
__global__ void obsignatio_chunk_kernel(const unsigned char *bytes, unsigned long long messages,
                                        unsigned long long length, unsigned long long stride, unsigned long long chunks,
                                        ObsignatioKey key, unsigned int mode, unsigned int *chaining,
                                        unsigned char *signa)
{
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long index = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
         index < (messages * chunks); index += jump)
    {
        const unsigned long long message = index / chunks;
        const unsigned long long chunk = index % chunks;
        const unsigned long long start = chunk << OBSIGNATIO_CHUNK_SHIFT;
        const unsigned long long remain = length - start;
        // the take is at most one chunk's 1024 bytes. It fits an unsigned int
        const unsigned int take = (remain < OBSIGNATIO_CHUNK_BYTES) ? (unsigned int)remain : OBSIGNATIO_CHUNK_BYTES;
        const ObsignatioSource source = {&bytes[message * stride], NULL, 0ull, 0ull, length};
        ObsignatioNode node;
        obsignatio_chunk(key.words, mode, &source, start, take, chunk, &node);
        if (chunks == 1ull)
        {
            obsignatio_root(&node, &signa[message * OBSIGNATIO_SIGNUM_BYTES], OBSIGNATIO_SIGNUM_BYTES);
        }
        else
        {
            obsignatio_chaining(&node, &chaining[index * OBSIGNATIO_CHAINING_WORDS]);
        }
    }
}
#endif
