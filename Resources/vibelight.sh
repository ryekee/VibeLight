#!/usr/bin/env bash
# vibelight: forward Claude Code hook payload to local broker.
# Argument $1 = hook name (e.g. PreToolUse). stdin = JSON payload.
# Fail silently — never block Claude Code.
exec curl -s -m 0.2 -X POST \
  -H 'Content-Type: application/json' \
  --data-binary @- \
  "http://127.0.0.1:17345/event?hook=$1" >/dev/null 2>&1 || true
