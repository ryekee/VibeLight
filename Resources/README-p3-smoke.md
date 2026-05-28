# VibeLight P3 — end-to-end smoke

## 1. Reset and bundle

```bash
# Clear any existing P2 setup so onboarding fires fresh.
defaults delete com.vibelight.app 2>/dev/null
rm -f ~/.config/vibelight/config.json
security delete-generic-password -s com.vibelight.app -a haToken 2>/dev/null

# Build + bundle
./scripts/bundle.sh
```

## 2. Launch

```bash
open build/VibeLight.app
```

Expected: menubar icon appears (purple/Idle). The "Setup required" menu item should be visible; clicking "Continue setup…" opens the onboarding window.

## 3. Walk onboarding

- Welcome → Next
- HA Connection: paste URL + token, click Test, expect "✓ Connected", then Next
- Light selection: pick a `light.*` entity, Next
- Network confirm: click "Check now", expect "✓ Reachable", Next
- Hook install: click "Install hooks", expect "✓ Installed". Check `~/.claude/settings.json` includes vibelight entries
- Effect test: click each state button; watch the menubar icon + your HA light
- Done → Done

The Onboarding window closes; menubar should reflect Idle.

## 4. Verify settings persistence

Quit the app (menubar → Quit). Relaunch via `open build/VibeLight.app`. Onboarding should NOT appear — app should be ready immediately.

## 5. Open Settings

Menubar → Settings… Walk all 6 tabs:

- General: toggles for launch-at-login and notifications
- Home Assistant: re-test connection, refresh entity list, install/uninstall scene pack
- Colors: change Working to a different color; broker auto-rebuilds (saved on every change)
- Network: status shows "At home" or "Away"; click Check now
- Claude Code: status shows "Installed ✓"; can reinstall/uninstall
- Advanced: change broker port (won't take effect until restart), reset all (only if you want to redo onboarding)

## 6. Verify Scene pack mode (optional)

Settings → Home Assistant → click "Install scene pack". Expect "✓ Installed 7 scenes".
Switch radio to "Scene pack". The light effects now run via HA scenes; customizable in HA UI.

## 7. Verify Pause across state changes

Click Pause → 30 minutes. Push a hook event:

```bash
echo '{"session_id":"smoke","cwd":"/tmp"}' | curl -s -X POST \
  -H 'Content-Type: application/json' --data-binary @- \
  'http://127.0.0.1:17345/event?hook=UserPromptSubmit'
```

Menubar updates to Working but light stays put. Click Resume — light catches up.

## 8. Verify "away" behavior

Disconnect Wi-Fi (or set a wrong HA URL temporarily). Network tab should show "Away" within ~30 seconds. Hook events still received; menubar reflects them; broker won't try HA calls (since the broker actually does try and fail silently — visible in HA logs).

## 9. Quit

Menubar → Quit. Within 1 second the process exits.

```bash
pgrep -f VibeLight   # should print nothing
```
