#!/bin/zsh
# Captures the screenshots the store listing and objectgraph.com use, from the real app on
# real sample files (../../samples/public in the wrapper). Mac windows are captured with
# screencapture, iPhone and iPad with the simulator.
#
#   AppStore/shots.sh                # everything
#   AppStore/shots.sh mac            # one platform: mac | iphone | ipad
#   SCENES=02-heart-rate AppStore/shots.sh iphone
#   UI_LANG=de AppStore/shots.sh iphone   # the German app, into screenshots/de/
#
# Needs a Debug build of the Mac app and of the simulator app (xcodebuild, see CLAUDE.md);
# MAC_APP / SIM_APP override the DerivedData lookup. Writes AppStore/screenshots/<platform>/.
set -e
here=${0:A:h}
samples=$here/../../samples/public
out=$here/screenshots
bundle=com.objectgraph.GPXExplore

# The newest *binary* wins: an incremental build does not touch the .app directory's date
MAC_APP=${MAC_APP:-$(ls -t ~/Library/Developer/Xcode/DerivedData/GPXExplore-*/Build/Products/Debug/GPXExplore.app/Contents/MacOS/GPXExplore | head -1 | sed 's#/Contents/MacOS/GPXExplore$##')}
SIM_APP=${SIM_APP:-$(ls -t ~/Library/Developer/Xcode/DerivedData/GPXExplore-*/Build/Products/Debug-iphonesimulator/GPXExplore.app/GPXExplore | head -1 | xargs dirname)}
echo "mac: $MAC_APP"; echo "sim: $SIM_APP"
IPHONE=${IPHONE:-"iPhone 16 Pro Max"}
IPAD=${IPAD:-"iPad Pro 13-inch (M4)"}

# Every scene starts from the same settings: US units, standard map, effort colouring,
# both overlays on, elevation chart, drawer closed. Scenes override what they need.
# UI_LANG=de (fr, es, ja) captures the localised app into screenshots/<lang>/<platform>/;
# unset means English into screenshots/<platform>/. Locale and units follow the language.
lang=${UI_LANG:-en}
case $lang in
  en) locale=en_US; metric=NO ;;
  de) locale=de_DE; metric=YES ;;
  fr) locale=fr_FR; metric=YES ;;
  es) locale=es_ES; metric=YES ;;
  ja) locale=ja_JP; metric=YES ;;
  *)  locale=${lang}_${(U)lang}; metric=YES ;;
esac
[[ $lang == en ]] || out=$here/screenshots/$lang
base=(-AppleLanguages "($lang)" -AppleLocale $locale -useMetricSystem $metric -mapStyle Standard
      -elevationVisualizationMode Effort -trackLineWidth 5 -defaultShowElevationOverlay YES
      -defaultShowRouteInfoOverlay YES -chartMetric Elevation -showTracksDrawer NO)

# name | sample file | overrides
scenes=(
  "01-hero|blue_hills.gpx|"
  "02-heart-rate|run.gpx|-chartMetric 'Heart rate'"
  "03-satellite|Lannion_Plestin_parcours24.4RE.gpx|-mapStyle Satellite"
  "04-tracks|blue_hills.gpx|-showTracksDrawer YES"
  "05-gradient|mystic_basin_trail.gpx|-elevationVisualizationMode Gradient -mapStyle Hybrid"
  "06-speed|run.gpx|-chartMetric Speed"
)

wanted=${SCENES:-}
platforms=(${@:-mac iphone ipad})

# Splits a scene's override string into words, honouring quotes ('Heart rate')
scene_args() { local -a words; words=(${(Q)${(z)1}}); print -r -- "${(pj:\n:)words}"; }

capture_mac() {
  mkdir -p $out/mac
  local helper=$here/windowid
  [[ -x $helper && $helper -nt $here/windowid.swift ]] || swiftc -O $here/windowid.swift -o $helper
  for scene in $scenes; do
    local name=${scene%%|*}; local rest=${scene#*|}; local file=${rest%%|*}; local extra=${rest#*|}
    [[ -n $wanted && $wanted != *$name* ]] && continue
    pkill -x GPXExplore 2>/dev/null || true; sleep 1
    local -a args; args=($base "${(@f)$(scene_args "$extra")}")
    # A 1440×900 window (2880×1800 at 2×, an App Store Mac size) through the argument domain,
    # so the user's own saved frame is never touched
    open -a "$MAC_APP" "$samples/$file" --args $args "-NSWindow Frame GPXExploreDocumentWindow" "160 120 1440 900 0 0 2560 1440 "
    sleep 9
    local id=$($helper "GPX Explore")
    if [[ -z $id ]]; then echo "no window for $name"; continue; fi
    screencapture -l $id -o -x $out/mac/$name.png
    echo "mac/$name.png $(sips -g pixelWidth -g pixelHeight $out/mac/$name.png | awk '/pixel/{printf "%s ", $2}')"
  done
  pkill -x GPXExplore 2>/dev/null || true
}

capture_sim() {   # $1 = device name, $2 = output folder
  local udid=$(xcrun simctl list devices available | grep -F "$1 (" | head -1 | grep -o '[0-9A-F-]\{36\}')
  [[ -n $udid ]] || { echo "no simulator named $1"; return 1; }
  mkdir -p $out/$2
  xcrun simctl boot $udid 2>/dev/null || true
  xcrun simctl bootstatus $udid -b >/dev/null
  xcrun simctl install $udid $SIM_APP
  xcrun simctl ui $udid appearance dark   # dark, like the Mac captures: Gavi wants dark boards and site shots
  xcrun simctl status_bar $udid override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 --operatorName "" >/dev/null 2>&1 || true
  for scene in $scenes; do
    local name=${scene%%|*}; local rest=${scene#*|}; local file=${rest%%|*}; local extra=${rest#*|}
    [[ -n $wanted && $wanted != *$name* ]] && continue
    xcrun simctl terminate $udid $bundle 2>/dev/null || true
    local -a args; args=($base "${(@f)$(scene_args "$extra")}")
    xcrun simctl launch $udid $bundle -openFile "$samples/$file" $args >/dev/null
    sleep 11
    xcrun simctl io $udid screenshot $out/$2/$name.png >/dev/null
    echo "$2/$name.png $(sips -g pixelWidth -g pixelHeight $out/$2/$name.png | awk '/pixel/{printf "%s ", $2}')"
  done
  xcrun simctl terminate $udid $bundle 2>/dev/null || true
  xcrun simctl status_bar $udid clear >/dev/null 2>&1 || true
}

for p in $platforms; do
  case $p in
    mac) capture_mac ;;
    iphone) capture_sim "$IPHONE" iphone-6.9 ;;
    ipad) capture_sim "$IPAD" ipad-13 ;;
    *) echo "unknown platform $p"; exit 1 ;;
  esac
done
