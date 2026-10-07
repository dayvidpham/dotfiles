# evbridge: bridge Linux evdev input devices into a wlroots Wayland compositor
# via wlr_virtual_pointer / virtual_keyboard. Upstream ships no nixpkgs package;
# this wraps the upstream prebuilt release binary (x86_64-linux-gnu).
#
# Used by CUSTOM.services.sunshine to get Sunshine's uinput devices into the
# headless sway session the same way wayvnc does — no libinput, no seat.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  libxkbcommon,
  libgcc,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "evbridge";
  version = "0.1.0";

  src = fetchurl {
    url = "https://github.com/atassis/evbridge/releases/download/v${finalAttrs.version}/evbridge-v${finalAttrs.version}-x86_64-linux-gnu.tar.gz";
    hash = "sha256-viy1rq+zAsbt73SkGTb4gnHARPExy6lJD9ONEHLK4to=";
  };

  # The tarball contains the binary at its top level.
  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ autoPatchelfHook ];
  # libxkbcommon + libgcc_s (libwayland-client is vendored).
  buildInputs = [ libxkbcommon libgcc ];

  installPhase = ''
    runHook preInstall
    install -Dm755 evbridge "$out/bin/evbridge"
    runHook postInstall
  '';

  meta = {
    description = "Bridge Linux evdev input devices into a wlroots Wayland compositor";
    homepage = "https://github.com/atassis/evbridge";
    license = with lib.licenses; [ mit asl20 ];
    mainProgram = "evbridge";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
