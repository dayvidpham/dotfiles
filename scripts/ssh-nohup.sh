#!/usr/bin/env sh

. ./lib.sh

SSH_IP_DEFAULT="${home_ip}"
SSH_USER_DEFAULT="minttea"
SSH_PORT_DEFAULT="${ssh_port}"

SSH_IP="${SSH_IP:-$SSH_IP_DEFAULT}"
SSH_USER="${SSH_USER:-$SSH_USER_DEFAULT}"
SSH_PORT="${SSH_PORT:-$SSH_PORT_DEFAULT}"

OUT_FILE="~/ssh-nohup.txt"

SH_CMD_DEFAULT="$(printf "nohup sh -c ' python3 src/study/run_tiktok_parallel.py ' > %s 2>&1 &" "${OUT_FILE}")"
SH_CMD="${SH_CMD:-$SH_CMD_DEFAULT}"

printf "[INFO] Will attempt to run the command:\n\`\`\`\n%s\n\`\`\`\n\n" "${SH_CMD}"

ssh -p "${SSH_PORT}" "${SSH_USER}@${SSH_IP}" "${SH_CMD}"
