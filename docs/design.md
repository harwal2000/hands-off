# Hands Off — design

## Why

Coding agents that test Mac apps open windows on your screen and take the keyboard. The moment that
started this: an agent kept pulling keyboard focus away while its user was typing a prompt to another
agent; the user grabbed focus back, so the agent's screenshots captured the user's windows instead of
the app. *"If I'd known to let it do its thing for a bit, I would have let go."*

So two things:

1. **Out of sight:** agents put their test windows on a virtual display nobody looks at.
2. **Turn-taking for the keyboard:** an agent that needs focus asks for it, waits until you pause,
   and the menu bar says clearly when to keep your hands off. If you touch the keyboard anyway, the
   agent is told its result can't be trusted.

Built to be shared: nothing in it knows about any particular app or agent.

## Goals

- A virtual display that exists while the app runs, placed where the pointer won't wander onto it.
- One command agents wrap around anything that needs keyboard focus.
- A menu bar item that shows, at a glance: nothing to worry about / an agent wants the keyboard /
  hands off (with what it's doing and for how long) / you've told agents to hold on.
- A "Hold on, I'm typing" button that makes waiting agents wait.

## Non-goals

- Isolating focus completely (that needs a VM; macOS has one keyboard focus per login session).
- Driving the app under test. Each app (or agent) puts its own windows on the virtual display, using
  the frame `handsoff display` prints.
- Viewing the virtual display's contents (a "peek" window needs Screen Recording; later, maybe).

## Anti-goals

- Taking the keyboard while you're typing.
- Leaving the display arrangement changed after it quits.
- Extra dependencies, a background daemon beyond the menu bar app, or setup beyond one install script.

## How it works

One executable inside `Hands Off.app`. Launched normally it is the menu bar app (no Dock icon);
with a subcommand (`handsoff …`, a symlink in `~/.local/bin`) it is the command-line tool.

They share state through files in `~/Library/Application Support/Hands Off/`
(`HANDSOFF_STATE_DIR` overrides it, for tests):

| File | Written by | Meaning |
|---|---|---|
| `display.json` | app | the virtual display's ID and frame (CoreGraphics and AppKit coordinates) |
| `keyboard.lock` | CLI | the agent holding the keyboard: reason, label, pid, start |
| `waiting/<pid>.json` | CLI | agents queued for the keyboard |
| `hold.json` | app or CLI | you said "hold on" (or Not now); holds the time it ends |
| `prompt.json` | CLI | the agent the menu bar is asking about, and when its countdown ends (one at a time, a lock like `keyboard.lock`) |
| `start-<pid>` | app | you clicked Start on that agent's prompt |
| `settings.json` | app or CLI | `confirm`: ask before each hold (on unless turned off) |
| `app.json` | app | the menu bar app's pid, so the CLI only asks while something can show the prompt |

The app polls the folder twice a second; the CLI needs no app to work (but launches it if installed, so
the menu bar shows what's happening).

### Virtual display

Private `CGVirtualDisplay` API (as DeskPad and BetterDisplay use; checked on macOS 27.0.1). Same point size
and scale as the main display, so apps lay out as they would there. Moved diagonally off the main
display's bottom-right corner with a configuration that's undone when the app quits (touches only at a
point, so the pointer doesn't drift onto it). Menu: turn it off and on.

### `handsoff focus [--reason …] [--seconds N] [--idle S] [--wait W] [--allow-input] -- command …`

1. Joins the queue. Menu bar: amber, "Agent needs keyboard".
2. Waits until you're not holding agents, nobody else holds the keyboard, and you haven't pressed a key
   or clicked for `S` seconds (default 5). Mouse *movement* doesn't count; it doesn't move focus. Only
   real hardware input counts (`CGEventSource` HID state), so the agent's own synthetic events don't.
3. Asks, unless you turned it off (menu, or `handsoff config confirm off`) or the app isn't running: takes the
   prompt lock and the menu bar shows a non-activating panel (who, why, the estimate, a 10 s countdown, **Start** and
   **Not now**, and how many others wait). **Start** goes now; the countdown ending goes too. A key press or click
   *restarts* the countdown, rather than pausing it, so a hold never starts within 10 s of your last input, however
   long you typed. **Not now** is a 2-minute hold: everyone waits, then an agent asks again; the command never fails
   because of it (only `W` ends the wait).
4. Takes the lock (a hard link to a fully written file, so it appears atomically with its contents). Menu bar: red,
   "Hands off" with a countdown (`--seconds`; `+m:ss` once it runs over) or the elapsed time.
5. Runs the command, then releases. A holder whose process died is ignored.
6. Exit code is the command's, except **75** when you pressed a key or clicked during the hold ("results may
   be wrong, run it again") or when waiting gave up after `W` seconds (default 30 min).

Multi-step work goes in one wrapped shell: `handsoff focus -- sh -c '…'`.

### Other commands

- `handsoff display` — the display's frame as JSON (launches the app and waits for it if needed).
- `handsoff screenshot <file.png>` — captures only the virtual display, never your screens.
- `handsoff status` — what the menu bar shows, as text.
- `handsoff hold [minutes]` / `handsoff resume` — same as the menu's buttons.

## Builder's calls (not decided with the user)

- Asking before each hold (the user's call); restarting the countdown on input, Not now = 2 minutes on hold, and
  one prompt at a time (builder's calls).
- The name, the 5 s idle default, exit code 75 (`EX_TEMPFAIL`), the amber/red colours.
- Swift package, AppKit `NSStatusItem` (coloured text), Swift Testing, macOS 14+.
- Shared via its git repo: clone, `scripts/install.sh` (builds, ad-hoc signs, copies to `~/Applications`,
  links the command). Signed, notarized downloads can come later.
