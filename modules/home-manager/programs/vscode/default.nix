{ config
, pkgs
, lib ? config.lib
, ...
}:
let
  cfg = config.CUSTOM.programs.vscode;

  inherit (lib)
    mkIf
    mkOption
    mkDefault
    mkEnableOption
    ;

  deps-unity = (ps: with ps; [
    dotnet-sdk_8
    mono
    msbuild
    nuget
    # Add any extra binaries you want accessible to Rider here
  ]);

  pkg-vscode = pkgs.vscode.fhsWithPackages (ps: (
    (with ps; [
      zlib
      openssl.dev
      pkg-config
    ])
    ++ (deps-unity ps)
  ))
  ;

in
{
  options.CUSTOM.programs.vscode = {
    enable = mkEnableOption "VSCode editor";
  };

  config = mkIf cfg.enable {
    programs.vscode = {
      enable = true;
      package = pkg-vscode;
    };

    xdg.desktopEntries = {
      vscode = {
        name = "VSCode - URL Handler";
        genericName = "Text Editor";
        exec = "${pkg-vscode}/bin/code %U";
        icon = "vscode";
        type = "Application";
        noDisplay = false;
        terminal = false;
        startupNotify = true;
        categories = [ "Utility" "TextEditor" "Development" "IDE" ];
        mimeType = [
          "text/english"
          "text/plain"
          "text/x-makefile"
          "text/x-c++hdr"
          "text/x-c++src"
          "text/x-chdr"
          "text/x-cs"
          "text/x-csrc"
          "text/x-java"
          "text/x-moc"
          "text/x-pascal"
          "text/x-tcl"
          "text/x-tex"
          "application/x-shellscript"
          "text/x-c"
          "text/x-c++"
        ];
      };

      vscode-url-handler = {
        name = "VSCode - URL Handler";
        genericName = "Text Editor";
        exec = "${pkg-vscode}/bin/code --open-url %U";
        icon = "vscode";
        type = "Application";
        noDisplay = true;
        terminal = false;
        startupNotify = true;
        categories = [ "Utility" "TextEditor" "Development" "IDE" ];
        mimeType = [ "x-scheme-handler/vscode" ];
      };
    };

  };
}
