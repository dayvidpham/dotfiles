{
  config
  , pkgs
  , lib ? pkgs.lib
  , ...
}:

{

  imports = [
    (lib.mkAliasOptionModule 
      [ "CUSTOM" "themes" "pointerCursor" ]
      [ "home" "pointerCursor" ])
    (lib.mkAliasOptionModule 
      [ "CUSTOM" "themes" "gtk" "font" ]
      [ "gtk" "font" ])
    (lib.mkAliasOptionModule 
      [ "CUSTOM" "themes" "gtk" "theme" ]
      [ "gtk" "theme" ])
    (lib.mkAliasOptionModule 
      [ "CUSTOM" "themes" "gtk" "iconTheme" ]
      [ "gtk" "iconTheme" ])
    (lib.mkAliasOptionModule 
      [ "CUSTOM" "themes" "gtk" "enable" ]
      [ "gtk" "enable" ] )
  ];

  options.CUSTOM.themes = {

    enable = lib.mkEnableOption "default cursor theme and GTK colours";

    #pointerCursor = lib.mkOption {
    #  description = "alias for home.pointerCursor";
    #  type = lib.types.submodule {};
    #};

    #gtk = lib.mkOption {
    #  description = "alias for gtk";
    #  type = lib.types.submodule {};
    #};
  };

  config = let

    cfg = config.CUSTOM.themes;

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

  in lib.mkIf cfg.enable {

    CUSTOM.themes = {

      pointerCursor = lib.mkDefault {
        gtk.enable = true;
        name = "Bibata-Modern-Classic";
        size = 24;
        package = pkgs.bibata-cursors;
      };

      gtk = lib.mkDefault rec {
        enable = if gtkNonNull then true else false;

        font = lib.mkDefault fonts.dejavu-sans;
        theme = lib.mkDefault gtk.themes.dracula;
      };
    };
  };
}
