#!/bin/zsh
# Renders App Store images from source/store.html with headless Chrome at 2x.
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SRC="file://$PWD/source/store.html"
render() { # name query css-width css-height  (output is 2x)
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
    --force-device-scale-factor=2 --virtual-time-budget=4000 \
    --window-size="$3,$4" --screenshot="$PWD/$1" "$SRC?s=$2" 2>/dev/null
}
render header-3840x1646.png header 1920 823
render search-1-organize-3840x2560.png 1 1920 1280
render search-2-languages-3840x2560.png 2 1920 1280
render search-3-aisles-3840x2560.png 3 1920 1280
