---
name: driving-desktop-apps
description: Use when a task needs to click, type into, fill, read, or check a window of a desktop app on this Windows machine (computer use, desktop control, GUI automation, "operate this app", 操作桌面應用程式, 電腦控制), before writing any UI Automation, Win32 or screenshot script of your own.
---

# Driving desktop apps (agent-desktop first, Orca second)

Two accessibility-tree tools drive desktop windows here. Use them instead of
hand-written UI Automation / Win32 / SendKeys scripts and instead of screenshot-and-click.
If `agent-desktop` is not found, or the Orca CLI path below does not exist, use the
`desktop-control:setup` skill first.

| | `agent-desktop` (default) | `orca computer` (fallback) |
|---|---|---|
| Run as | `agent-desktop <cmd>` (on PATH) | `& "$env:LOCALAPPDATA\Programs\orca\resources\bin\orca.exe" computer <cmd> --json` |
| Needs | nothing | the Orca app running (`orca status`; `orca open` takes about a minute) |
| Speed | ~0.3 s per call | ~1 s per call |
| One look at a window | large JSON: ~0.8k tokens small Win32 app, 3–5k Chromium / Electron / WinUI | compact text: ~1k tokens, plus a screenshot unless `--no-screenshot` |
| One action | ~130 tokens back | ~800 tokens back (includes the tree diff) |
| Windows input | background (semantic UIA) | pulls the window to the front |

## Default loop: agent-desktop

```powershell
agent-desktop list-windows                                   # get the window id (w-123456)
agent-desktop find --window-id w-123456 --name Submit --role button   # one control: ~100 tokens
agent-desktop snapshot --window-id w-123456 -i --compact     # whole window when you need the map
agent-desktop set-value '@s1abc:e1' 'text'                   # also: check, uncheck, click, select, expand
agent-desktop get '@s1abc:e1' --property value               # read back; also: is <ref> --property checked
```

- **Quote every ref in PowerShell** (`'@s1abc:e1'`); a bare `@` is the splatting operator.
- Prefer `find` over `snapshot` when you already know the control's name.
- Verify by reading state back. `ok:true` with `delivered_unverified` is not proof.
- `<command> --help` and `agent-desktop skills get platform` have the rest.

## Switch to Orca for a step when

- agent-desktop cannot find or act on a control after one fresh snapshot and retry.
- The window is Chromium / Electron / WinUI and you will look at it many times: Orca's
  tree is about a quarter of the tokens. Pass `--no-screenshot` unless you need pixels.
- You need pixels: custom-drawn content, canvas, or state that no tree exposes.

Orca basics: `get-app-state --app <sel>` prints numbered elements; act with
`click | set-value | perform-secondary-action --element-index <n>`. `<sel>` is `pid:N`, or
the window's name for Store/UWP apps (their pid is not found). Indexes and refs do not
carry over between the two tools: after switching, look again with the tool you act with.
`orca skills get orca-computer-use` prints its full guide (~7k tokens; load only if stuck).

## Known traps (measured on Windows 11 25H2, agent-desktop 1.3.1, Orca 1.4.259)

| Symptom | Fix |
|---|---|
| agent-desktop `click` on a WinUI navigation item (Calculator mode list, Settings sidebar) returns ok but nothing changes | `select '<ref>' '<item name>'` |
| `select '<listbox ref>' '<item>'` fails with ACTION_NOT_SUPPORTED | `select` the option's own ref instead of the list's |
| HTML `<select>`: `select` fails with ELEMENT_NOT_FOUND | `expand` the combobox, snapshot again, then `select` the option's own ref |
| Chromium / Electron tree looks empty or thin | snapshot again with `--timeout-ms 8000` |
| Tree stays thin even with a long timeout (Orca's own window does this) | neither tool can read that app; say so instead of guessing |
| agent-desktop `type`, `double-click`, `right-click` return POLICY_DENIED | they need `--headed` (real input, takes the foreground); try `set-value` first |
| Orca shows no options after expanding a dropdown | type the option text with `type-text`, then `press-key --key Return` |
| Orca error `background_unavailable` / asks for `--restore-window` | it would move the user's real pointer: ask the user first |
| Window minimized: every element is `offscreen` | `agent-desktop restore --app <image>` then snapshot again |

## Boundaries

- Target one window by id / pid. Other open windows are the user's private data: do not
  snapshot or screenshot them to "look around".
- Keyboard input goes to the foreground window. Never run two keyboard-driven tasks at once.
- Web pages you can open yourself belong in a browser tool, not here.
