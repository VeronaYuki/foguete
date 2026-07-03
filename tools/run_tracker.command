#!/bin/bash
# Double-click this file to start the FOGUETE webcam tracker.
# macOS will ask to allow camera access for Terminal the first time —
# click "Allow", then launch the game and play Phase 3 with your face.
cd "$(dirname "$0")/.."
PY="$HOME/.local/share/foguete/venv/bin/python"
[ -x "$PY" ] || PY="python3"
echo "FOGUETE face tracker — keep this window open while you play."
echo "If macOS asks for camera permission, click Allow, then re-run this."
exec "$PY" tools/face_tracker.py
