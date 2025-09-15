#!/usr/bin/env bash

if [[ "$#" -lt 1 ]]; then
	echo "Please provide a hostname for the builder (e.g. sfurs-1)"
	echo "usage: setup-builder.sh {hostname}"
	exit
fi

HOSTNAME="$1"

cat "$HOSTNAME" >/etc/hostname

apt update -y
apt install fail2ban openssh-server -y
systemctl enable --now fail2ban

systemctl enable --now ssh
ssh-keygen -A
mkdir /etc/ssh/authorized_keys.d
wget -qO- https://github.com/dayvidpham.keys >>/etc/ssh/authorized_keys.d/builder
wget -qO- https://github.com/dayvidpham/dotfiles/scripts/sfurs/sshd_config >/etc/ssh/sshd_config

snap install tailscale
tailscale login --ssh=true --hostname="$HOSTNAME" --advertise-tags="tag:builder" --login-server="https://hs0.vpn.dhpham.com"
