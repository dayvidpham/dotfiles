#!/usr/bin/env sh

echo -n "<example AAA...===>" | base64 -d - | openssl dgst -binary -sha256 | base64
