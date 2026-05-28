# VibeLight P4 — Settings refactor + cold-start smoke

## 1. Build

```bash
./scripts/bundle.sh
```

## 2. Open Settings

Launch the app, click menubar icon, click "Settings…".

Expected layout: sidebar on the left with three sections —

- (top, no header): **General**, **Integrations**, **Light Effects**, **Network**
- **Advanced**: **Scene Pack**, **Diagnostics**
- **VibeLight**: **About**

Each sidebar row has a small colored icon glyph. Click each one in turn:

| Destination | Should show |
|---|---|
| General | Two toggles in a grouped box: Launch at login (with warning if unsigned) + Notify on HA errors |
| Integrations | HA URL + Scan + Token + Test + Light entity + Refresh, then Claude Code hook status |
| Light Effects | Three grouped sections (Session, Interactions, System), 2–3 rows each, color/brightness/effect per row, Reset button |
| Network | Status row (At home / Away), optional Wi-Fi hint, Check button |
| Scene Pack | Two-bullet explainer, mode radio group, Install/Uninstall buttons |
| Diagnostics | Broker port + default pause field; Open logs folder; Reset all settings |
| About | Version, source link (disabled placeholder), license |

## 3. Try changing a color

Light Effects → click the color swatch next to "Working" → pick a different color. The menubar icon should NOT change yet (state is still idle), but pushing a fake event will use the new color:

```bash
echo '{"session_id":"x"}' | curl -s -X POST \
  -H 'Content-Type: application/json' --data-binary @- \
  'http://127.0.0.1:17345/event?hook=UserPromptSubmit'
```

Menubar icon → your new working color. (Settings auto-reload — no restart.)

## 4. Verify Launch-at-login behavior

General → toggle Launch at login on.

- For a **signed app** placed in /Applications: the toggle persists and a Login Item appears in System Settings → General → Login Items.
- For an **unsigned dev build** (our `./scripts/bundle.sh` output): the description text under the toggle will warn "Login Item registration not supported for this build." The toggle still flips the UserDefaults value; it just doesn't register the system item.

## 5. Verify cold-start transcript discovery

If you have any `*.jsonl` files under `~/.claude/projects/*/`, quitting and relaunching the app should auto-populate the Sessions submenu with those session ids (in state Idle). Check via:

```bash
ls ~/.claude/projects/*/*.jsonl 2>/dev/null | head -5
# Then:
curl -s http://127.0.0.1:17345/state | python3 -m json.tool
```

The `sessions` map should contain the recovered ids.

You should also see a line in stdout when the app launches:

```
VibeLight: recovered N historical Claude Code sessions
```

## 6. Quit

Menubar → Quit. Within ~1 second:

```bash
pgrep -f VibeLight   # should print nothing
```
