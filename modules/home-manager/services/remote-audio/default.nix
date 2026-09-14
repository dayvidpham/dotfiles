{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.services.remote-audio;

  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    getExe
    optionalString
    ;

  # Capture the remote session's audio and stream it over RTP+RS8M (Reed-Solomon
  # FEC) to the peer. The session's apps play into a dedicated null sink
  # (created via PipeWire config) whose monitor roc-send captures.
  sendScript = pkgs.writeShellApplication {
    name = "remote-audio-send";
    runtimeInputs = [ pkgs.roc-toolkit pkgs.glibc pkgs.gawk pkgs.coreutils ];
    text = ''
      set -eu
      peer="${cfg.peer}"
      case "$peer" in
        *:*) ;;                       # already an IPv6 / host:port
        *[0-9].[0-9]*) ;;             # already an IPv4
        *) resolved="$(getent hosts "$peer" 2>/dev/null | awk '{print $1}' | head -n1)"
           [ -n "$resolved" ] && peer="$resolved" ;;
      esac
      exec roc-send -v \
        -i pulse://${cfg.sinkName}.monitor \
        -s rtp+rs8m://"$peer":${toString cfg.port} \
        -r rs8m://"$peer":${toString cfg.repairPort} \
        --target-latency=${cfg.latency}
    '';
  };

  # Receive from the tailnet interface only (so RTP is never exposed elsewhere;
  # WireGuard encrypts it) and play out to the default Pulse sink.
  recvScript = pkgs.writeShellApplication {
    name = "remote-audio-recv";
    runtimeInputs = [ pkgs.roc-toolkit pkgs.iproute2 pkgs.gawk pkgs.coreutils ];
    text = ''
      set -eu
      bind="${cfg.bindAddress}"
      if [ -z "$bind" ]; then
        bind="$(ip -4 -o addr show dev "${cfg.interfaceName}" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)"
      fi
      if [ -z "$bind" ]; then
        echo "remote-audio-recv: no address on ${cfg.interfaceName}" >&2
        exit 1
      fi
      exec roc-recv -v \
        -o pulse://${cfg.sourceDevice} \
        -s rtp+rs8m://"$bind":${toString cfg.port} \
        -r rs8m://"$bind":${toString cfg.repairPort} \
        --miface="$bind" \
        --target-latency=${cfg.latency}
    '';
  };

  # Persistent virtual sink the remote session plays into. object.linger keeps
  # it alive without a client holding it open.
  nullSink = ''
    context.objects = [
      { factory = adapter
        args = {
          factory.name = support.null-audio-sink
          node.name = ${cfg.sinkName}
          node.description = "Remote session audio"
          media.class = Audio/Sink
          object.linger = true
          audio.position = [ FL FR ]
        }
      }
    ]
  '';
in
{
  options.CUSTOM.services.remote-audio = {
    enable = mkEnableOption "stream the remote session's audio over RTP (roc)";

    role = mkOption {
      type = types.enum [ "send" "recv" ];
      description = "send = capture and stream; recv = receive and play out";
    };

    peer = mkOption {
      type = types.str;
      default = "flowx13";
      description = "Send: receiver host (MagicDNS name or IP)";
    };

    interfaceName = mkOption {
      type = types.str;
      default = "tailscale0";
      description = "Recv: bind the RTP sockets to this interface's IPv4";
    };

    bindAddress = mkOption {
      type = types.str;
      default = "";
      description = "Recv: explicit bind address (overrides interfaceName detection)";
    };

    port = mkOption {
      type = types.port;
      default = 10001;
      description = "RTP source port";
    };

    repairPort = mkOption {
      type = types.port;
      default = 10002;
      description = "RTP repair (FEC) port";
    };

    latency = mkOption {
      type = types.str;
      default = "200ms";
      description = "Target latency";
    };

    sinkName = mkOption {
      type = types.str;
      default = "remote_audio";
      description = "Send: name of the null sink whose monitor is captured";
    };

    sourceDevice = mkOption {
      type = types.str;
      default = "default";
      description = "Recv: Pulse sink to play out to";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ pkgs.roc-toolkit ];

    systemd.user.services = {
      remote-audio-send = mkIf (cfg.role == "send") {
        Unit = {
          Description = "Stream remote session audio over RTP (roc)";
          After = [ "pipewire-pulse.service" "pipewire.service" ];
          PartOf = [ "pipewire-pulse.service" ];
        };
        Service = {
          ExecStart = "${getExe sendScript}";
          Restart = "always";
          RestartSec = 3;
        };
        Install.WantedBy = [ "default.target" ];
      };

      remote-audio-recv = mkIf (cfg.role == "recv") {
        Unit = {
          Description = "Receive remote session audio over RTP (roc)";
          After = [ "pipewire-pulse.service" "pipewire.service" ];
          PartOf = [ "pipewire-pulse.service" ];
        };
        Service = {
          ExecStart = "${getExe recvScript}";
          Restart = "always";
          RestartSec = 3;
        };
        Install.WantedBy = [ "default.target" ];
      };
    };

    xdg.configFile = mkIf (cfg.role == "send") {
      "pipewire/pipewire.conf.d/10-remote-audio.conf".text = nullSink;
    };
  };
}
