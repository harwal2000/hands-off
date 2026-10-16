#!/bin/zsh
# Builds Hands Off, installs it to ~/Applications, links the `handsoff` command and starts it.
#
#   scripts/install.sh [--bin-dir DIR]   # default ~/.local/bin
#   scripts/install.sh --uninstall
set -euo pipefail
cd "$(dirname "$0")/.."
APP_DIR="$HOME/Applications"
BIN_DIR="$HOME/.local/bin"
UNINSTALL=0
while (( $# )); do
  case $1 in
    --bin-dir) BIN_DIR=$2; shift ;;
    --uninstall) UNINSTALL=1 ;;
    *) echo "usage: $0 [--bin-dir DIR] [--uninstall]" >&2; exit 2 ;;
  esac
  shift
done
APP="$APP_DIR/Hands Off.app"

if (( UNINSTALL )); then
  [[ -x "$APP/Contents/MacOS/HandsOff" ]] && "$APP/Contents/MacOS/HandsOff" quit-app
  rm -rf "$APP"
  [[ -L "$BIN_DIR/handsoff" ]] && rm "$BIN_DIR/handsoff"
  rm -rf "$HOME/Library/Application Support/Hands Off"
  echo "Removed Hands Off."
  exit 0
fi

scripts/build-app.sh >/dev/null
"build/Hands Off.app/Contents/MacOS/HandsOff" quit-app   # whichever copy is running
mkdir -p "$APP_DIR" "$BIN_DIR"
rm -rf "$APP"
cp -R "build/Hands Off.app" "$APP"
ln -sf "$APP/Contents/MacOS/HandsOff" "$BIN_DIR/handsoff"
open -g "$APP"

echo "Installed $APP and $BIN_DIR/handsoff."
[[ ":$PATH:" == *":$BIN_DIR:"* ]] || echo "Note: $BIN_DIR isn't on your PATH; add it, or rerun with --bin-dir."
echo "To start it at login: its menu bar icon → Open at login."
