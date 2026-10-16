#!/bin/zsh
# Re-creates the README's menu bar GIF and menu screenshot with the installed Hands Off.
# The menu bar runs through a staged demo (~15 s); the menu screenshot is taken inside `handsoff focus`, since an open
# menu takes the keyboard. Needs ffmpeg and Screen Recording permission for the terminal.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=build/readme-media; rm -rf $OUT; mkdir -p $OUT/frames $OUT/kept $OUT/cropped
swiftc -O scripts/readme-media/itemcrop.swift -o $OUT/itemcrop
swiftc -O scripts/readme-media/menuwin.swift -o $OUT/menuwin
STATE="$HOME/Library/Application Support/Hands Off"; ITEM="$STATE/menubar-item.txt"; mkdir -p "$STATE/waiting"
REGION_X=600   # capture from here to the right edge of the main display; the item is cropped out of it per frame

fake_waiter() {   # label reason → pid of a process standing in for a waiting agent
  sleep 120 & local pid=$!
  printf '{"label":"%s","pid":%s,"reason":"%s","since":"2026-01-01T00:00:00Z"}' "$1" $pid "$2" > "$STATE/waiting/$pid.json"
  echo $pid
}

# 1. Menu bar GIF: idle → an agent waits → it has the keyboard (countdown) → idle → "hold on" → idle.
handsoff focus --idle 0 --allow-input --reason warm-up -- true 2>/dev/null   # makes the app record its item position
( sleep 2; P=$(fake_waiter "my-app · editor-fix" "Typing test in the editor"); sleep 3; rm -f "$STATE/waiting/$P.json"; kill $P
  handsoff focus --idle 0 --allow-input --label "my-app · editor-fix" --reason "Typing test in the editor" --seconds 6 -- sleep 5.8 2>/dev/null
  sleep 1.5; handsoff hold 15 >/dev/null; sleep 3; handsoff resume >/dev/null; sleep 1.5; touch $OUT/done ) &
WIDTH=$(( $(system_profiler SPDisplaysDataType | awk '/UI Looks like/ {print $4; exit}') - REGION_X ))
i=0
while [[ ! -f $OUT/done ]]; do
  screencapture -x -R $REGION_X,0,$WIDTH,30 $OUT/frames/$(printf %04d $i).png
  echo "$(perl -MTime::HiRes=time -e 'printf "%.3f", time') $(cat "$ITEM")" >> $OUT/times.txt
  i=$((i+1))
done
wait
# The item's position arrives a frame or two after it changes: drop the frames around each change.
paste -d' ' <(ls $OUT/frames) $OUT/times.txt |
  awk '{line[NR]=$0; pos[NR]=$3" "$5} END{for(i=1;i<=NR;i++){ok=1; for(j=i-1;j<=i+2;j++) if(j>=1 && j<=NR && pos[j]!=pos[i]) ok=0; if(ok) print line[i]}}' > $OUT/kept.txt
while read -r name rest; do cp $OUT/frames/$name $OUT/kept/; done < $OUT/kept.txt
cut -d' ' -f2- $OUT/kept.txt > $OUT/kept-times.txt
$OUT/itemcrop $OUT/kept-times.txt $OUT/kept $OUT/cropped $REGION_X
paste -d' ' <(ls $OUT/cropped) $OUT/kept-times.txt |
  awk -v d=$OUT/cropped 'NR>1{printf "file '\''%s/%s'\''\nduration %.3f\n", d, prev, $2-pt} {prev=$1; pt=$2} END{printf "file '\''%s/%s'\''\nduration 1.0\nfile '\''%s/%s'\''\n", d, prev, d, prev}' > $OUT/concat.txt
ffmpeg -loglevel error -y -f concat -safe 0 -i $OUT/concat.txt \
  -vf "fps=10,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=none" -loop 0 docs/menubar.gif

# 2. The menu, open while an agent has the keyboard and another waits.
P=$(fake_waiter "my-app · settings-fix" "Screenshot of the Settings window")
until handsoff focus --label "my-app · editor-fix" --reason "Typing test in the editor" --seconds 40 -- sh -c "
  sleep 4; handsoff _open-menu 3; sleep 1.2
  screencapture -x -l \$($OUT/menuwin 'Hands Off') docs/menu.png; sleep 2.5"; do echo "interrupted, again"; done
kill $P; rm -f "$STATE/waiting/$P.json"
echo "docs/menubar.gif, docs/menu.png"
