---
name: setup
description: Use when the user asks to install, set up, repair, update or check the desktop-control tools (agent-desktop, Orca) on a Windows machine, or when agent-desktop or the Orca CLI turns out to be missing while driving a desktop app.
---

# Setting up desktop control (Windows)

One script does the checking and the installing:
`${CLAUDE_PLUGIN_ROOT}/scripts/setup.ps1`
(if that variable is not expanded, it is `scripts/setup.ps1` two folders above this skill's directory).

## Steps

1. **Check first. This changes nothing:**
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "<script>" -Check
   ```
2. **Tell the user what is missing and what installing does**, then get a yes unless
   this request already asked for the install:
   - `npm install -g agent-desktop` (needs Node.js; the script does not install Node)
   - downloads Orca's Windows installer (~215 MB) from its GitHub releases, checks that its
     code signature is valid and signed by SignPath Foundation, runs it silently (per-user)
   - starts the Orca app and waits for its runtime
   - `orca skills install --skill orca-cli --skill orchestration` (into `~/.agents/skills`,
     linked into `~/.claude/skills`)
   - adds `%LOCALAPPDATA%\Programs\orca\resources\bin` to the user PATH
3. **Install:** the same command without `-Check`. Run it in the background with a long
   timeout (the download and the signature check can take 10+ minutes).
   `-SkipOrca` installs agent-desktop only.
4. **Run `-Check` again** and show the table.
5. **Relay every `NEEDS YOU` line.** Sign-ins are the user's: never log in for them.

## Reading the result

| State | Meaning |
|---|---|
| `OK` | present and working |
| `MISS` | not installed; the install run fixes it |
| `WARN` | works, something optional is absent |
| `FAIL` | the script could not fix it; the line says why |

## Notes

- New terminals and a restarted Claude app see the new PATH; running ones do not.
- On its first start Orca adds its own status hooks to `~/.claude/settings.json` and may
  set its theme. `orca agent hooks off` removes the hooks.
- Orca's settings page keeps saying its Computer Use skill is "not installed". That is
  intended: do not install `orca-computer-use`, it competes with `driving-desktop-apps`.
- Agents that Orca launches run in bypass-permissions mode unless the user changes that
  in Orca's agent settings. Mention it once.
- `Access is denied (os error 5)` from `agent-desktop snapshot` is a known upstream bug on
  some Windows 11 builds (vercel-labs/agent-desktop issue 677); Orca still works there.
