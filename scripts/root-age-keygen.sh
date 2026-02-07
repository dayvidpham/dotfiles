#!/usr/bin/env sh

# 1. Create the directory
sudo mkdir -p /var/lib/sops-nix
sudo chmod 700 /var/lib/sops-nix

# 2. Generate a NEW unencrypted age identity (don't copy your personal key)
sudo age-keygen -o /var/lib/sops-nix/keys.txt
sudo chmod 400 /var/lib/sops-nix/keys.txt

# 3. Read the public key (you'll need it for .sops.yaml)
sudo age-keygen -y /var/lib/sops-nix/keys.txt
