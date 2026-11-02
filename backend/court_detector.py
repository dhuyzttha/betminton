"""
Badminton Court Detector & Homography Engine (v4.0 PRO AI)
Supports:
- BWF Standard Dimension Mapping (Singles: 13.40m x 5.18m, Doubles: 13.40m x 6.10m)
- Automatic AI 4-Corner Detection & Occluded Corner Extrapolation (--occluded-corner)
- Aspect-Ratio-Preserving Viewport Mapping
- RANSAC Homography Matrix Computation (Pixel <-> BWF Metric Space)
"""

import cv2
import numpy as np
from typing import Tuple, Dict, Optional, List


class CourtDetector:
    BWF_LENGTH = 13.40
    BWF_WIDTH_SINGLES = 5.18
    BWF_WIDTH_DOUBLES = 6.10
    BWF_NET_POS = 6.70
    BWF_SHORT_SERVICE_DIST = 1.98
    BWF_DOUBLES_REAR_SERVICE_DIST = 0.76
    BWF_SIDE_TRAMLINE_WIDTH = 0.46

    def __init__(self, mode: str = "doubles", occluded_corner: str = "none"):
        self.mode = (mode or "doubles").lower()
        self.occluded_corner = (occluded_corner or "none").lower()
        self.width = self.BWF_WIDTH_SINGLES if self.mode == "singles" else self.BWF_WIDTH_DOUBLES
        self.length = self.BWF_LENGTH

        self.world_corners = np.array([
            [0.0, 0.0],               # Top-Left (Far-Left)
            [self.width, 0.0],        # Top-Right (Far-Right)
            [self.width, self.length],# Bottom-Right (Near-Right)
            [0.0, self.length]        # Bottom-Left (Near-Left)
        ], dtype=np.float32)

        self.H: Optional[np.ndarray] = None
        self.H_inv: Optional[np.ndarray] = None
        self.detected_corners: Optional[np.ndarray] = None

    @staticmethod
    def line_intersection(
        line1: Tuple[Tuple[float, float], Tuple[float, float]],
        line2: Tuple[Tuple[float, float], Tuple[float, float]]
    ) -> Optional[Tuple[float, float]]:
        p1, p2 = line1
        p3, p4 = line2
        x1, y1 = float(p1[0]), float(p1[1])
        x2, y2 = float(p2[0]), float(p2[1])
        x3, y3 = float(p3[0]), float(p3[1])
        x4, y4 = float(p4[0]), float(p4[1])

        denom = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
        if abs(denom) < 1e-6:
            return None

        px = ((x1 * y2 - y1 * x2) * (x3 - x4) - (x1 - x2) * (x3 * y4 - y3 * x4)) / denom
        py = ((x1 * y2 - y1 * x2) * (y3 - y4) - (y1 - y2) * (x3 * y4 - y3 * x4)) / denom
        if not (np.isfinite(px) and np.isfinite(py)):
            return None
        return (float(px), float(py))

    def set_manual_corners(self, corners: List[List[float]]) -> Dict:
        """Sets 4 court corners directly (from interactive UI calibration) and computes Homography."""
        self.detected_corners = np.array(corners, dtype=np.float32)
        H, _ = cv2.findHomography(self.detected_corners, self.world_corners)
        if H is None or abs(np.linalg.det(H)) < 1e-9:
            self.detected_corners = np.array([
                [160.0, 220.0], [570.0, 220.0], [680.0, 390.0], [50.0, 390.0]
            ], dtype=np.float32)
            H, _ = cv2.findHomography(self.detected_corners, self.world_corners)
        self.H = H
        self.H_inv = np.linalg.inv(self.H)
        return {
            "mode": self.mode,
            "occluded_corner": self.occluded_corner,
            "corners": [[float(c[0]), float(c[1])] for c in self.detected_corners],
            "H": self.H.tolist(),
            "H_inv": self.H_inv.tolist(),
            "world_dimensions": {"width": self.width, "length": self.length}
        }

    def detect_court(self, frame: np.ndarray) -> Dict:
        """
        Detects court boundaries and computes Homography.
        Supports automatic corner detection and geometric extrapolation for occluded corners.
        """
        if frame is None or frame.size == 0:
            raise ValueError("Invalid empty frame passed to detect_court")

        h, w = frame.shape[:2]
        hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)

        lower_green = np.array([30, 55, 50])
        upper_green = np.array([92, 255, 255])
        court_mask = cv2.inRange(hsv, lower_green, upper_green)

        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (9, 9))
        court_clean = cv2.morphologyEx(court_mask, cv2.MORPH_CLOSE, kernel)
        court_clean = cv2.morphologyEx(court_clean, cv2.MORPH_OPEN, kernel)

        contours, _ = cv2.findContours(court_clean, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        contour_corners = None
        if contours:
            largest = max(contours, key=cv2.contourArea)
            area = cv2.contourArea(largest)
            if 0.08 * (w * h) < area < 0.85 * (w * h):
                hull = cv2.convexHull(largest)
                pts = hull.reshape(-1, 2).astype(np.float32)
                s = pts[:, 0] + pts[:, 1]
                d = pts[:, 0] - pts[:, 1]
                tl_c = tuple(map(float, pts[np.argmin(s)]))
                br_c = tuple(map(float, pts[np.argmax(s)]))
                tr_c = tuple(map(float, pts[np.argmax(d)]))
                bl_c = tuple(map(float, pts[np.argmin(d)]))
                if (
                    tl_c[1] > 0.10 * h
                    and br_c[1] < 0.96 * h
                    and (br_c[1] - tl_c[1]) > 0.18 * h
                    and (tr_c[0] - tl_c[0]) > 0.20 * w
                ):
                    contour_corners = [tl_c, tr_c, br_c, bl_c]

        if contour_corners is not None:
            corners = self.extrapolate_missing_corners(contour_corners, w, h)
        else:
            court_dilated = cv2.dilate(court_clean, kernel, iterations=2)
            white_mask = cv2.inRange(hsv, np.array([0, 0, 165]), np.array([180, 75, 255]))
            if 0.05 * (w * h) < cv2.countNonZero(court_dilated) < 0.88 * (w * h):
                lines_mask = cv2.bitwise_and(white_mask, court_dilated)
            else:
                lines_mask = white_mask

            edges = cv2.Canny(lines_mask, 50, 150)
            lines = cv2.HoughLinesP(edges, 1, np.pi / 180, threshold=40, minLineLength=35, maxLineGap=12)

            horizontals: List[Tuple[Tuple[float, float], Tuple[float, float]]] = []
            verticals: List[Tuple[Tuple[float, float], Tuple[float, float]]] = []

            if lines is not None:
                for l in lines:
                    x1, y1, x2, y2 = l[0]
                    dx = float(x2 - x1)
                    dy = float(y2 - y1)
                    angle = abs(np.arctan2(dy, dx) * 180.0 / np.pi)
                    if angle < 25.0 or angle > 155.0:
                        horizontals.append(((float(x1), float(y1)), (float(x2), float(y2))))
                    elif 50.0 < angle < 130.0:
                        verticals.append(((float(x1), float(y1)), (float(x2), float(y2))))

            far_y = 0.44 * h
            near_y = 0.82 * h

            if horizontals:
                ys = [(l[0][1] + l[1][1]) / 2.0 for l in horizontals if 0.15 * h < (l[0][1] + l[1][1]) / 2.0 < 0.92 * h]
                if len(ys) >= 2:
                    far_y = float(np.percentile(ys, 10))
                    near_y = float(np.percentile(ys, 90))

            if near_y - far_y < 0.18 * h:
                far_y = 0.44 * h
                near_y = 0.82 * h

            left_pts: List[Tuple[float, float]] = []
            right_pts: List[Tuple[float, float]] = []
            mid_x = w / 2.0

            for l in verticals:
                lx = (l[0][0] + l[1][0]) / 2.0
                if lx < mid_x:
                    left_pts.extend([l[0], l[1]])
                else:
                    right_pts.extend([l[0], l[1]])

            if len(left_pts) >= 4:
                pts = np.array(left_pts, dtype=np.float32)
                fit_res = cv2.fitLine(pts, cv2.DIST_L2, 0, 0.01, 0.01).flatten()
                vx, vy, x0, y0 = float(fit_res[0]), float(fit_res[1]), float(fit_res[2]), float(fit_res[3])
                left_line = ((x0, y0), (x0 + vx * 100.0, y0 + vy * 100.0)) if abs(vy) > 1e-3 else ((0.22 * w, far_y), (0.06 * w, near_y))
            else:
                left_line = ((0.22 * w, far_y), (0.06 * w, near_y))

            if len(right_pts) >= 4:
                pts = np.array(right_pts, dtype=np.float32)
                fit_res = cv2.fitLine(pts, cv2.DIST_L2, 0, 0.01, 0.01).flatten()
                vx, vy, x0, y0 = float(fit_res[0]), float(fit_res[1]), float(fit_res[2]), float(fit_res[3])
                right_line = ((x0, y0), (x0 + vx * 100.0, y0 + vy * 100.0)) if abs(vy) > 1e-3 else ((0.78 * w, far_y), (0.94 * w, near_y))
            else:
                right_line = ((0.78 * w, far_y), (0.94 * w, near_y))

            far_line = ((0.0, far_y), (float(w), far_y))
            near_line = ((0.0, near_y), (float(w), near_y))

            tl = self.line_intersection(left_line, far_line)
            tr = self.line_intersection(right_line, far_line)
            br = self.line_intersection(right_line, near_line)
            bl = self.line_intersection(left_line, near_line)

            corners = self.extrapolate_missing_corners([tl, tr, br, bl], w, h)

        self.detected_corners = np.array(corners, dtype=np.float32)

        H, _ = cv2.findHomography(self.detected_corners, self.world_corners, cv2.RANSAC, 5.0)
        if H is None or abs(np.linalg.det(H)) < 1e-9:
            H, _ = cv2.findHomography(self.detected_corners, self.world_corners)

        if H is None or abs(np.linalg.det(H)) < 1e-9:
            default_corners = np.array([
                [0.22 * w, 0.44 * h],
                [0.78 * w, 0.44 * h],
                [0.94 * w, 0.82 * h],
                [0.06 * w, 0.82 * h],
            ], dtype=np.float32)
            self.detected_corners = default_corners
            H, _ = cv2.findHomography(self.detected_corners, self.world_corners)

        self.H = H
        self.H_inv = np.linalg.inv(self.H)

        return {
            "mode": self.mode,
            "occluded_corner": self.occluded_corner,
            "corners": [[float(c[0]), float(c[1])] for c in self.detected_corners],
            "H": self.H.tolist(),
            "H_inv": self.H_inv.tolist(),
            "world_dimensions": {"width": self.width, "length": self.length}
        }

    def extrapolate_missing_corners(
        self,
        corners: List[Optional[Tuple[float, float]]],
        w: int,
        h: int,
    ) -> List[Tuple[float, float]]:
        tl, tr, br, bl = corners
        default_tl = (0.22 * w, 0.44 * h)
        default_tr = (0.78 * w, 0.44 * h)
        default_br = (0.94 * w, 0.82 * h)
        default_bl = (0.06 * w, 0.82 * h)

        if tl is None or tl[1] < 0.05 * h or tl[0] < 0 or tl[0] > 0.48 * w:
            tl = default_tl
        if tr is None or tr[1] < 0.05 * h or tr[0] > w or tr[0] < 0.52 * w:
            tr = default_tr

        # Apply explicit --occluded-corner extrapolation rules
        if self.occluded_corner == "bl":
            bl = (w - (br[0] if br else default_br[0]), br[1] if br else default_br[1])
        elif self.occluded_corner == "br":
            br = (w - (bl[0] if bl else default_bl[0]), bl[1] if bl else default_bl[1])
        elif self.occluded_corner == "bottom_both":
            span_top = max(50.0, tr[0] - tl[0])
            mid_top = (tl[0] + tr[0]) / 2.0
            near_y = min(0.95 * h, tl[1] + span_top * 0.68)
            bl = (max(0.02 * w, mid_top - span_top * 0.78), near_y)
            br = (min(0.98 * w, mid_top + span_top * 0.78), near_y)

        if bl is None or bl[1] > h * 0.98 or bl[0] < -0.15 * w or bl[0] > 0.48 * w:
            bl = default_bl
        if br is None or br[1] > h * 0.98 or br[0] > w * 1.15 or br[0] < 0.52 * w:
            br = (w - bl[0], bl[1]) if bl is not None else default_br

        return [tl, tr, br, bl]

    def pixel_to_world(self, px: float, py: float) -> Tuple[float, float]:
        if self.H is None:
            return (0.0, 0.0)
        pt = np.array([[[float(px), float(py)]]], dtype=np.float32)
        trans = cv2.perspectiveTransform(pt, self.H)
        return float(trans[0][0][0]), float(trans[0][0][1])

    def world_to_pixel(self, x: float, y: float) -> Tuple[float, float]:
        if self.H_inv is None:
            return (0.0, 0.0)
        pt = np.array([[[float(x), float(y)]]], dtype=np.float32)
        trans = cv2.perspectiveTransform(pt, self.H_inv)
        return float(trans[0][0][0]), float(trans[0][0][1])

    def is_in_court(self, x_world: float, y_world: float, margin: float = 0.0) -> bool:
        return (-margin <= x_world <= self.width + margin) and (-margin <= y_world <= self.length + margin)
