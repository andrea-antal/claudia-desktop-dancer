#!/bin/zsh
# Rebuilds Sprites/ from the BLISS film on claudia.gallery.
# Each line: name  start(s)  frames  crop x y w h  [frame to drop | frame:x,y,w,h box to erase ...]  (on the 1280×720 film)
set -e
cd "${0:A:h}/.."
mkdir -p .cache Sprites
film=.cache/bliss.mp4
[[ -f $film ]] || ffmpeg -nostdin -loglevel error -i https://claudia.gallery/films/bliss/hls/index.m3u8 -c copy $film
swiftc -O tools/matte.swift -o .cache/matte

while read name ss n x y w h drop; do
  [[ -z $name || $name == \#* ]] && continue
  tmp=$(mktemp -d)
  ffmpeg -nostdin -loglevel error -ss $ss -i $film -frames:v $n $tmp/%04d.png
  boxes=()
  for d in ${=drop}; do
    if [[ $d == *:* ]]; then boxes+=$d; else rm $tmp/$d.png; fi   # drop frames where UI fused with her
  done
  rm -rf Sprites/$name
  .cache/matte $tmp Sprites/$name $x $y $w $h $boxes
  rm -rf $tmp
done <<'EOF'
# ponytail: ranges and crop boxes picked by eye from contact sheets of every frame; widen a box if a limb gets clipped.
# Every box stops at row 679, the top of the XP taskbar she stands on.
dance   38.0   42     880 300 400 379  0009 0010 0020 0021 0022 0023 0024 0025 0026 0027 0028
hoop    10.25  14     380 180 540 499  0011
kick    39.75  18     680 40  600 639
fight   23.125 9      520 60  760 619  0001 0002 0003 0004:0,150,50,110 0005:0,150,50,110
spin    28.667 10     280 20  760 659  0002 0003 0009
start   83.625 19     300 130 380 549
window  84.292 14     660 130 360 549
EOF
