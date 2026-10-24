#include <stdlib.h>
#include <string.h>

#include "sherpa-onnx/c-api/c-api.h"

#include "bridge.h"

void *dictated_create(const char *encoder, const char *decoder,
                      const char *joiner, const char *tokens,
                      int32_t threads, const char *provider) {
  SherpaOnnxOfflineRecognizerConfig config;
  memset(&config, 0, sizeof(config));

  config.feat_config.sample_rate = 16000;
  config.feat_config.feature_dim = 80;

  config.model_config.transducer.encoder = encoder;
  config.model_config.transducer.decoder = decoder;
  config.model_config.transducer.joiner = joiner;
  config.model_config.tokens = tokens;
  config.model_config.num_threads = threads;
  config.model_config.debug = 0;
  config.model_config.provider = provider;

  config.decoding_method = "greedy_search";

  return (void *)SherpaOnnxCreateOfflineRecognizer(&config);
}

char *dictated_transcribe(void *handle, const float *samples, int32_t count) {
  const SherpaOnnxOfflineRecognizer *recognizer =
      (const SherpaOnnxOfflineRecognizer *)handle;

  const SherpaOnnxOfflineStream *stream =
      SherpaOnnxCreateOfflineStream(recognizer);
  SherpaOnnxAcceptWaveformOffline(stream, 16000, samples, count);
  SherpaOnnxDecodeOfflineStream(recognizer, stream);

  const SherpaOnnxOfflineRecognizerResult *result =
      SherpaOnnxGetOfflineStreamResult(stream);
  char *text = strdup(result->text != NULL ? result->text : "");

  SherpaOnnxDestroyOfflineRecognizerResult(result);
  SherpaOnnxDestroyOfflineStream(stream);

  return text;
}

void dictated_free_string(char *text) { free(text); }

void dictated_destroy(void *handle) {
  SherpaOnnxDestroyOfflineRecognizer(
      (const SherpaOnnxOfflineRecognizer *)handle);
}

void *dictated_vad_create(const char *model, float threshold,
                          float min_silence, float min_speech) {
  SherpaOnnxVadModelConfig config;
  memset(&config, 0, sizeof(config));

  config.silero_vad.model = model;
  config.silero_vad.threshold = threshold;
  config.silero_vad.min_silence_duration = min_silence;
  config.silero_vad.min_speech_duration = min_speech;
  config.silero_vad.window_size = 512;
  config.sample_rate = 16000;
  config.num_threads = 1;
  config.provider = "cpu";
  config.debug = 0;

  return (void *)SherpaOnnxCreateVoiceActivityDetector(&config, 30.0f);
}

int32_t dictated_vad_split(void *handle, const float *samples, int32_t count,
                           int32_t *pairs, int32_t max_pairs) {
  const SherpaOnnxVoiceActivityDetector *vad =
      (const SherpaOnnxVoiceActivityDetector *)handle;

  /* Feed in window_size chunks: a single huge buffer only yields the tail
   * segment, because the detector advances one window per call. */
  const int32_t window = 512;
  for (int32_t offset = 0; offset < count; offset += window) {
    int32_t n = count - offset;
    if (n > window) n = window;
    SherpaOnnxVoiceActivityDetectorAcceptWaveform(vad, samples + offset, n);
  }
  SherpaOnnxVoiceActivityDetectorFlush(vad);

  int32_t segments = 0;
  while (!SherpaOnnxVoiceActivityDetectorEmpty(vad)) {
    const SherpaOnnxSpeechSegment *segment =
        SherpaOnnxVoiceActivityDetectorFront(vad);
    if (segment != NULL) {
      if (segments < max_pairs) {
        pairs[segments * 2] = segment->start;
        pairs[segments * 2 + 1] = segment->n;
        segments++;
      }
      SherpaOnnxDestroySpeechSegment(segment);
    }
    SherpaOnnxVoiceActivityDetectorPop(vad);
  }
  return segments;
}

void dictated_vad_destroy(void *handle) {
  SherpaOnnxDestroyVoiceActivityDetector(
      (const SherpaOnnxVoiceActivityDetector *)handle);
}
