#!/usr/bin/env sh

SSH_DEST="desktop"
OUT_FILE="~/ssh-nohup.txt"

ssh "${SSH_DEST}" $'nohup sh -c \' sleep 10; echo "world"; \' > "${OUT_FILE}" 2>&1 &'
