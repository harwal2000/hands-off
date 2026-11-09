# Devlog

Work log for whoever builds Hands Off, newest first. Release notes for people who use it are in [CHANGELOG.md](CHANGELOG.md).

## 10 November 2026, 01:56
- Started `DEVLOG.md` (entries below rebuilt from git history) and `CHANGELOG.md`.
- Design: noted a planned way to see what's on the virtual display. Apps sometimes open their windows there with no agent running, so they look broken; the user finds them with Raycast's "Move to Next Display". Two ideas: a picture-in-picture peek window (ScreenCaptureKit, never takes focus or clicks) and a stray-window alert with a "Bring it here" action. Not built yet.

## 9 November 2026, 19:32
- Fixed leftover requests getting stuck after a restart: a waiting file whose PID had been reused (by distnoted) kept the menu bar on "Agent needs keyboard". A file's owner now counts as live only if its process started before the file was written. Merged `fix/stale-pid-after-reboot`.
- README recording script: always removes its fake waiting agents (EXIT trap), and the fake's sleep no longer holds the caller's stdout.

## 27 October 2026, 00:38
- Ask before each hold (PR #1): a menu bar prompt with who, why, the estimate, a 10 s countdown, Start and Not now (a 2-minute hold). Input restarts the countdown. `handsoff config confirm on|off` and a menu switch turn it off; `handsoff status` shows the prompt. A late Start click never skips a later prompt. README and design updated with screenshots of the prompt.

## 17 October 2026, 03:11
- First version: design doc, shared state and keyboard turn-taking rules with tests, the menu bar app, the virtual display (private `CGVirtualDisplay`) and the `handsoff` command (`focus`, `display`, `screenshot`, `status`, `hold`, `resume`). Install script, licence, and a README for sharing with a GIF of the menu bar.
- `handsoff status` shows the holder's estimate and the menu bar's countdown.
