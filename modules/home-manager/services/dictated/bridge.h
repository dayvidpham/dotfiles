/* Thin C surface over sherpa-onnx for cgo; keeps struct layouts in C. */
#ifndef DICTATED_BRIDGE_H
#define DICTATED_BRIDGE_H

#include <stdint.h>

void *dictated_create(const char *encoder, const char *decoder,
                      const char *joiner, const char *tokens,
                      int32_t threads, const char *provider);

char *dictated_transcribe(void *handle, const float *samples, int32_t count);

void dictated_free_string(char *text);

void dictated_destroy(void *handle);

/* Silero VAD: create once per request, split, destroy. */
void *dictated_vad_create(const char *model, float threshold,
                          float min_silence, float min_speech);

/* Feed the whole clip, flush, and write (start, count) pairs into `pairs`.
 * Returns the number of segments written, capped at max_pairs. */
int32_t dictated_vad_split(void *handle, const float *samples, int32_t count,
                           int32_t *pairs, int32_t max_pairs);

void dictated_vad_destroy(void *handle);

#endif
