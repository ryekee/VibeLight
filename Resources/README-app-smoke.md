# VibeLight.app — end-to-end smoke

After running `./scripts/bundle.sh`:

## 1. Launch

    open build/VibeLight.app

Expected: colored circle in menubar, no Dock icon, no warning dialog.

## 2. Check the menu

Click the circle. Should show:
- Status row (Idle / Working / …) and session count
- Sessions submenu
- Pause submenu (30 min / 1 hr / Until tomorrow)
- Test light effect submenu (7 states)
- Show Sessions Window…
- Settings… (placeholder)
- Quit VibeLight

## 3. Simulate hook events

```bash
echo '{"session_id":"smoke1"}' | curl -s -X POST \
  -H 'Content-Type: application/json' --data-binary @- \
  'http://127.0.0.1:17345/event?hook=UserPromptSubmit'
```

Expected: icon turns blue (working) within 1 second.

```bash
echo '{"session_id":"smoke1","message":"Claude needs your permission"}' | curl -s -X POST \
  -H 'Content-Type: application/json' --data-binary @- \
  'http://127.0.0.1:17345/event?hook=Notification'
```

Expected: icon turns red (needsAuth).

```bash
echo '{"session_id":"smoke1"}' | curl -s -X POST \
  -H 'Content-Type: application/json' --data-binary @- \
  'http://127.0.0.1:17345/event?hook=Stop'
```

Expected: icon turns purple (done → idle).

## 4. Sessions window

Click "Show Sessions Window…". Open a second session via:

```bash
echo '{"session_id":"smoke2","cwd":"/Users/me/projB"}' | curl -s -X POST \
  -H 'Content-Type: application/json' --data-binary @- \
  'http://127.0.0.1:17345/event?hook=UserPromptSubmit'
```

Expected: table updates within 1 second to show 2 rows.

## 5. Pause

Click Pause → "Pause for 30 minutes". The menu now shows "Paused until …" and a Resume button. Push a hook event — icon should still update (state tracking continues) but the HA light will NOT be called.

Click Resume; the next event resumes driving HA.

## 6. Test light effect

If you have a real HA-connected light, click Test light effect → Working. The light should turn blue and start breathing. Click another state to switch.

If you don't have HA, this is silent. Tests run in `swift test`.

## 7. Quit

Click Quit VibeLight. Process exits cleanly within 1 second. Verify:

    pgrep -f VibeLight   # should print nothing
