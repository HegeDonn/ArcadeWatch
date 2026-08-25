#!/bin/bash
# Build the vivoactive5 .prg and (try to) push it to the watch.
#
#   tools/deploy.sh
#
# Auto-copies if the watch mounts as a USB drive (/Volumes/GARMIN).
# Otherwise it just builds — drag bin/ArcadeWatch-vivoactive5.prg into
# GARMIN/APPS/ using Android File Transfer.
set -e
cd "$(dirname "$0")/.."

SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b/bin"
PRG="bin/ArcadeWatch-vivoactive5.prg"

echo "Building $PRG ..."
java -Xms1g -jar "$SDK/monkeybrains.jar" -o "$PRG" -f monkey.jungle \
    -y developer_key -d vivoactive5 -w
echo "Build OK ($(ls -la "$PRG" | awk '{print $5}') bytes)"

DEST=""
for v in /Volumes/GARMIN /Volumes/garmin; do
    [ -d "$v/GARMIN/APPS" ] && DEST="$v/GARMIN/APPS"
done

if [ -n "$DEST" ]; then
    cp "$PRG" "$DEST/"
    sync
    echo "Copied to $DEST — eject the GARMIN volume and unplug."
else
    echo
    echo "Watch not mounted as a USB drive."
    echo "Drag $PRG into GARMIN/APPS/ using Android File Transfer."
fi
