{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.services.powermode;

  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    types
    ;

  # Stateless sysfs-write override.
  # TLP re-asserts its profile on the next udev AC/BAT event, so manual mode
  # naturally expires on plug/unplug/suspend-resume — matching the "auto as default" goal.
  powermode = pkgs.writeShellApplication {
    name = "powermode";
    runtimeInputs = with pkgs; [ tlp coreutils systemd procps ];
    text = ''
      STATE_DIR=/run/powermode
      STATE_FILE="$STATE_DIR/current"

      read_state() {
        if [[ -f "$STATE_FILE" ]]; then cat "$STATE_FILE"; else echo auto; fi
      }

      ac_online() {
        local f
        for f in /sys/class/power_supply/A*/online; do
          if [[ -f "$f" && "$(cat "$f")" == "1" ]]; then return 0; fi
        done
        return 1
      }

      set_governor() {
        local val="$1" f
        for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
          if [[ -w "$f" ]]; then echo "$val" > "$f" || true; fi
        done
      }

      set_epp() {
        local val="$1" f
        for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
          if [[ -w "$f" ]]; then echo "$val" > "$f" || true; fi
        done
      }

      set_boost() {
        local val="$1"
        if [[ -w /sys/devices/system/cpu/cpufreq/boost ]]; then
          echo "$val" > /sys/devices/system/cpu/cpufreq/boost || true
        fi
      }

      set_platform_profile() {
        local val="$1"
        if [[ -w /sys/firmware/acpi/platform_profile ]]; then
          echo "$val" > /sys/firmware/acpi/platform_profile || true
        fi
      }

      apply_eco() {
        set_platform_profile quiet
        set_governor powersave
        set_epp power
        set_boost 0
      }
      apply_balanced() {
        set_platform_profile balanced
        set_governor schedutil
        set_epp balance_performance
        set_boost 1
      }
      apply_performance() {
        set_platform_profile performance
        set_governor performance
        set_epp performance
        set_boost 1
      }

      return_to_auto() {
        rm -f "$STATE_FILE"
        tlp start >/dev/null || true
      }

      set_mode() {
        local mode="$1"
        case "$mode" in
          auto)        return_to_auto ;;
          eco)         apply_eco;         echo eco         > "$STATE_FILE" ;;
          balanced)    apply_balanced;    echo balanced    > "$STATE_FILE" ;;
          performance) apply_performance; echo performance > "$STATE_FILE" ;;
          *) echo "unknown mode: $mode" >&2; return 1 ;;
        esac
        # Nudge waybar to refresh the custom/powermode module immediately.
        pkill -RTMIN+8 waybar 2>/dev/null || true
      }

      cycle_to_next() {
        local cur next
        cur=$(read_state)
        case "$cur" in
          auto)        next=eco ;;
          eco)         next=balanced ;;
          balanced)    next=performance ;;
          performance) next=auto ;;
          *)           next=auto ;;
        esac
        set_mode "$next"
      }

      print_json() {
        local mode src label class tooltip
        mode=$(read_state)
        if ac_online; then src=AC; else src=BAT; fi
        case "$mode" in
          auto)        label=A; class=auto;        tooltip="powermode: auto ($src) — TLP managed" ;;
          eco)         label=E; class=eco;         tooltip="powermode: eco (manual override)" ;;
          balanced)    label=B; class=balanced;    tooltip="powermode: balanced (manual override)" ;;
          performance) label=P; class=performance; tooltip="powermode: performance (manual override)" ;;
          *)           label="?"; class=unknown;   tooltip="powermode: unknown state" ;;
        esac
        printf '{"text":"%s","tooltip":"%s","class":"%s","alt":"%s"}\n' \
          "$label" "$tooltip" "$class" "$mode"
      }

      cmd="''${1:-status}"
      case "$cmd" in
        --json|json)
          print_json
          ;;
        status)
          echo "powermode: $(read_state)"
          ;;
        cycle)
          if [[ $EUID -ne 0 ]]; then exec sudo -n "$0" cycle; fi
          cycle_to_next
          ;;
        auto|eco|balanced|performance)
          if [[ $EUID -ne 0 ]]; then exec sudo -n "$0" "$cmd"; fi
          set_mode "$cmd"
          ;;
        -h|--help|help)
          cat <<EOF
      Usage: powermode [COMMAND]

      Commands:
        auto         Return control to TLP's automatic AC/BAT switching (default on boot)
        eco          Force eco profile: quiet platform, powersave gov, EPP=power, boost off
        balanced     Force balanced profile: balanced platform, schedutil, EPP=balance_performance
        performance  Force performance profile: performance platform, gov+EPP=performance, boost on
        cycle        Cycle auto -> eco -> balanced -> performance -> auto
        status       Print current mode
        --json       Print waybar-format JSON (single line)
        --help       Show this help
      EOF
          ;;
        *)
          echo "Unknown command: $cmd (try --help)" >&2; exit 1
          ;;
      esac
    '';
  };

in
{
  options.CUSTOM.services.powermode = {
    enable = mkEnableOption "powermode override (manual eco/balanced/performance on top of TLP's auto switching)";
    user = mkOption {
      type = types.str;
      description = "Unprivileged user permitted to invoke powermode without a password.";
    };
    package = mkOption {
      type = types.package;
      default = powermode;
      readOnly = true;
      description = "The powermode script package (exposed so other modules can reference it).";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ powermode ];

    # State lives in tmpfs so reboots reset to "auto" — no boot-time leftover overrides.
    systemd.tmpfiles.rules = [
      "d /run/powermode 0755 root root -"
    ];

    security.sudo.extraRules = [
      {
        users = [ cfg.user ];
        commands = [
          {
            command = "${powermode}/bin/powermode";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };
}
