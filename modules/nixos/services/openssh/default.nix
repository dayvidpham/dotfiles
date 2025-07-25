{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.services.openssh;

  inherit (lib)
    mkIf
    mkEnableOption
    mkPackageOption
    ;
in
{
  options = {
    CUSTOM.services.openssh = {
      enable = mkEnableOption "openssh";
    };
  };

  config = mkIf cfg.enable {
    services.fail2ban.enable = true;
    services.fail2ban.bantime-increment.enable = true;

    services.openssh = {
      enable = true;
      ports = [ 8108 ];
      openFirewall = false;

      sftpFlags = [
        "-f AUTHPRIV"
        "-l INFO"
      ];

      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        AuthenticationMethods = "publickey";

        PermitRootLogin = "no";
        DenyUsers = [ "root" ];
        DenyGroups = [ "root" ];

        Ciphers = [
          "chacha20-poly1305@openssh.com"
          "aes256-gcm@openssh.com"
          "aes128-gcm@openssh.com"
        ];

        X11Forwarding = false;
      };
    };
  };
}
