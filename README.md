# Badminton AI Analyzer v4.0 PRO AI (HawkEye Broadcast Split-Screen)

Ứng dụng phân tích cầu lông **Badminton AI Analyzer v4.0 PRO AI** dành cho Android (Flutter + Native Hardware H.264 MediaCodec + Python AI Backend), tái tạo chuẩn giao diện **v4.0 PRO AI (3 Tab)** và xuất video định dạng **Broadcast Split-Screen (`976x576`)** chuẩn truyền hình BWF.

## Tính năng nổi bật

1. **Giao diện 3 Tab v4.0 PRO AI & Thanh trượt siêu mượt (`60fps+`)**
   - **Tab 1 — Video & Cấu hình**:
     - Chọn video từ máy (hỗ trợ MIUI / HyperOS / SAF / Google Drive / Android 7–15).
     - Chế độ trận đấu (`--mode`): Đánh đôi (`doubles` - 4 người) hoặc Đánh đơn (`singles` - 2 người).
     - Tên VĐV (`--player-names`): Tùy chỉnh tên 4 VĐV hiển thị trực tiếp trên Bounding Box và bảng thống kê quãng đường.
     - Góc sân bị khuất (`--occluded-corner`): Tự động nội suy góc khuất bằng phép biến đổi phối cảnh BWF (`none`, `bl`, `br`, `bottom_both`, `auto`).
     - Độ nhạy bắt cầu (`--shuttle-sensitivity` từ `0.5` đến `2.4`) và Hệ số hiệu chuẩn tốc độ (`--speed-calib` từ `0.6x` đến `1.6x`): Bọc trong `RepaintBoundary` độc lập với `ValueChanged` mượt mà, không giật lag hay làm đóng băng khung hình video.
     - Tùy chọn nâng cao: Chấm 4 góc sân thủ công (`--calibrate`) và Xuất kèm video gốc có vẽ AI overlay.
   - **Tab 2 — Chấm góc sân BWF**:
     - Chấm 4 góc sân trực quan (`TL -> TR -> BR -> BL`) với kính lúp phóng đại (`Magnifier Loupe`) chuẩn xác từng pixel trên khung hình thực tế.
     - Giữ nguyên tỉ lệ khung hình gốc (`AspectRatio` / `BoxFit.contain`), không bao giờ bóp méo video dọc (`9:16`), vuông (`1:1`) hay ngang (`16:9`).
   - **Tab 3 — Phân tích & Xuất Video Broadcast Split-Screen**:
     - Hiển thị giao diện Broadcast Split-Screen thời gian thực với thanh trượt tua frame có cơ chế **Seek Throttling (`45ms`)** mượt mà.
     - Tải xuống trực tiếp vào Bộ sưu tập (`Movies/BadmintonHawkEye/`), Lưu thành file (`Save As...` qua SAF), hoặc Chia sẻ (`Share`) sang Zalo / TikTok / Telegram.

2. **Bố cục Video Xuất Ra (Broadcast Split-Screen `976x576`)**
   - **Thanh HUD Trên Cùng (`Full Width`)**: Hiển thị `SPEED`, `MAX`, `RALLY`, `SHOTS` và trạng thái `IN / OUT` chuẩn Hawk-Eye.
   - **Khung Video Bên Trái (`75% Width`)**: Bảo toàn 100% tỉ lệ khung hình video gốc (`Letterbox / Pillarbox` tự động, không kéo giãn hay bóp méo khung hình), vẽ khung xương VĐV, vòng tròn đôi dưới chân (`Double Ground Ring`), nhãn tên + quãng đường (`m`), và quỹ đạo cầu Parabol màu vàng/cam.
   - **4 Thẻ Quãng Đường VĐV Dưới Video (`Bottom-Left`)**: Thống kê trực tiếp quãng đường di chuyển (`m`) và tốc độ (`km/h`) theo đúng màu sắc của từng VĐV.
   - **Bản Đồ Sân 2D (`COURT MAP` Bên Phải - `25% Width`, Full Height)**: Hiển thị mặt sân BWF màu xanh lá tiêu chuẩn, lưới trắng ở giữa, toàn bộ các đường cầu tích lũy màu vàng, điểm rơi `IN/OUT` và vị trí 4 VĐV thời gian thực.

## Cấu trúc dự án

- `lib/`: Mã nguồn Flutter UI (`hawkeye_screen.dart`, `hawkeye_painter.dart`, `stats_hud_widget.dart`, `mini_court_widget.dart`, `control_panel_widget.dart`, `video_engine_service.dart`, `xiaomi_safe_file_picker.dart`).
- `android/`: Cấu hình Android Gradle (`AGP 8.9.1`, `Kotlin 2.1.21`, `Gradle 8.12`, `compileSdk 36`) và Native Engine (`MainActivity.kt`) kết xuất phần cứng H.264 `MediaCodec` + `MediaMuxer`.
- `backend/`: Bộ xử lý AI Python (`cli_analyze.py`, `server.py`, `court_detector.py`, `player_tracker.py`, `shuttlecock_tracker.py`, `video_renderer.py`, `speed_estimator.py`, `line_judge.py`).
- `.github/workflows/build_apk.yml`: Workflow GitHub Actions tự động kiểm tra mã nguồn, chạy unit test backend, và đóng gói cả **Debug APK** lẫn **Release APK**.

## Sử dụng CLI Backend trực tiếp

```bash
python3 backend/cli_analyze.py \
  --input input_match.mp4 \
  --output output_broadcast.mp4 \
  --json output_report.json \
  --mode doubles \
  --player-names "P1 (Gần-T),P2 (Gần-P),P3 (Xa-T),P4 (Xa-P)" \
  --occluded-corner auto \
  --shuttle-sensitivity 1.4 \
  --speed-calib 1.0
```
