{ config
, pkgs
, lib
, ...
}:
let
  cfg = config.CUSTOM.services.dictated;

  # Parakeet TDT 0.6B v2 int8 weights for sherpa-onnx.
  #
  # Fetch a commit, never `main`: Hugging Face re-exports files in place (every
  # int8 file here changed on 2026-11-07), so a `resolve/main` URL turns the
  # next flake update into a hash mismatch against unchanged hashes.
  #
  # Bump the revision and all four hashes together with
  # `scripts/update-parakeet-model.sh`, which reads them from the Hugging Face
  # API (LFS metadata) instead of downloading the 650 MB encoder.
  # BEGIN parakeet-model-pin (written by scripts/update-parakeet-model.sh)
  modelRev = "84b478d541cdbf0c296a7ab5f1e20a6f8f998114";
  modelHashes = {
    "encoder.int8.onnx" = "sha256-kqEL2cI5NuoFZsKfljvFfCpd9CYbaokhw5q+pmVXyos=";
    "decoder.int8.onnx" = "sha256-TQl7rjusXJYBjVKTujnxtlcpYQKxQq/9pAN484sCD0E=";
    "joiner.int8.onnx" = "sha256-d6KfPlrH03B04K9GU5G4DzFAFdW5fw+Qxsd2fx1W9Cg=";
    "tokens.txt" = "sha256-7BgrcN1CETr/bFNyx1ysWMlSRD6yIyL1e71/U5d9SX0=";
  };
  # END parakeet-model-pin

  fetch = name: pkgs.fetchurl {
    url = "https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8/resolve/${modelRev}/${name}";
    hash = modelHashes.${name};
    name = "parakeet-${name}";
  };

  models = pkgs.runCommand "parakeet-tdt-0.6b-v2-int8" { } ''
    mkdir -p $out
    cp ${fetch "encoder.int8.onnx"} $out/encoder.int8.onnx
    cp ${fetch "decoder.int8.onnx"} $out/decoder.int8.onnx
    cp ${fetch "joiner.int8.onnx"} $out/joiner.int8.onnx
    cp ${fetch "tokens.txt"} $out/tokens.txt
  '';

  # Silero VAD: 1.8 MB, used to split recordings at pauses so silence is never
  # decoded and long clips are recognised as utterance-sized segments.
  vadModel = pkgs.fetchurl {
    url = "https://huggingface.co/csukuangfj/vad/resolve/fba88cd2e921609e7675c3aaf51e0b9b295da4bc/silero_vad.onnx";
    hash = "sha256-o16/Uv085fFGmyo2FY26dhvEe5c+ozgrMYbKFbH1ryg=";
    name = "silero_vad.onnx";
  };

  # The sherpa runtime ships inside the dsh package; load it from there rather
  # than building an ONNX Runtime binding of our own.
  runtime = "${pkgs.llm-agents.dsh}/lib/node_modules/@deepseek-ai/dsh/node_modules/sherpa-onnx-node";

  daemon = pkgs.buildGoModule {
    pname = "dictated";
    version = "0.4.0";
    src = ./.;
    vendorHash = null;
    doCheck = false;
    env = {
      CGO_ENABLED = "1";
      CGO_CFLAGS = "-I${pkgs.sherpa-onnx}/include";
      # Link the shared sherpa-onnx and record where to find it and ONNX
      # Runtime at run time.
      CGO_LDFLAGS = "-L${pkgs.sherpa-onnx}/lib -lsherpa-onnx-c-api -Wl,-rpath,${pkgs.sherpa-onnx}/lib -Wl,-rpath,${pkgs.onnxruntime}/lib";
    };
    buildInputs = [ pkgs.sherpa-onnx pkgs.onnxruntime ];
  };
in
{
  options.CUSTOM.services.dictated = {
    enable = lib.mkEnableOption "dictated, the warm Parakeet transcription daemon";
    threads = lib.mkOption {
      type = lib.types.int;
      default = 6;
      description = "CPU threads the recognizer may use";
    };
    vad = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Trim every recording to its speech with Silero VAD, and split clips
        longer than vadMinSeconds at pauses. Costs roughly 0.15-0.3 s per short
        clip, so turn it off when latency matters more than skipping silence.
      '';
    };
    vadMinSeconds = lib.mkOption {
      type = lib.types.float;
      default = 30.0;
      description = ''
        Recordings shorter than this are decoded whole. Longer ones are split
        at pauses by Silero VAD, so silence is skipped and each segment is
        utterance-sized. Splitting costs punctuation and capitalisation at
        every boundary, which is why the default leaves short clips alone.
      '';
    };
    maxBytes = lib.mkOption {
      type = lib.types.int;
      default = 64 * 1024 * 1024;
      description = ''
        Largest recording accepted, in bytes of 16 kHz s16 mono PCM.
        The default 64 MiB is about 35 minutes.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.dictated = {
      Unit = {
        Description = "dictated — warm Parakeet TDT 0.6B transcription daemon";
        After = [ "pipewire.service" ];
      };
      Service = {
        ExecStart = "${daemon}/bin/dictated";
        Restart = "always";
        RestartSec = "2s";
        Environment = [
          "DICTATED_SOCKET=%t/dictated/socket"
          "DICTATED_MODEL_DIR=${models}"
          "DICTATED_RUNTIME=${runtime}"
          "DICTATED_THREADS=${toString cfg.threads}"
          "DICTATED_MAX_BYTES=${toString cfg.maxBytes}"
        ] ++ lib.optionals cfg.vad [
          "DICTATED_VAD_MODEL=${vadModel}"
          "DICTATED_VAD_MIN_SECONDS=${toString cfg.vadMinSeconds}"
        ];
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
