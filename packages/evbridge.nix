# evbridge: bridge Linux evdev input devices into a wlroots Wayland compositor
# via wlr_virtual_pointer / virtual_keyboard. Not in nixpkgs; built from source
# with one fix (see postPatch).
#
# Used by CUSTOM.services.sunshine to get Sunshine's uinput devices into the
# headless sway session the same way wayvnc does — no libinput, no seat.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  wayland,
  libxkbcommon,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "evbridge";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "atassis";
    repo = "evbridge";
    rev = "v${finalAttrs.version}";
    hash = "sha256-/KAohWQQdjNkam9I9tgIOML0JR7oLWQuQydVwmT+Duo=";
  };

  cargoHash = "sha256-efssejC15YLp4ppGL7Ow2ffkhVvdbWgpIQ0q7UhZI7o=";

  # Re-scan the input dir on evbridge's periodic timer so devices that appear
  # after startup (Sunshine creates its virtual devices lazily) get bridged too.
  patches = [ ./evbridge-rescan.patch ];

  # Two fixes so the bridged pointer behaves like a normal mouse (and the user's
  # sway `input` config governs it, no override needed):
  #  - negate vertical: evdev REL_WHEEL (+1 = up) vs wl_pointer axis (+1 = down)
  #  - scale ~20x: evdev sends 1 per notch; wl_pointer wants ~a notch's worth.
  # Horizontal is already correct (both +1 = right).
  postPatch = ''
    substituteInPlace src/mouse.rs \
      --replace-fail 'vptr.axis(time_ms, Axis::VerticalScroll, self.scroll_vert);' \
                     'vptr.axis(time_ms, Axis::VerticalScroll, -self.scroll_vert * 20.0);'
  '';

  buildInputs = [ wayland libxkbcommon ];
  # The wayland/xkbcommon crates link the system libs directly.
  nativeBuildInputs = [ ];

  meta = {
    description = "Bridge Linux evdev input devices into a wlroots Wayland compositor";
    homepage = "https://github.com/atassis/evbridge";
    license = with lib.licenses; [ mit asl20 ];
    mainProgram = "evbridge";
    platforms = lib.platforms.linux;
  };
})
