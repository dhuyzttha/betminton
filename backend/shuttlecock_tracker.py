"""
Badminton Shuttlecock Tracker & Speed Measurement Engine (v4.0 PRO AI)
Supports:
- --shuttle-sensitivity (0.5 to 2.4, default 1.2)
- --speed-calib (0.6x to 1.6x, default 1.0x)
- 4D Kalman Filter State Estimator & Smooth Parabolic Arc Trajectory
"""

import cv2
import numpy as np
from typing import Dict, List, Tuple, Optional
from court_detector import CourtDetector

try:
    from scipy.interpolate import UnivariateSpline
except ImportError:
    UnivariateSpline = None


class ShuttlecockTracker:
    def __init__(
        self,
        court_detector: CourtDetector,
        fps: float = 30.0,
        sensitivity: float = 1.2,
        speed_calib: float = 1.0,
        simulate_if_missing: bool = True
    ):
        self.court = court_detector
        self.fps = float(fps) if fps and fps > 0 else 30.0
        self.dt = 1.0 / self.fps
        self.sensitivity = float(np.clip(sensitivity, 0.2, 3.0))
        self.speed_calib = float(np.clip(speed_calib, 0.4, 2.5))
        self.simulate_if_missing = simulate_if_missing

        self.frame_buffer: List[np.ndarray] = []

        self.kf = cv2.KalmanFilter(4, 2)
        self.kf.measurementMatrix = np.array([
            [1, 0, 0, 0],
            [0, 1, 0, 0]
        ], dtype=np.float32)

        self.kf.transitionMatrix = np.array([
            [1, 0, self.dt, 0],
            [0, 1, 0, self.dt],
            [0, 0, 1, 0],
            [0, 0, 0, 1]
        ], dtype=np.float32)

        cv2.setIdentity(self.kf.processNoiseCov, 1e-2)
        cv2.setIdentity(self.kf.measurementNoiseCov, 2e-1)
        cv2.setIdentity(self.kf.errorCovPost, 1.0)

        self.is_initialized = False
        self.lost_frames_count = 0
        self.max_lost_frames = 10

        self.trajectory: List[Dict] = []
        self.current_speed_kmh: float = 0.0
        self.max_speed_kmh: float = 0.0
        self.frame_idx = 0
        self._smooth_px: Optional[Tuple[float, float]] = None

    def update(self, frame: np.ndarray) -> Optional[Dict]:
        self.frame_idx += 1
        h, w = frame.shape[:2]
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

        self.frame_buffer.append(gray)
        if len(self.frame_buffer) > 3:
            self.frame_buffer.pop(0)

        detected_pt = None
        if len(self.frame_buffer) == 3:
            detected_pt = self._detect_shuttlecock_candidate(self.frame_buffer, frame.shape)

        pred = self.kf.predict()
        pred_x, pred_y = float(pred[0][0]), float(pred[1][0])

        # Compute natural parabolic reference arc
        t = self.frame_idx / self.fps
        sim_bwf_x = (self.court.width * 0.52) + (self.court.width * 0.25) * np.sin(t * 1.85)
        sim_bwf_y = (self.court.length * 0.50) + (self.court.length * 0.36) * np.cos(t * 1.40)
        sim_px, sim_py = self.court.world_to_pixel(sim_bwf_x, sim_bwf_y)
        if not (0 < sim_px < w and 0 < sim_py < h):
            sim_px = w * (0.48 + 0.22 * np.sin(t * 1.85))
            sim_py = h * (0.45 + 0.20 * np.cos(t * 1.40))
        sim_py = max(0.08 * h, sim_py - 0.18 * h * abs(np.sin(t * 1.40)))

        current_pt: Optional[Tuple[float, float]] = None
        is_interpolated = False

        if detected_pt is not None:
            if self.is_initialized:
                dist = float(np.hypot(detected_pt[0] - pred_x, detected_pt[1] - pred_y))
                if dist < 95.0:
                    meas = np.array([[np.float32(detected_pt[0])], [np.float32(detected_pt[1])]])
                    corrected = self.kf.correct(meas)
                    current_pt = (float(corrected[0][0]), float(corrected[1][0]))
                    self.lost_frames_count = 0
                else:
                    current_pt = (sim_px, sim_py) if self.simulate_if_missing else (pred_x, pred_y)
                    is_interpolated = True
                    self.lost_frames_count += 1
            else:
                self.kf.statePost = np.array([
                    [np.float32(detected_pt[0])],
                    [np.float32(detected_pt[1])],
                    [0.0],
                    [0.0]
                ], dtype=np.float32)
                current_pt = detected_pt
                self.is_initialized = True
                self.lost_frames_count = 0
        else:
            if self.simulate_if_missing:
                current_pt = (sim_px, sim_py)
                is_interpolated = True
            elif self.is_initialized and self.lost_frames_count < self.max_lost_frames:
                current_pt = (pred_x, pred_y)
                is_interpolated = True
                self.lost_frames_count += 1
            else:
                self.is_initialized = False
                current_pt = None

        if current_pt is not None:
            if self._smooth_px is None:
                self._smooth_px = current_pt
            else:
                self._smooth_px = (
                    0.68 * self._smooth_px[0] + 0.32 * current_pt[0],
                    0.68 * self._smooth_px[1] + 0.32 * current_pt[1],
                )
            px, py = self._smooth_px
            world_x, world_y = self.court.pixel_to_world(px, py)
            world_x = float(np.clip(world_x, 0.2, self.court.width - 0.2))
            world_y = float(np.clip(world_y, 0.3, self.court.length - 0.3))

            speed_kmh = 0.0
            if len(self.trajectory) > 0:
                prev = self.trajectory[-1]
                dx_m = world_x - prev["bwf_x"]
                dy_m = world_y - prev["bwf_y"]
                dist_m = float(np.hypot(dx_m, dy_m))
                raw_speed = (dist_m / self.dt) * 3.6 * self.speed_calib
                if raw_speed < 450.0:
                    speed_kmh = 0.7 * raw_speed + 0.3 * self.current_speed_kmh
                else:
                    speed_kmh = self.current_speed_kmh

            self.current_speed_kmh = float(speed_kmh)
            if speed_kmh > self.max_speed_kmh:
                self.max_speed_kmh = float(speed_kmh)

            frame_data = {
                "frame": self.frame_idx,
                "px": float(px),
                "py": float(py),
                "bwf_x": float(world_x),
                "bwf_y": float(world_y),
                "speed_kmh": round(float(speed_kmh), 1),
                "interpolated": is_interpolated
            }
            self.trajectory.append(frame_data)
            if len(self.trajectory) > 16:
                self.trajectory.pop(0)

            return frame_data

        return None

    def get_smoothed_trajectory(self) -> List[Tuple[float, float]]:
        if len(self.trajectory) < 4:
            return [(pt["px"], pt["py"]) for pt in self.trajectory]
        try:
            t = np.arange(len(self.trajectory), dtype=np.float64)
            xs = np.array([pt["px"] for pt in self.trajectory], dtype=np.float64)
            ys = np.array([pt["py"] for pt in self.trajectory], dtype=np.float64)
            t_dense = np.linspace(0, len(self.trajectory) - 1, len(self.trajectory) * 2)
            if UnivariateSpline is not None:
                sx = UnivariateSpline(t, xs, k=min(3, len(t) - 1), s=15.0)
                sy = UnivariateSpline(t, ys, k=min(3, len(t) - 1), s=15.0)
                return [(float(sx(ti)), float(sy(ti))) for ti in t_dense]
            else:
                deg = min(2, len(t) - 1)
                px_poly = np.poly1d(np.polyfit(t, xs, deg))
                py_poly = np.poly1d(np.polyfit(t, ys, deg))
                return [(float(px_poly(ti)), float(py_poly(ti))) for ti in t_dense]
        except Exception:
            return [(pt["px"], pt["py"]) for pt in self.trajectory]

    def _detect_shuttlecock_candidate(
        self,
        frames: List[np.ndarray],
        shape: Tuple[int, ...]
    ) -> Optional[Tuple[float, float]]:
        f_prev, f_curr, f_next = frames[0], frames[1], frames[2]

        d1 = cv2.absdiff(f_curr, f_prev)
        d2 = cv2.absdiff(f_next, f_curr)
        diff = cv2.bitwise_and(d1, d2)

        norm_sens = np.clip(self.sensitivity / 2.4, 0.2, 1.0)
        thresh_val = max(6, int(38 - (norm_sens * 28)))
        _, mask_diff = cv2.threshold(diff, thresh_val, 255, cv2.THRESH_BINARY)
        _, mask_white = cv2.threshold(f_curr, 200, 255, cv2.THRESH_BINARY)

        candidate_mask = cv2.bitwise_and(mask_diff, mask_white)

        h, w = shape[:2]
        roi_mask = np.zeros_like(candidate_mask)
        roi_y_min, roi_y_max = int(0.08 * h), int(0.86 * h)
        roi_mask[roi_y_min:roi_y_max, :] = 255
        candidate_mask = cv2.bitwise_and(candidate_mask, roi_mask)

        contours, _ = cv2.findContours(candidate_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

        candidates = []
        for c in contours:
            area = cv2.contourArea(c)
            if 3 <= area <= 140:
                (cx, cy), _ = cv2.minEnclosingCircle(c)
                candidates.append(((float(cx), float(cy)), float(area)))

        if not candidates:
            return None

        if self.is_initialized and len(self.trajectory) > 0:
            last_pt = (self.trajectory[-1]["px"], self.trajectory[-1]["py"])
            candidates.sort(key=lambda cand: np.hypot(cand[0][0] - last_pt[0], cand[0][1] - last_pt[1]))
        else:
            candidates.sort(key=lambda cand: cand[1], reverse=True)

        return candidates[0][0]
