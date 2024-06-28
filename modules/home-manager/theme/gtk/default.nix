{ config
, pkgs
, lib ? pkgs.lib
, ...
}:

{

  imports = [
    (lib.mkAliasOptionModule
      [ "CUSTOM" "theme" "pointerCursor" ]
      [ "home" "pointerCursor" ])
    (lib.mkAliasOptionModule
      [ "CUSTOM" "theme" "gtk" "font" ]
      [ "gtk" "font" ])
    (lib.mkAliasOptionModule
      [ "CUSTOM" "theme" "gtk" "theme" ]
      [ "gtk" "theme" ])
    (lib.mkAliasOptionModule
      [ "CUSTOM" "theme" "gtk" "iconTheme" ]
      [ "gtk" "iconTheme" ])
    (lib.mkAliasOptionModule
      [ "CUSTOM" "theme" "gtk" "enable" ]
      [ "gtk" "enable" ])
  ];

  options.CUSTOM.theme = { };

  config =
    let

      cfg = config.CUSTOM.theme;

      fonts = {
        noto-sans = {
          name = "Noto Sans";
          package = pkgs.noto-fonts;
          size = 12;
        };

        dejavu-sans = {
          name = "DejaVu Sans";
          package = pkgs.dejavu_fonts;
          size = 12;
        };
      };

      gtk.themes = {
        dracula = {
          name = "Dracula";
          package = pkgs.dracula-theme;
        };
      };

      gtkNonNull = (builtins.any (attr: attr != null) (
        lib.concatLists [
          (lib.attrsets.attrVals [ "theme" "iconTheme" "font" "pointerCursor" ] cfg.gtk)
          (lib.attrsets.attrVals [ "pointerCursor" ] cfg)
        ]
      ));

    in
    lib.mkIf cfg.enable {

      CUSTOM.theme = {

        pointerCursor = lib.mkDefault {
          gtk.enable = true;
          name = "Bibata-Modern-Classic";
          size = 24;
          package = pkgs.bibata-cursors;
        };

        gtk = lib.mkDefault {
          enable = if gtkNonNull then true else false;

          font = lib.mkDefault fonts.dejavu-sans;
          theme = lib.mkDefault gtk.themes.dracula;
        };
      };
    };
}
