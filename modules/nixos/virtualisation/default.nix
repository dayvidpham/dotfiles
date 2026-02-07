{ ... }:
{
  imports = [
    ./podman
    ./libvirtd
    ./llm-sandbox
    # Standalone modules — previously imported transitively by openclaw wrappers
    # Now imported directly since wrappers moved to nix-openclaw-vm flake
    ./keycloak
    ./openbao
  ];
}
