"""
Badminton Hawk-Eye FastAPI Server (v4.0 PRO AI)
Provides WebSocket live telemetry streaming, video processing, and direct MP4 export endpoints.
"""

from fastapi import FastAPI, UploadFile, File, Form, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, FileResponse
import uvicorn
import shutil
import os
import cv2
import json
from court_detector import CourtDetector
from cli_analyze import process_video, NumpyEncoder

app = FastAPI(title="Badminton AI Analyzer v4.0 PRO AI Engine", version="4.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
UPLOAD_DIR = os.path.join(BASE_DIR, "uploads")
OUTPUT_DIR = os.path.join(BASE_DIR, "processed")
os.makedirs(UPLOAD_DIR, exist_ok=True)
os.makedirs(OUTPUT_DIR, exist_ok=True)


def _safe_filename(filename: str, default: str = "video.mp4") -> str:
    base = os.path.basename(filename or default)
    cleaned = "".join(c if c.isalnum() or c in "._-" else "_" for c in base)
    return cleaned or default


@app.get("/")
def read_root():
    return {
        "system": "Badminton AI Analyzer v4.0 PRO AI Engine",
        "status": "ONLINE",
        "version": "4.0.0"
    }


@app.post("/api/calibrate_court")
async def calibrate_court(
    file: UploadFile = File(...),
    mode: str = Form("doubles"),
    occluded_corner: str = Form("none")
):
    safe_name = _safe_filename(file.filename, "frame.jpg")
    temp_path = os.path.join(UPLOAD_DIR, f"calib_{safe_name}")
    try:
        with open(temp_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        img = cv2.imread(temp_path)
        if img is None:
            return JSONResponse(status_code=400, content={"error": "Invalid image file"})

        detector = CourtDetector(mode=mode, occluded_corner=occluded_corner)
        court_info = detector.detect_court(img)
        return JSONResponse(content=json.loads(json.dumps(court_info, cls=NumpyEncoder)))
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)


@app.post("/api/analyze_video")
async def analyze_video(
    file: UploadFile = File(...),
    mode: str = Form("doubles"),
    player_names: str = Form("Tú, Cường, Nam, Thành"),
    player1: str = Form("Tú"),
    player2: str = Form("Cường"),
    player3: str = Form("Nam"),
    player4: str = Form("Thành"),
    occluded_corner: str = Form("none"),
    sensitivity: float = Form(1.2),
    speed_calib: float = Form(1.0),
):
    safe_name = _safe_filename(file.filename, "input.mp4")
    if not safe_name.lower().endswith(".mp4"):
        safe_name = os.path.splitext(safe_name)[0] + ".mp4"

    input_path = os.path.join(UPLOAD_DIR, safe_name)
    output_filename = f"hawkeye_{safe_name}"
    output_path = os.path.join(OUTPUT_DIR, output_filename)

    with open(input_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    parsed_names = [n.strip() for n in player_names.split(",") if n.strip()] if player_names else None

    try:
        telemetry_data = process_video(
            input_path=input_path,
            output_path=output_path,
            mode=mode,
            sensitivity=float(sensitivity),
            speed_calib=float(speed_calib),
            occluded_corner=occluded_corner,
            player_names=parsed_names,
            player1=player1,
            player2=player2,
            player3=player3,
            player4=player4,
        )
    except Exception as e:
        return JSONResponse(status_code=500, content={"status": "error", "error": str(e)})

    return JSONResponse(content={
        "status": "success",
        "output_filename": output_filename,
        "video_url": f"/api/download/{output_filename}",
        "telemetry": telemetry_data["summary"],
        "court_metadata": telemetry_data["court_metadata"],
        "total_frames": telemetry_data["video_metadata"]["total_frames"]
    })


@app.get("/api/download/{filename}")
async def download_file(filename: str):
    safe_name = _safe_filename(filename)
    path = os.path.join(OUTPUT_DIR, safe_name)
    if os.path.exists(path):
        return FileResponse(
            path,
            media_type="video/mp4",
            filename=safe_name,
            headers={"Content-Disposition": f'attachment; filename="{safe_name}"'}
        )
    return JSONResponse(status_code=404, content={"error": "Processed video file not found"})


@app.get("/api/list_exports")
async def list_exports():
    files = []
    if os.path.exists(OUTPUT_DIR):
        for fname in sorted(os.listdir(OUTPUT_DIR)):
            if fname.lower().endswith(".mp4"):
                fpath = os.path.join(OUTPUT_DIR, fname)
                files.append({
                    "filename": fname,
                    "size_bytes": os.path.getsize(fpath),
                    "download_url": f"/api/download/{fname}"
                })
    return {"status": "success", "exports": files}


@app.websocket("/ws/live_telemetry")
async def websocket_telemetry_stream(websocket: WebSocket):
    await websocket.accept()
    try:
        while True:
            data = await websocket.receive_text()
            try:
                req = json.loads(data)
            except json.JSONDecodeError:
                req = {"raw": data}
            await websocket.send_text(json.dumps({"status": "ack", "received": req}))
    except WebSocketDisconnect:
        print("WebSocket client disconnected")


if __name__ == "__main__":
    uvicorn.run("server:app", host="0.0.0.0", port=8000, reload=True)
