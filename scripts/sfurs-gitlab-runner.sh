#!/usr/bin/env sh

docker run -d --name sfurs --restart always \
  -v "$XDG_RUNTIME_DIR/podman/podman.sock:/var/run/podman/podman.sock" \
  -v gitlab-runner-config:/etc/gitlab-runner \
  gitlab/gitlab-runner:latest
