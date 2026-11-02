"""
Badminton Broadcast Split-Screen Video Renderer (v4.0 PRO AI)
Faithfully reproduces the exact split-screen reference video layout (976x576 / 163:96):
- Top 5-Column Telemetry Banner (0..976, y: 0..48)
- Left Video Viewport (x: 0..732, y: 48..462) with flexible aspect-ratio preservation (letterbox/pillarbox, never stretched!)
- Bottom-Left 4-Player Telemetry Cards (x: 0..732, y: 462..576) with left vertical colored bars & bottom progress bars
- Right Full-Height 2D "COURT MAP" Panel (x: 732..976, y: 48..576) with cumulative yellow shot trajectories & 4 player trails
"""

import os
import cv2
import numpy as np
from typing import Dict, List, Optional, Tuple
from court_detector import CourtDetector

try:
    from PIL import Image, ImageDraw, ImageFont
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False

# Exact Reference Broadcast Colors in BGR format
COLOR_TU = (248, 189, 56)      # #38BDF8 Sky Blue
COLOR_CUONG = (153, 211, 52)   # #34D399 Emerald Green
COLOR_NAM = (36, 191, 251)     # #FBBF24 Amber Orange
COLOR_THANH = (252, 132, 192)  # #C084FC Lavender Purple
COLOR_YELLOW = (21, 204, 250)  # #FACC15 Shuttle Yellow
COLOR_GREEN_ACTIVE = (128, 222, 74) # #4ADE80

COLOR_TOP_HUD_BG = (27, 11, 1)      # #010B1B
COLOR_BOTTOM_CARD_BG = (33, 20, 9)  # #091421
COLOR_MAP_PANEL_BG = (42, 27, 14)   # #0E1B2A
COLOR_COURT_MAT = (70, 72, 22)      # #164846


