# evbridge: bridge Linux evdev input devices into a wlroots Wayland compositor
# via wlr_virtual_pointer / virtual_keyboard. Not in nixpkgs; built from source
# with a few fixes (see patches).
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
  #
  # Scroll: Sunshine's libvirtualhid reports the real scroll distance in the
  # high-resolution codes (REL_WHEEL_HI_RES/REL_HWHEEL_HI_RES, 120 units per
  # detent) and emits the legacy REL_WHEEL only at whole detents, so evbridge read
  # almost nothing. Emit axis_source(WHEEL) + axis_discrete into the compositor,
  # which wlroots forwards and GTK apps (e.g. Firefox) require. See the patch.
  patches = [
    ./evbridge-rescan.patch
    ./evbridge-scroll.patch
  ];

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
