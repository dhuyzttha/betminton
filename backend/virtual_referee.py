"""
Badminton Virtual Referee & Rally Analytics
Features:
- Automated Shot Counter with debounce cooldown (Direction Inflection / Velocity Reversal Detection)
- In/Out Court Boundary Arbitration (BWF Standard Polygon Testing)
- Rally State Machine (SERVE -> IN_PLAY -> POINT_AWARDED -> BREAK)
- Live HUD Broadcast Metrics (Rally duration, Active play time, Shot count, In/Out verdict)
"""

from typing import Dict, List, Optional
from court_detector import CourtDetector


class VirtualReferee:
    def __init__(self, court_detector: CourtDetector, fps: float = 30.0):
        self.court = court_detector
        self.fps = float(fps) if fps and fps > 0 else 30.0
        self.state = "IN_PLAY"  # "SERVE", "IN_PLAY", "POINT_AWARDED", "BREAK"
        self.rally_number = 1
        self.shot_count = 1
        self.rally_duration_frames = 0
        self.active_play_frames = 0
        self.last_shot_frame = -30
        self.min_shot_interval_frames = max(6, int(0.30 * self.fps))
        self.last_velocity_y = 0
        self.last_decision = "PLAY ON"  # "IN", "OUT", "FAULT", "PLAY ON"
        self.landing_spot_bwf = None
        self.landing_spot_px = None
        self.rally_history: List[Dict] = []

    def update(self, shuttle_data: Optional[Dict], players: Dict[int, Dict]) -> Dict:
        """
        Updates referee logic, checks velocity inflections for shots with debounce cooldown,
        and tests landing boundaries.
        """
        self.rally_duration_frames += 1
        if self.state == "IN_PLAY":
            self.active_play_frames += 1

        duration_sec = self.rally_duration_frames / self.fps
        active_sec = self.active_play_frames / self.fps

        if shuttle_data is not None:
            bwf_y = float(shuttle_data["bwf_y"])
            bwf_x = float(shuttle_data["bwf_x"])

            self.rally_history.append(shuttle_data)
            if len(self.rally_history) > 100:
                self.rally_history.pop(0)

            # Check inflection in BWF Y or pixel Y direction with minimum shot cooldown
            if len(self.rally_history) >= 4:
                dy_recent = shuttle_data["bwf_y"] - self.rally_history[-4]["bwf_y"]
                if abs(dy_recent) > 0.35:
                    curr_dir_y = 1 if dy_recent > 0 else -1
                    frames_since_shot = self.rally_duration_frames - self.last_shot_frame
                    if (
                        self.last_velocity_y != 0
                        and curr_dir_y != self.last_velocity_y
                        and frames_since_shot >= self.min_shot_interval_frames
                    ):
                        self.shot_count += 1
                        self.last_shot_frame = self.rally_duration_frames
                        self.state = "IN_PLAY"
                    self.last_velocity_y = curr_dir_y

            # Check potential landing spot
            if shuttle_data.get("speed_kmh", 0.0) < 12.0 and len(self.rally_history) > 10:
                is_in = self.court.is_in_court(bwf_x, bwf_y, margin=0.05)
                self.landing_spot_bwf = (bwf_x, bwf_y)
                self.landing_spot_px = (shuttle_data["px"], shuttle_data["py"])
                self.last_decision = "IN" if is_in else "OUT"

        return {
            "state": self.state,
            "rally_number": self.rally_number,
            "shot_count": self.shot_count,
            "duration_sec": round(duration_sec, 1),
            "active_play_sec": round(active_sec, 1),
            "decision": self.last_decision,
            "landing_spot_bwf": self.landing_spot_bwf,
            "landing_spot_px": self.landing_spot_px
        }
