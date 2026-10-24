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

#endif
