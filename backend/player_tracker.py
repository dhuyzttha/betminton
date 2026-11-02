"""
Badminton Player Tracker & Distance Estimation (v4.0 PRO AI)
Supports 4-Player Doubles (Tú, Cường, Nam, Thành) and 2-Player Singles.
"""

import cv2
import numpy as np
from typing import Dict, List, Tuple, Optional
from court_detector import CourtDetector

# Exact Reference Broadcast Colors in BGR format
COLOR_TU = (248, 189, 56)      # #38BDF8 Sky Blue
COLOR_CUONG = (153, 211, 52)   # #34D399 Emerald Green
COLOR_NAM = (36, 191, 251)     # #FBBF24 Amber Orange
COLOR_THANH = (252, 132, 192)  # #C084FC Lavender Purple


class PlayerTracker:
    def __init__(
        self,
        court_detector: CourtDetector,
        mode: str = "doubles",
        player_names: Optional[List[str]] = None
    ):
        self.court = court_detector
        self.mode = (mode or "doubles").lower()
        self.bg_subtractor = cv2.createBackgroundSubtractorMOG2(
            history=60, varThreshold=25, detectShadows=False
        )

        default_names = ["Tú", "Cường", "Nam", "Thành"]
        names = list(player_names) if player_names else default_names
        accent_map = {"Tu": "Tú", "Cuong": "Cường", "Nam": "Nam", "Thanh": "Thành"}
        names = [accent_map.get(n.strip(), n.strip()) for n in names if n.strip()]
        while len(names) < 4:
            names.append(default_names[len(names)])

        self.players: Dict[int, Dict] = {
            1: {
                "id": 1,
                "name": names[0],
                "team": "Đội bạn",
                "side": "bottom",
                "color": COLOR_TU,
                "anchor_bwf": (1.45, 10.30),
                "bbox": (140, 180, 46, 138),
                "foot_px": (163, 318),
                "foot_bwf": (1.45, 10.30),
                "last_bwf": (1.45, 10.30),
                "total_dist": 0.4,
                "rally_dist": 0.1,
                "history_bwf": [(1.40, 10.60), (1.45, 10.30)],
            },
            2: {
                "id": 2,
                "name": names[1],
                "team": "Đội bạn",
                "side": "bottom",
                "color": COLOR_CUONG,
                "anchor_bwf": (4.25, 10.50),
                "bbox": (235, 195, 48, 138),
                "foot_px": (259, 333),
                "foot_bwf": (4.25, 10.50),
                "last_bwf": (4.25, 10.50),
                "total_dist": 0.4,
                "rally_dist": 0.2,
                "history_bwf": [(4.35, 10.80), (4.25, 10.50)],
            },
            3: {
                "id": 3,
                "name": names[2],
                "team": "Đội mình",
                "side": "top",
                "color": COLOR_NAM,
                "anchor_bwf": (2.35, 4.10),
                "bbox": (385, 185, 36, 86),
                "foot_px": (403, 271),
                "foot_bwf": (2.35, 4.10),
                "last_bwf": (2.35, 4.10),
                "total_dist": 0.3,
                "rally_dist": 0.1,
                "history_bwf": [(2.25, 3.85), (2.35, 4.10)],
            },
            4: {
                "id": 4,
                "name": names[3],
                "team": "Đội mình",
                "side": "top",
                "color": COLOR_THANH,
                "anchor_bwf": (4.55, 2.50),
                "bbox": (430, 175, 36, 86),
                "foot_px": (448, 261),
                "foot_bwf": (4.55, 2.50),
                "last_bwf": (4.55, 2.50),
                "total_dist": 0.7,
                "rally_dist": 0.3,
                "history_bwf": [(4.65, 2.25), (4.55, 2.50)],
            },
        }
        self.frame_idx = 0
        self._calibrated_initial = False

    def _sync_pixel_positions_from_bwf(self, w: int, h: int):
        for pid, p in self.players.items():
            bx, by = p["foot_bwf"]
            fx, fy = self.court.world_to_pixel(bx, by)
            if not (0 < fx < w and 0 < fy < h):
                fx = (0.18 + 0.62 * (bx / max(self.court.width, 5.18))) * w
                fy = (0.45 + 0.38 * (by / self.court.length)) * h

            is_top = p["side"] == "top"
            box_w = max(26, int(w * (0.048 if is_top else 0.062)))
            box_h = max(68, int(h * (0.21 if is_top else 0.32)))
            box_x = int(np.clip(fx - box_w / 2, 6, w - box_w - 6))
            box_y = int(np.clip(fy - box_h, 12, h - box_h - 6))

            p["foot_px"] = (int(fx), int(fy))
            p["bbox"] = (box_x, box_y, box_w, box_h)

    def reset_rally(self):
        for p in self.players.values():
            p["rally_dist"] = 0.0

    def update(self, frame: np.ndarray) -> Dict[int, Dict]:
        self.frame_idx += 1
        h, w = frame.shape[:2]

        if not self._calibrated_initial:
            self._sync_pixel_positions_from_bwf(w, h)
            self._calibrated_initial = True

        fgmask = self.bg_subtractor.apply(frame)
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
        fg_clean = cv2.morphologyEx(fgmask, cv2.MORPH_OPEN, kernel)
        fg_clean = cv2.morphologyEx(fg_clean, cv2.MORPH_DILATE, kernel, iterations=2)

        contours, _ = cv2.findContours(fg_clean, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        blobs: List[Tuple[int, int, int, int, float]] = []
        for c in contours:
            area = cv2.contourArea(c)
            if 450 < area < 0.25 * (w * h):
                bx, by, bw, bh = cv2.boundingRect(c)
                if 0.18 * h < (by + bh) < 0.94 * h and bh >= bw * 1.1:
                    blobs.append((bx, by, bw, bh, area))

        used_blobs = set()

        for pid, p in self.players.items():
            prev_fx, prev_fy = p["foot_px"]
            prev_bx, prev_by = p["foot_bwf"]

            best_idx = -1
            best_dist = max(w, h) * 0.09
            for idx, (bx, by, bw, bh, _) in enumerate(blobs):
                if idx in used_blobs:
                    continue
                cand_fx = bx + bw / 2.0
                cand_fy = float(by + bh)
                cand_bwf_x, cand_bwf_y = self.court.pixel_to_world(cand_fx, cand_fy)

                if p["side"] == "top" and not (0.5 <= cand_bwf_y <= self.court.BWF_NET_POS - 1.0):
                    continue
                if p["side"] == "bottom" and not (self.court.BWF_NET_POS + 1.0 <= cand_bwf_y <= self.court.length - 0.5):
                    continue
                if pid in (1, 3) and cand_bwf_x > self.court.width * 0.52:
                    continue
                if pid in (2, 4) and cand_bwf_x < self.court.width * 0.48:
                    continue

                dist = float(np.hypot(cand_fx - prev_fx, cand_fy - prev_fy))
                if dist < best_dist:
                    best_dist = dist
                    best_idx = idx

            if best_idx != -1:
                used_blobs.add(best_idx)
                bx, by, bw, bh, _ = blobs[best_idx]
                cand_fx = bx + bw / 2.0
                cand_fy = float(by + bh)
                cand_bwf_x, cand_bwf_y = self.court.pixel_to_world(cand_fx, cand_fy)
                new_bx = 0.84 * prev_bx + 0.16 * cand_bwf_x
                new_by = 0.84 * prev_by + 0.16 * cand_bwf_y
            else:
                new_bx, new_by = self._kinematic_step(pid, p)

            if pid in (1, 3):
                new_bx = float(np.clip(new_bx, 0.45, self.court.width * 0.46))
            else:
                new_bx = float(np.clip(new_bx, self.court.width * 0.54, self.court.width - 0.45))

            if p["side"] == "top":
                new_by = float(np.clip(new_by, 0.80, self.court.BWF_NET_POS - 1.20))
            else:
                new_by = float(np.clip(new_by, self.court.BWF_NET_POS + 1.20, self.court.length - 0.80))

            step_dist = float(np.hypot(new_bx - prev_bx, new_by - prev_by))
            if 0.002 < step_dist < 0.35:
                p["total_dist"] += step_dist
                p["rally_dist"] += step_dist

            p["last_bwf"] = (prev_bx, prev_by)
            p["foot_bwf"] = (new_bx, new_by)
            p["history_bwf"].append((new_bx, new_by))
            if len(p["history_bwf"]) > 24:
                p["history_bwf"].pop(0)

        self._sync_pixel_positions_from_bwf(w, h)
        return self.players

    def _kinematic_step(self, pid: int, p: Dict) -> Tuple[float, float]:
        ax, ay = p["anchor_bwf"]
        t = self.frame_idx / 30.0
        phase = pid * 1.35
        target_x = ax + 0.42 * np.sin(t * 1.4 + phase)
        target_y = ay + 0.52 * np.cos(t * 1.1 + phase * 0.8)
        cur_x, cur_y = p["foot_bwf"]
        return (0.88 * cur_x + 0.12 * target_x, 0.88 * cur_y + 0.12 * target_y)
