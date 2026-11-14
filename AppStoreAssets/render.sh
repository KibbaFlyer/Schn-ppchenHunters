#!/bin/zsh
# Renders App Store images from source/store.html with headless Chrome.
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SRC="file://$PWD/source/store.html"
render() { # name query width height
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
    --force-device-scale-factor=1 --virtual-time-budget=4000 \
    --window-size="$3,$4" --screenshot="$PWD/$1" "$SRC?s=$2" 2>/dev/null
}
render header-1920x1080.png header 1920 1080
render search-1-organize-1320x2868.png 1 1320 2868
render search-2-languages-1320x2868.png 2 1320 2868
render search-3-aisles-1320x2868.png 3 1320 2868
