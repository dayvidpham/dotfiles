{
  lib,
  buildGoModule,
}:

# Static, CGO-free binary: the diff runs inside an fzf preview and should be
# copyable to machines without a Nix store.
buildGoModule {
  pname = "tmux-env-diff";
  version = "0.1.0";

  src = ./.;
  vendorHash = null;
  env.CGO_ENABLED = 0;
  trimpath = true;
  ldflags = [ "-s" "-w" ];

  meta = with lib; {
    description = "Colourised environment diff for tmux display routing";
    mainProgram = "tmux-env-diff";
  };
}
