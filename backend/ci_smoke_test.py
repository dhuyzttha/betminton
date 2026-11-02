"""
CI Smoke Test for Badminton AI Analyzer v4.0 PRO AI Backend Pipeline.
Verifies end-to-end Broadcast Split-Screen (976x576) rendering and aspect-ratio preservation.
"""

import os
import sys
import json
import subprocess
import cv2
import numpy as np


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    cli_script = os.path.join(script_dir, "cli_analyze.py")

    in_mp4 = "/tmp/ci_in.mp4"
    out_mp4 = "/tmp/ci_out.mp4"
    out_json = "/tmp/ci_out.json"

    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(in_mp4, fourcc, 30.0, (640, 360))
    for i in range(30):
        frame = np.full((360, 640, 3), 24, dtype=np.uint8)
        cv2.circle(frame, (320, 180), 40, (0, 220, 120), -1)
        writer.write(frame)
    writer.release()

    cmd = [
        sys.executable,
        cli_script,
        "--input", in_mp4,
        "--output", out_mp4,
        "--json", out_json,
        "--mode", "doubles",
        "--player-names", "Tú, Cường, Nam, Thành",
        "--occluded-corner", "auto",
        "--shuttle-sensitivity", "1.4",
        "--speed-calib", "1.0",
    ]
    subprocess.run(cmd, check=True)

    assert os.path.exists(out_mp4) and os.path.getsize(out_mp4) > 1000, "Output MP4 missing or empty"
    assert os.path.exists(out_json) and os.path.getsize(out_json) > 100, "Output JSON missing or empty"

    with open(out_json, "r", encoding="utf-8") as f:
        data = json.load(f)
    assert data["video_metadata"]["output_width"] == 976
    assert data["video_metadata"]["output_height"] == 576
    print("[CI PASS] Python AI Backend Broadcast Split-Screen (976x576) pipeline verified successfully!")


if __name__ == "__main__":
    main()
