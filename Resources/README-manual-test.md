# Manual end-to-end smoke test

Prerequisites:
- `~/.config/vibelight/config.json` exists with valid HA URL, token, and `light.X` entity
- Home Assistant is reachable and the light entity responds

## 1. Start the broker

```bash
swift run vibelight-broker
```

Leave it running in one terminal.

## 2. Simulate a UserPromptSubmit (expect WORKING / breathing blue)

```bash
echo '{"session_id":"test1","cwd":"/tmp"}' | \
  curl -s -X POST -H 'Content-Type: application/json' \
       --data-binary @- \
       'http://127.0.0.1:17345/event?hook=UserPromptSubmit'
```

Light should turn blue and start breathing.

## 3. Simulate a Notification with permission (expect NEEDS_AUTH / solid red)

```bash
echo '{"session_id":"test1","message":"Claude needs your permission to use Bash"}' | \
  curl -s -X POST -H 'Content-Type: application/json' \
       --data-binary @- \
       'http://127.0.0.1:17345/event?hook=Notification'
```

Light should turn solid red.

## 4. Simulate Stop (expect DONE → IDLE)

```bash
echo '{"session_id":"test1"}' | \
  curl -s -X POST -H 'Content-Type: application/json' \
       --data-binary @- \
       'http://127.0.0.1:17345/event?hook=Stop'
```

Light should blink purple briefly, then settle to solid purple (IDLE).

## 5. Inspect state via /state

```bash
curl -s http://127.0.0.1:17345/state | python3 -m json.tool
```

## 6. Trigger any state directly via /test

```bash
curl -s -X POST 'http://127.0.0.1:17345/test?state=error'
```

## 7. Test ERROR auto-clear

```bash
curl -s -X POST 'http://127.0.0.1:17345/test?state=error'
sleep 6
```

Note: `/test` does NOT update session state, only renders the driver directly. To test the full auto-clear path, send a real `PostToolUse` with `is_error: true`:

```bash
echo '{"session_id":"test1","tool_response":{"is_error":true}}' | \
  curl -s -X POST -H 'Content-Type: application/json' \
       --data-binary @- \
       'http://127.0.0.1:17345/event?hook=PostToolUse'
sleep 6
curl -s http://127.0.0.1:17345/state | python3 -m json.tool
# Expect session state to be "idle"
```

## 8. Stop the broker

`Ctrl+C` in the broker terminal. Expect "vibelight-broker: stopped".
