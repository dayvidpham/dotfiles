#!/usr/bin/env bash

echo "sfurs-3" >/etc/hostname

apt update -y
apt install fail2ban
systemctl enable --now fail2ban

snap install tailscale
