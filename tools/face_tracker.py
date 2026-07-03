#!/usr/bin/env python3
"""FOGUETE face tracker — streams head position + smile to the game over UDP.

Phase 3 control: lean/move your head to steer the rocket, smile to boost.
Sends one JSON packet per camera frame to 127.0.0.1:46464:

    {"face": 1, "x": -0.31, "y": 0.12, "smile": 0}

x/y are -1..1 in mirror space (lean right -> x > 0, lean up -> y > 0),
measured in face-widths from the neutral position captured at startup.

The game (scripts/face_control.gd) launches this automatically when it can;
run it manually in a terminal to watch tracking status:

    ~/.local/share/foguete/venv/bin/python tools/face_tracker.py

Requires opencv-python 4.x (Haar cascades ship inside the package — no
model files are added to the repo).
"""
import argparse
import json
import socket
import sys
import time

import cv2

DETECT_W = 320          # detection runs on a downscaled frame for speed
PREVIEW_PORT = 46465    # JPEG preview frames stream to game HUD on this port
PREVIEW_QUALITY = 60
CALIB_FRAMES = 15       # frames averaged to find the neutral head position
SMILE_WINDOW = 6        # rolling frames of smile votes
SMILE_VOTES = 3         # votes needed inside the window to count as smiling
SMILE_NEIGHBORS = 12    # Haar minNeighbors — lower = more sensitive


def open_camera(index: int) -> cv2.VideoCapture:
    # Retry for a few seconds: on phase restarts the previous tracker may
    # still be releasing the device.
    deadline = time.monotonic() + 8.0
    while True:
        cap = cv2.VideoCapture(index)
        if cap.isOpened():
            cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
            cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
            return cap
        cap.release()
        if time.monotonic() > deadline:
            sys.exit(f"could not open camera {index}")
        time.sleep(0.5)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--camera", type=int, default=0)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=46464)
    args = ap.parse_args()

    face_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_frontalface_default.xml")
    smile_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_smile.xml")
    if face_cascade.empty() or smile_cascade.empty():
        sys.exit("could not load Haar cascades from the cv2 package")

    cap = open_camera(args.camera)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.connect((args.host, args.port))
    preview_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    # When spawned by the game (no TTY), quit once the game stops listening —
    # a closed UDP port on loopback surfaces as ECONNREFUSED on later sends.
    # The error clears the socket state, so with no listener sends *alternate*
    # ok/refused; only a long unbroken run of successes means a real listener.
    auto_exit = not sys.stdout.isatty()
    refused = 0
    ok_streak = 0

    baseline = None     # neutral head position (image coords)
    calib = []
    sx = sy = 0.0       # smoothed output offsets
    smile_hist = []
    misses = 0
    last_status = 0.0

    print(f"tracking camera {args.camera} -> udp://{args.host}:{args.port}   (Ctrl+C stops)")
    print("look at the screen while it calibrates your neutral position…")
    while True:
        ok, frame = cap.read()
        if not ok:
            misses += 1
            if misses > 40:
                sys.exit("camera stopped delivering frames")
            time.sleep(0.05)
            continue
        misses = 0

        frame = cv2.flip(frame, 1)  # mirror, so leaning right steers right
        scale = DETECT_W / frame.shape[1]
        small = cv2.resize(frame, (DETECT_W, int(frame.shape[0] * scale)))
        gray = cv2.equalizeHist(cv2.cvtColor(small, cv2.COLOR_BGR2GRAY))

        packet = {"face": 0, "x": 0.0, "y": 0.0, "smile": 0}
        face_box = None
        faces = face_cascade.detectMultiScale(gray, scaleFactor=1.15, minNeighbors=5, minSize=(48, 48))
        if len(faces):
            x, y, w, h = max(faces, key=lambda f: f[2] * f[3])
            face_box = (x, y, w, h)
            cx, cy = x + w / 2.0, y + h / 2.0
            if baseline is None:
                calib.append((cx, cy))
                if len(calib) >= CALIB_FRAMES:
                    baseline = (sum(c[0] for c in calib) / len(calib),
                                sum(c[1] for c in calib) / len(calib))
                    print("calibrated — this head position flies straight")
            if baseline is not None:
                # ~one face-width of head travel = full stick deflection
                ox = max(-1.0, min(1.0, (cx - baseline[0]) / (w * 0.9)))
                oy = max(-1.0, min(1.0, (baseline[1] - cy) / (h * 0.9)))
                sx += (ox - sx) * 0.35
                sy += (oy - sy) * 0.35

                # smile detection on the full-res mouth crop — the downscaled
                # detection frame is too small for the smile cascade
                fx, fy, fw, fh = (int(v / scale) for v in (x, y, w, h))
                mouth = cv2.cvtColor(frame[fy + fh // 2:fy + fh, fx:fx + fw],
                                     cv2.COLOR_BGR2GRAY)
                mouth = cv2.equalizeHist(mouth)
                smiles = smile_cascade.detectMultiScale(
                    mouth, scaleFactor=1.6, minNeighbors=SMILE_NEIGHBORS,
                    minSize=(int(fw * 0.3), int(fh * 0.12)))
                smile_hist.append(1 if len(smiles) else 0)
                del smile_hist[:-SMILE_WINDOW]
                packet = {"face": 1, "x": round(sx, 3), "y": round(sy, 3),
                          "smile": 1 if sum(smile_hist) >= SMILE_VOTES else 0}

        # preview frame for the in-game HUD: mirror view + tracking overlay
        if baseline is not None:
            bx, by = int(baseline[0]), int(baseline[1])
            cv2.line(small, (bx - 8, by), (bx + 8, by), (140, 140, 140), 1)
            cv2.line(small, (bx, by - 8), (bx, by + 8), (140, 140, 140), 1)
        if face_box is not None:
            x, y, w, h = face_box
            color = (80, 220, 80) if packet["smile"] else (220, 180, 60)
            cv2.rectangle(small, (x, y), (x + w, y + h), color, 2)
            cv2.circle(small, (x + w // 2, y + h // 2), 3, color, -1)
            if packet["smile"]:
                cv2.putText(small, "BOOST!", (x, y - 6),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.6, (80, 220, 80), 2)
        else:
            cv2.putText(small, "no face", (8, 20),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.55, (60, 60, 230), 2)
        ok_enc, jpg = cv2.imencode(".jpg", small, [cv2.IMWRITE_JPEG_QUALITY, PREVIEW_QUALITY])
        if ok_enc:
            try:
                preview_sock.sendto(jpg.tobytes(), (args.host, PREVIEW_PORT))
            except OSError:
                pass

        try:
            sock.send(json.dumps(packet).encode())
            ok_streak += 1
            if ok_streak >= 30:
                refused = 0
        except (ConnectionRefusedError, OSError):
            ok_streak = 0
            refused += 1
            if auto_exit and refused > 75:  # ~5 s without a listener
                sys.exit("game stopped listening — exiting")

        now = time.monotonic()
        if now - last_status > 0.5:
            last_status = now
            if packet["face"]:
                mood = "SMILING -> BOOST" if packet["smile"] else "neutral"
                print(f"\rhead x={packet['x']:+.2f} y={packet['y']:+.2f}   {mood}      ",
                      end="", flush=True)
            else:
                print("\rno face in view                                    ", end="", flush=True)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nstopped")
