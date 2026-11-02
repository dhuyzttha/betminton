"""
Badminton Hawk-Eye CLI Video Processor (v4.0 PRO AI)
Supports all CLI parameters from the UI:
--mode, --player-names, --occluded-corner, --shuttle-sensitivity, --speed-calib, --calibrate, --json
"""

import os
import sys
import shutil
import subprocess
import argparse
import cv2
import json
import numpy as np
from typing import Optional, Dict, Any, List
from court_detector import CourtDetector
from player_tracker import PlayerTracker
from shuttlecock_tracker import ShuttlecockTracker
from virtual_referee import VirtualReferee
from video_renderer import VideoRenderer


class NumpyEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, (np.floating, np.float32, np.float64)):
            return float(obj)
        elif isinstance(obj, (np.integer, np.int32, np.int64)):
            return int(obj)
        elif isinstance(obj, np.ndarray):
            return obj.tolist()
        return super(NumpyEncoder, self).default(obj)


def process_video(
    input_path: str,
    output_path: str,
    mode: str = "doubles",
    max_frames: Optional[int] = None,
    sensitivity: float = 1.2,
    speed_calib: float = 1.0,
    occluded_corner: str = "none",
    player_names: Optional[List[str]] = None,
    player1: str = "Tú",
    player2: str = "Cường",
    player3: str = "Nam",
    player4: str = "Thành",
    manual_corners: Optional[List[List[float]]] = None,
    export_h264: bool = True,
    json_output_path: Optional[str] = None,
) -> Dict[str, Any]:
    if not os.path.exists(input_path):
        raise FileNotFoundError(f"Input video not found at {input_path}")

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)

    cap = cv2.VideoCapture(input_path)
    if not cap.isOpened():
        raise RuntimeError(f"Could not open video file: {input_path}")

    fps = cap.get(cv2.CAP_PROP_FPS)
    if not fps or fps <= 0 or np.isnan(fps):
        fps = 30.0
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT)) or 0
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

    print(f"Loaded input video: {width}x{height} @ {fps:.1f} FPS, Total Frames: {total_frames}")

    court = CourtDetector(mode=mode, occluded_corner=occluded_corner)
    sample_frame = None
    for _ in range(min(30, max(1, total_frames))):
        ret, frame = cap.read()
        if ret and frame is not None:
            sample_frame = frame

    if sample_frame is None:
        cap.release()
        raise RuntimeError("Error: Could not read video frames from input video.")

    if manual_corners and len(manual_corners) == 4:
        court_info = court.set_manual_corners(manual_corners)
    else:
        court_info = court.detect_court(sample_frame)

    cap.set(cv2.CAP_PROP_POS_FRAMES, 0)

    names = player_names if player_names else [player1, player2, player3, player4]
    player_tracker = PlayerTracker(court, mode=mode, player_names=names)
    shuttle_tracker = ShuttlecockTracker(
        court, fps=fps, sensitivity=sensitivity, speed_calib=speed_calib
    )
    referee = VirtualReferee(court, fps=fps)
    renderer = VideoRenderer(court)

    out_w, out_h = VideoRenderer.OUT_W, VideoRenderer.OUT_H
    raw_output_path = output_path + ".raw.mp4" if export_h264 and shutil.which("ffmpeg") else output_path
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    out = cv2.VideoWriter(raw_output_path, fourcc, fps, (out_w, out_h))

    frame_count = 0
    all_telemetry = []

    print("Beginning frame-by-frame Broadcast Split-Screen Computer Vision pipeline...")
    while cap.isOpened():
        ret, frame = cap.read()
        if not ret or frame is None:
            break

        frame_count += 1
        if max_frames and frame_count > max_frames:
            break

        players = player_tracker.update(frame)
        shuttle_data = shuttle_tracker.update(frame)
        referee_data = referee.update(shuttle_data, players)

        rendered_frame = renderer.render_frame(
            frame=frame,
            court_data=court_info,
            players=players,
            shuttle_data=shuttle_data,
            shuttle_trajectory=shuttle_tracker.trajectory,
            referee_data=referee_data
        )

        out.write(rendered_frame)

        all_telemetry.append({
            "frame": frame_count,
            "shuttle": shuttle_data,
            "referee": referee_data,
            "players": {
                pid: {
                    "name": p["name"],
                    "foot_bwf": p["foot_bwf"],
                    "total_dist": round(p["total_dist"], 2),
                    "rally_dist": round(p["rally_dist"], 2),
                }
                for pid, p in players.items()
            }
        })

    cap.release()
    out.release()

    if raw_output_path != output_path:
        try:
            cmd = [
                "ffmpeg", "-y",
                "-i", raw_output_path,
                "-i", input_path,
                "-map", "0:v:0",
                "-map", "1:a:0?",
                "-c:v", "libx264",
                "-pix_fmt", "yuv420p",
                "-preset", "fast",
                "-crf", "21",
                "-c:a", "aac",
                "-shortest",
                "-movflags", "+faststart",
                output_path
            ]
            subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            os.remove(raw_output_path)
        except Exception as e:
            print(f"FFmpeg H.264 remux fallback to mp4v: {e}")
            if os.path.exists(raw_output_path):
                shutil.move(raw_output_path, output_path)

    json_path = json_output_path or (os.path.splitext(output_path)[0] + "_telemetry.json")
    player_summaries = [
        {
            "id": pid,
            "name": p["name"],
            "distanceMeters": round(p["total_dist"], 2),
            "rallyDistanceMeters": round(p["rally_dist"], 2),
        }
        for pid, p in player_tracker.players.items()
    ]
    telemetry_payload = {
        "video_metadata": {
            "input_width": width,
            "input_height": height,
            "output_width": out_w,
            "output_height": out_h,
            "fps": round(float(fps), 2),
            "total_frames": frame_count,
            "output_path": os.path.abspath(output_path)
        },
        "court_metadata": court_info,
        "summary": {
            "matchMode": mode,
            "total_shots": referee.shot_count,
            "totalShots": referee.shot_count,
            "rally_duration_sec": round(frame_count / fps, 2),
            "rallyDurationSec": round(frame_count / fps, 2),
            "max_shuttle_speed_kmh": round(shuttle_tracker.max_speed_kmh, 1),
            "maxSpeedKmh": round(shuttle_tracker.max_speed_kmh, 1),
            "last_decision": referee.last_decision,
            "players": {p["name"]: round(p["total_dist"], 2) for p in player_tracker.players.values()},
            "playerSummaries": player_summaries,
        },
        "frames": all_telemetry
    }
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(telemetry_payload, f, indent=2, cls=NumpyEncoder)

    print(f"Analysis complete! Saved rendered video to {output_path}")
    return telemetry_payload


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Badminton AI Analyzer v4.0 PRO AI")
    parser.add_argument("--input", type=str, required=True, help="Path to input MP4 video")
    parser.add_argument("--output", type=str, required=True, help="Path to output rendered MP4 video")
    parser.add_argument("--json", "--output-json", dest="json_output", type=str, default=None, help="Optional JSON report path")
    parser.add_argument("--mode", type=str, default="doubles", choices=["singles", "doubles"])
    parser.add_argument("--player-names", type=str, default="Tú, Cường, Nam, Thành")
    parser.add_argument("--occluded-corner", type=str, default="none")
    parser.add_argument("--shuttle-sensitivity", "--sensitivity", dest="sensitivity", type=float, default=1.2)
    parser.add_argument("--speed-calib", type=float, default=1.0)
    parser.add_argument("--calibrate", action="store_true", help="Enable interactive/auto calibration")
    parser.add_argument("--max-frames", type=int, default=None)
    parser.add_argument("--player1", type=str, default="Tú")
    parser.add_argument("--player2", type=str, default="Cường")
    parser.add_argument("--player3", type=str, default="Nam")
    parser.add_argument("--player4", type=str, default="Thành")

    args = parser.parse_args()
    parsed_names = [n.strip() for n in args.player_names.split(",") if n.strip()] if args.player_names else None
    process_video(
        input_path=args.input,
        output_path=args.output,
        mode=args.mode,
        max_frames=args.max_frames,
        sensitivity=args.sensitivity,
        speed_calib=args.speed_calib,
        occluded_corner=args.occluded_corner,
        player_names=parsed_names,
        player1=args.player1,
        player2=args.player2,
        player3=args.player3,
        player4=args.player4,
        json_output_path=args.json_output,
    )
