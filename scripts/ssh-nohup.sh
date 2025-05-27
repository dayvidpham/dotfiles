#!/usr/bin/env sh

source ./lib.sh

SSH_IP_DEFAULT="${home_ip}"
SSH_USER_DEFAULT="minttea"
SSH_PORT_DEAFULT="${ssh_port}"

SSH_IP="${SSH_IP:SSH_IP_DEFAULT}"
SSH_USER="${SSH_USER:SSH_USER_DEFAULT}"
SSH_PORT="${SSH_PORT:SSH_PORT_DEFAULT}"

OUT_FILE="~/ssh-nohup.txt"

ssh -p "${SSH_PORT}" "${SSH_USER}@${SSH_IP}" $'nohup sh -c \' python3 src/study/run_tiktok_parallel.py \' > "${OUT_FILE}" 2>&1 &'
