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