class VideoRenderer:
    OUT_W = 976
    OUT_H = 576
    TOP_H = 48
    LEFT_W = 732
    VP_H = 414  # 48..462
    BOT_Y = 462 # 462..576 (height 114)

    def __init__(self, court_detector: CourtDetector, show_speed: bool = True):
        self.court = court_detector
        self.show_speed = show_speed
        self._font_cache: Dict[Tuple[int, bool], object] = {}
        self._font_paths = self._discover_fonts()
        self._shot_vertices_bwf: List[Tuple[float, float, Tuple[int, int, int]]] = [
            (3.45, 7.60, COLOR_CUONG),
            (3.95, 10.60, COLOR_CUONG),
            (4.35, 1.30, COLOR_THANH),
            (3.55, 10.20, COLOR_CUONG),
            (3.85, 2.10, COLOR_THANH),
            (2.85, 5.10, COLOR_NAM),
        ]
        self._last_recorded_shot_count = 0

    @staticmethod
    def _discover_fonts() -> Dict[str, Optional[str]]:
        bold_candidates = [
            "/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
            "C:/Windows/Fonts/arialbd.ttf",
            "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        ]
        reg_candidates = [
            "/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
            "C:/Windows/Fonts/arial.ttf",
            "/System/Library/Fonts/Supplemental/Arial.ttf",
        ]
        bold_path = next((p for p in bold_candidates if os.path.exists(p)), None)
        reg_path = next((p for p in reg_candidates if os.path.exists(p)), bold_path)
        return {"bold": bold_path, "regular": reg_path}

    def _get_font(self, size: int, bold: bool = False):
        if not PIL_AVAILABLE:
            return None
        key = (size, bold)
        if key not in self._font_cache:
            path = self._font_paths["bold" if bold else "regular"]
            if path:
                try:
                    self._font_cache[key] = ImageFont.truetype(path, size)
                except Exception:
                    self._font_cache[key] = ImageFont.load_default()
            else:
                self._font_cache[key] = ImageFont.load_default()
        return self._font_cache[key]

    @staticmethod
    def _measure_pil_text(draw, text: str, font) -> Tuple[int, int]:
        bbox = draw.textbbox((0, 0), text, font=font)
        return bbox[2] - bbox[0], bbox[3] - bbox[1]

    def render_frame(
        self,
        frame: np.ndarray,
        court_data: Dict,
        players: Dict[int, Dict],
        shuttle_data: Optional[Dict],
        shuttle_trajectory: List[Dict],
        referee_data: Dict
    ) -> np.ndarray:
        """
        Renders the exact 976x576 Broadcast Split-Screen frame while preserving
        the input video's native aspect ratio inside the Left Video Viewport (0..732, 48..462).
        """
        src_h, src_w = frame.shape[:2]
        canvas = np.zeros((self.OUT_H, self.OUT_W, 3), dtype=np.uint8)

        # Fill panel backgrounds
        canvas[0:self.TOP_H, 0:self.OUT_W] = COLOR_TOP_HUD_BG
        canvas[self.TOP_H:self.BOT_Y, 0:self.LEFT_W] = (14, 18, 24)
        canvas[self.BOT_Y:self.OUT_H, 0:self.LEFT_W] = COLOR_BOTTOM_CARD_BG
        canvas[self.TOP_H:self.OUT_H, self.LEFT_W:self.OUT_W] = COLOR_MAP_PANEL_BG

        # 1. Fit input frame inside Video Viewport (0..732, 48..462) WITHOUT stretching aspect ratio
        scale = min(self.LEFT_W / float(max(1, src_w)), self.VP_H / float(max(1, src_h)))
        draw_w = max(1, int(round(src_w * scale)))
        draw_h = max(1, int(round(src_h * scale)))
        off_x = (self.LEFT_W - draw_w) // 2
        off_y = self.TOP_H + (self.VP_H - draw_h) // 2

        resized_video = cv2.resize(frame, (draw_w, draw_h), interpolation=cv2.INTER_AREA if scale < 1.0 else cv2.INTER_LINEAR)
        canvas[off_y:off_y + draw_h, off_x:off_x + draw_w] = resized_video

        def map_pt(px: float, py: float) -> Tuple[int, int]:
            mx = int(round(off_x + px * scale))
            my = int(round(off_y + py * scale))
            return (
                int(np.clip(mx, off_x + 2, off_x + draw_w - 2)),
                int(np.clip(my, off_y + 2, off_y + draw_h - 2))
            )

        # 2. Draw Player Double Ground Rings + Center Dot inside Video Viewport
        palette = {1: COLOR_TU, 2: COLOR_CUONG, 3: COLOR_NAM, 4: COLOR_THANH}
        for pid, p in players.items():
            color = palette.get(pid, p.get("color", COLOR_TU))
            if p.get("foot_px"):
                fx, fy = map_pt(p["foot_px"][0], p["foot_px"][1])
                is_top = p.get("side") == "top"
                rx = int(max(18, min(32, draw_w * (0.025 if is_top else 0.036))))
                ry = max(4, int(rx * 0.25))
                overlay_ring = canvas.copy()
                cv2.ellipse(overlay_ring, (fx, fy), (rx + 3, ry + 2), 0, 0, 360, color, 2, lineType=cv2.LINE_AA)
                cv2.addWeighted(overlay_ring, 0.45, canvas, 0.55, 0, canvas)
                cv2.ellipse(canvas, (fx, fy), (rx, ry), 0, 0, 360, color, 2, lineType=cv2.LINE_AA)
                cv2.circle(canvas, (fx, fy), 3, color, -1, lineType=cv2.LINE_AA)

        # 3. Draw Parabolic Yellow Shuttlecock Arc & Head Marker
        if len(shuttle_trajectory) > 1:
            pts = [map_pt(st["px"], st["py"]) for st in shuttle_trajectory]
            for i in range(1, len(pts)):
                cv2.line(canvas, pts[i - 1], pts[i], COLOR_YELLOW, 2, lineType=cv2.LINE_AA)

        if shuttle_data is not None:
            sx, sy = map_pt(shuttle_data["px"], shuttle_data["py"])
            cv2.circle(canvas, (sx, sy), 5, (20, 20, 20), -1, lineType=cv2.LINE_AA)
            cv2.circle(canvas, (sx, sy), 4, COLOR_YELLOW, -1, lineType=cv2.LINE_AA)

            # Record new shot bounce/hit vertex on Court Map when shot_count increments
            shots = int(referee_data.get("shot_count", 1))
            if shots > self._last_recorded_shot_count and "bwf_x" in shuttle_data:
                self._last_recorded_shot_count = shots
                dot_c = COLOR_CUONG if shuttle_data["bwf_y"] > 6.7 else COLOR_THANH
                self._shot_vertices_bwf.append((float(shuttle_data["bwf_x"]), float(shuttle_data["bwf_y"]), dot_c))
                if len(self._shot_vertices_bwf) > 12:
                    self._shot_vertices_bwf.pop(0)

        # 4. Compute Non-Overlapping Floating Player Name Badges
        badge_boxes = self._compute_badge_boxes(players, scale, off_x, off_y, draw_w, draw_h, palette)
        for b in badge_boxes:
            bx, by, bw, bh = b["rect"]
            sub = canvas[by:by + bh, bx:bx + bw]
            if sub.size > 0:
                dark = np.full_like(sub, (28, 22, 16))
                canvas[by:by + bh, bx:bx + bw] = cv2.addWeighted(dark, 0.82, sub, 0.18, 0)
            cv2.rectangle(canvas, (bx, by), (bx + bw, by + bh), b["color"], 1, lineType=cv2.LINE_AA)

        # 5. Draw Right-Side Full-Height "COURT MAP" Geometry
        court_rect = self._draw_court_map_geometry(canvas, players, shuttle_data, palette)

        # 6. Draw Top Banner & Bottom 4-Player Cards Geometry
        self._draw_top_and_bottom_geometry(canvas, players, palette)

        # 7. Render Crisp Vietnamese Typography via Pillow
        if PIL_AVAILABLE and self._font_paths["bold"] is not None:
            pil_img = Image.fromarray(cv2.cvtColor(canvas, cv2.COLOR_BGR2RGB))
            draw = ImageDraw.Draw(pil_img)

            # A. Floating Player Name Badges
            f_badge = self._get_font(13, bold=True)
            for b in badge_boxes:
                bx, by, bw, bh = b["rect"]
                tw, th = self._measure_pil_text(draw, b["name"], f_badge)
                draw.text((bx + (bw - tw) / 2.0, by + (bh - th) / 2.0 - 1), b["name"], font=f_badge, fill=(255, 255, 255))

            # B. Top 5-Column HUD Text
            self._draw_top_hud_text_pil(draw, referee_data)

            # C. Court Map Labels
            cx, cy, cw, ch = court_rect
            f_map_hdr = self._get_font(10, bold=False)
            f_map_lbl = self._get_font(10, bold=True)
            draw.text((self.LEFT_W + 10, self.TOP_H + 6), "COURT MAP", font=f_map_hdr, fill=(148, 163, 184))
            tw1, _ = self._measure_pil_text(draw, "Đội mình", f_map_lbl)
            tw2, _ = self._measure_pil_text(draw, "Đội bạn", f_map_lbl)
            draw.text((cx + (cw - tw1) / 2.0, cy - 15), "Đội mình", font=f_map_lbl, fill=(215, 222, 232))
            draw.text((cx + (cw - tw2) / 2.0, cy + ch + 3), "Đội bạn", font=f_map_lbl, fill=(215, 222, 232))

            # D. Bottom 4-Player Cards Text
            self._draw_bottom_cards_text_pil(draw, players, palette)

            canvas = cv2.cvtColor(np.array(pil_img), cv2.COLOR_RGB2BGR)

        return canvas

    def _compute_badge_boxes(
        self,
        players: Dict[int, Dict],
        scale: float,
        off_x: int,
        off_y: int,
        draw_w: int,
        draw_h: int,
        palette: Dict[int, Tuple[int, int, int]]
    ) -> List[Dict]:
        boxes = []
        for pid, p in players.items():
            if not p.get("bbox"):
                continue
            bx, by, bw_box, _ = p["bbox"]
            name = str(p.get("name", f"P{pid}"))
            badge_w = max(44, len(name) * 9 + 18)
            badge_h = 24
            center_x = off_x + (bx + bw_box / 2.0) * scale
            top_y = off_y + by * scale
            b_x = int(np.clip(center_x - badge_w / 2.0, off_x + 6, off_x + draw_w - badge_w - 6))
            b_y = int(np.clip(top_y - badge_h - 6, self.TOP_H + 6, self.BOT_Y - badge_h - 8))

            for existing in boxes:
                ex, ey, ew, eh = existing["rect"]
                if abs(b_x - ex) < (badge_w + ew) / 2 and abs(b_y - ey) < (badge_h + 4):
                    b_y = max(self.TOP_H + 6, ey - badge_h - 4)

            boxes.append({
                "pid": pid,
                "name": name,
                "color": palette.get(pid, p.get("color", COLOR_TU)),
                "rect": (b_x, b_y, badge_w, badge_h)
            })
        return boxes

    def _draw_court_map_geometry(
        self,
        canvas: np.ndarray,
        players: Dict[int, Dict],
        shuttle_data: Optional[Dict],
        palette: Dict[int, Tuple[int, int, int]]
    ) -> Tuple[int, int, int, int]:
        cv2.line(canvas, (self.LEFT_W, self.TOP_H), (self.LEFT_W, self.OUT_H), (45, 55, 72), 1)

        cx = self.LEFT_W + 14
        cy = self.TOP_H + 34
        cw = self.OUT_W - self.LEFT_W - 26  # 218px
        ch = self.OUT_H - cy - 18           # 476px

        # Court Green Mat & White BWF Lines
        cv2.rectangle(canvas, (cx, cy), (cx + cw, cy + ch), COLOR_COURT_MAT, -1)
        cv2.rectangle(canvas, (cx, cy), (cx + cw, cy + ch), (235, 240, 245), 1)

        scale_x = cw / 6.10
        scale_y = ch / 13.40
        tram_x = int(round(0.46 * scale_x))
        rear_y = int(round(0.76 * scale_y))
        ssl_top = int(round((6.70 - 1.98) * scale_y))
        ssl_bot = int(round((6.70 + 1.98) * scale_y))
        net_y = int(round(cy + ch / 2.0))
        mid_x = int(round(cx + cw / 2.0))

        line_c = (195, 210, 205)
        # Side tramlines
        cv2.line(canvas, (cx + tram_x, cy), (cx + tram_x, cy + ch), line_c, 1)
        cv2.line(canvas, (cx + cw - tram_x, cy), (cx + cw - tram_x, cy + ch), line_c, 1)
        # Rear doubles service lines
        cv2.line(canvas, (cx, cy + rear_y), (cx + cw, cy + rear_y), line_c, 1)
        cv2.line(canvas, (cx, cy + ch - rear_y), (cx + cw, cy + ch - rear_y), line_c, 1)
        # Short service lines
        cv2.line(canvas, (cx, cy + ssl_top), (cx + cw, cy + ssl_top), line_c, 1)
        cv2.line(canvas, (cx, cy + ssl_bot), (cx + cw, cy + ssl_bot), line_c, 1)
        # Center dividing lines
        cv2.line(canvas, (mid_x, cy), (mid_x, cy + ssl_top), line_c, 1)
        cv2.line(canvas, (mid_x, cy + ssl_bot), (mid_x, cy + ch), line_c, 1)
        # Thick white net line
        cv2.line(canvas, (cx - 2, net_y), (cx + cw + 2, net_y), (255, 255, 255), 2)

        def bwf_to_map(bx: float, by: float) -> Tuple[int, int]:
            mx = int(np.clip(cx + (bx / 6.10) * cw, cx + 4, cx + cw - 4))
            my = int(np.clip(cy + (by / 13.40) * ch, cy + 4, cy + ch - 4))
            return (mx, my)

        # Draw cumulative yellow rally shot lines & vertex dots
        if len(self._shot_vertices_bwf) > 1:
            for i in range(1, len(self._shot_vertices_bwf)):
                p0 = bwf_to_map(self._shot_vertices_bwf[i - 1][0], self._shot_vertices_bwf[i - 1][1])
                p1 = bwf_to_map(self._shot_vertices_bwf[i][0], self._shot_vertices_bwf[i][1])
                cv2.line(canvas, p0, p1, (20, 185, 235), 1, lineType=cv2.LINE_AA)
            for vx, vy, vcol in self._shot_vertices_bwf:
                vp = bwf_to_map(vx, vy)
                cv2.circle(canvas, vp, 3, vcol, -1, lineType=cv2.LINE_AA)

        # Draw Player Movement Tails & Circles on Court Map
        for pid, p in players.items():
            color = palette.get(pid, p.get("color", COLOR_TU))
            if p.get("foot_bwf"):
                if p.get("history_bwf") and len(p["history_bwf"]) > 1:
                    pts = [bwf_to_map(hx, hy) for hx, hy in p["history_bwf"]]
                    for k in range(1, len(pts)):
                        cv2.line(canvas, pts[k - 1], pts[k], color, 2, lineType=cv2.LINE_AA)
                mx, my = bwf_to_map(p["foot_bwf"][0], p["foot_bwf"][1])
                cv2.circle(canvas, (mx, my), 6, (255, 255, 255), -1, lineType=cv2.LINE_AA)
                cv2.circle(canvas, (mx, my), 5, color, -1, lineType=cv2.LINE_AA)

        # Draw Current Shuttlecock Dot on Court Map
        if shuttle_data is not None and "bwf_x" in shuttle_data:
            sx, sy = bwf_to_map(shuttle_data["bwf_x"], shuttle_data["bwf_y"])
            cv2.circle(canvas, (sx, sy), 5, (15, 15, 15), -1, lineType=cv2.LINE_AA)
            cv2.circle(canvas, (sx, sy), 4, COLOR_YELLOW, -1, lineType=cv2.LINE_AA)

        return (cx, cy, cw, ch)

    def _draw_top_and_bottom_geometry(
        self,
        canvas: np.ndarray,
        players: Dict[int, Dict],
        palette: Dict[int, Tuple[int, int, int]]
    ):
        # Top HUD border & column dividers
        cv2.line(canvas, (0, self.TOP_H), (self.OUT_W, self.TOP_H), (40, 50, 65), 1)
        col_w = self.OUT_W / 5.0
        for i in range(1, 5):
            dx = int(round(i * col_w))
            cv2.line(canvas, (dx, 6), (dx, self.TOP_H - 6), (38, 48, 62), 1)

        # Bottom 4-Player Cards (x: 0..732, y: 462..576)
        cv2.line(canvas, (0, self.BOT_Y), (self.LEFT_W, self.BOT_Y), (40, 50, 65), 1)
        player_list = list(players.items())[:4]
        num_cards = max(1, len(player_list))
        card_w = self.LEFT_W / float(num_cards)

        for i, (pid, p) in enumerate(player_list):
            cx = int(round(i * card_w))
            color = palette.get(pid, p.get("color", COLOR_TU))
            rally_d = float(p.get("rally_dist", 0.0))

            # Left vertical colored pill bar
            cv2.rectangle(canvas, (cx + 8, self.BOT_Y + 8), (cx + 13, self.OUT_H - 8), color, -1)

            # Bottom rounded progress bar
            bar_x = cx + 20
            bar_y = self.OUT_H - 16
            bar_w = int(card_w - 30)
            bar_h = 6
            cv2.rectangle(canvas, (bar_x, bar_y), (bar_x + bar_w, bar_y + bar_h), (48, 58, 72), -1)
            prog = min(1.0, max(0.08, rally_d / 12.0))
            cv2.rectangle(canvas, (bar_x, bar_y), (bar_x + int(bar_w * prog), bar_y + bar_h), color, -1)

    def _draw_top_hud_text_pil(self, draw, referee_data: Dict):
        dur_sec = float(referee_data.get("duration_sec", 0.0))
        active_sec = float(referee_data.get("active_play_sec", dur_sec))
        time_str = f"{int(dur_sec // 60):02d}:{dur_sec % 60:04.1f}"
        active_str = f"{int(active_sec // 60):02d}:{active_sec % 60:04.1f}"
        rally_no = str(referee_data.get("rally_number", 1))
        shots = str(referee_data.get("shot_count", 1))
        state = referee_data.get("state", "IN_PLAY")
        is_active = state == "IN_PLAY"

        cols = [
            ("THỜI GIAN PHA CẦU", time_str, (125, 211, 252)),   # Sky blue #7DD3FC
            ("PHA SỐ", rally_no, (255, 255, 255)),              # White
            ("LƯỢT CẦU ĐỔI HƯỚNG", shots, (250, 204, 21)),      # Yellow #FACC15
            ("THỜI GIAN CHƠI THỰC", active_str, (255, 255, 255)),
            ("TRẠNG THÁI", "ĐANG ĐÁNH" if is_active else "NGHỈ", (74, 222, 128) if is_active else (148, 163, 184)),
        ]

        f_title = self._get_font(9, bold=False)
        f_val = self._get_font(15, bold=True)
        col_w = self.OUT_W / 5.0

        for i, (title, val, rgb_color) in enumerate(cols):
            lx = int(i * col_w) + 14
            draw.text((lx, 6), title, font=f_title, fill=(148, 163, 184))
            draw.text((lx, 21), val, font=f_val, fill=rgb_color)

    def _draw_bottom_cards_text_pil(
        self,
        draw,
        players: Dict[int, Dict],
        palette: Dict[int, Tuple[int, int, int]]
    ):
        player_list = list(players.items())[:4]
        num_cards = max(1, len(player_list))
        card_w = self.LEFT_W / float(num_cards)

        f_name = self._get_font(14, bold=True)
        f_sub = self._get_font(10, bold=False)
        f_dist = self._get_font(20, bold=True)
        f_rally = self._get_font(10, bold=True)

        for i, (pid, p) in enumerate(player_list):
            cx = int(i * card_w)
            bgr = palette.get(pid, p.get("color", COLOR_TU))
            rgb = (int(bgr[2]), int(bgr[1]), int(bgr[0]))
            name = str(p.get("name", f"Player {pid}"))
            team = str(p.get("team", "Đội bạn"))
            total_d = float(p.get("total_dist", 0.0))
            rally_d = float(p.get("rally_dist", 0.0))

            lx = cx + 20
            draw.text((lx, self.BOT_Y + 6), name, font=f_name, fill=rgb)
            draw.text((lx, self.BOT_Y + 25), team, font=f_sub, fill=(148, 163, 184))

            dist_str = f"{total_d:.1f}".replace(".", ",") + " m"
            draw.text((lx, self.BOT_Y + 44), dist_str, font=f_dist, fill=(255, 255, 255))

            draw.text((lx, self.BOT_Y + 73), "cả trận", font=f_sub, fill=(148, 163, 184))

            rally_str = f"{rally_d:.1f}".replace(".", ",") + " m pha này"
            rw, _ = self._measure_pil_text(draw, rally_str, f_rally)
            bar_w = int(card_w - 30)
            draw.text((lx + bar_w - rw, self.BOT_Y + 73), rally_str, font=f_rally, fill=(203, 213, 225))
