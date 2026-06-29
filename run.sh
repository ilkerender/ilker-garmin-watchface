#!/usr/bin/env bash
set -e

SDK_DIR="$HOME/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.2.0-2026-06-09-92a1605b2"
KEY="$HOME/Desktop/developer_key"
JUNGLE="$HOME/garmin/venu3s-watchface/monkey.jungle"
OUT="$HOME/garmin/venu3s-watchface/bin/venu3swatchface.prg"
DEVICE="venu3s"

mkdir -p "$(dirname "$OUT")"

echo "── Building ──"
java -Xms1g -Dfile.encoding=UTF-8 -Dapple.awt.UIElement=true \
  -jar "$SDK_DIR/bin/monkeybrains.jar" \
  -o "$OUT" -f "$JUNGLE" -y "$KEY" -d "${DEVICE}_sim" -w -l 3
echo "── Build OK: $OUT ──"

echo "── Launching simulator ──"
"$SDK_DIR/bin/connectiq" &
sleep 2

echo "── Loading app into simulator ──"
"$SDK_DIR/bin/monkeydo" "$OUT" "$DEVICE"
