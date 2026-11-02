import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/math/homography_matrix.dart';
import '../../../../core/math/kalman_filter.dart';
import '../../../../core/utils/debouncer.dart';
import '../../domain/models/court_model.dart';
import '../../domain/models/player_model.dart';
import '../../domain/models/shuttlecock_model.dart';
import '../../domain/models/rally_stats.dart';
import '../../data/services/xiaomi_safe_file_picker.dart';
import '../../data/services/video_engine_service.dart';
import '../widgets/hawkeye_painter.dart';
import '../widgets/mini_court_widget.dart';
import '../widgets/stats_hud_widget.dart';
import '../widgets/control_panel_widget.dart';

class HawkEyeScreen extends StatefulWidget {
  const HawkEyeScreen({super.key});

  @override
  State<HawkEyeScreen> createState() => _HawkEyeScreenState();
}

class _HawkEyeScreenState extends State<HawkEyeScreen> {
  int _selectedTabIndex = 0; // 0: Video & Cấu hình, 1: Chấm góc sân BWF, 2: Phân tích & Xuất Video

  VideoPlayerController? _videoController;
  Timer? _demoSimulationTimer;
  late final Throttler _seekThrottler;
  late final TextEditingController _playerNamesController;

  bool _isLoading = false;
  bool _isExporting = false;
  double _exportProgress = 0.0;
  String _exportStatusMessage = '';
  String? _videoPath;
  String? _lastExportedVideoPath;
  double? _seekingValueMs;

  late final VideoEngineService _videoEngineService;

  // Algorithm parameters matching Badminton AI Analyzer v4.0 PRO AI UI
  late CourtModel _court;
  late List<PlayerModel> _players;
  late ShuttlecockModel _shuttlecock;
  late RallyStats _rallyStats;

  String _occludedCorner = 'none';
  double _shuttleSensitivity = 1.2; // 0.5 .. 2.4 (default 1.2)
  double _speedCalib = 1.0;         // 0.6 .. 1.6 (default 1.0x)
  bool _autoDetectCorners = true;
  bool _showShuttleSpeed = true;
  bool _preserveAspectRatio = true;
  double _demoElapsedSeconds = 0.0;

  // Corner calibration state (Tab 2)
  int? _activeDraggingCornerIndex;
  Offset? _activeDragCanvasPos;

  late ShuttlecockKalmanFilter _kalmanFilter;

  @override
  void initState() {
    super.initState();
    _videoEngineService = VideoEngineService();
    _seekThrottler = Throttler(interval: const Duration(milliseconds: 32));
    _playerNamesController = TextEditingController(text: 'Tú, Cường, Nam, Thành');
    _court = CourtModel.initial(CourtMode.doubles);
    _initPlayers(const Size(732, 414));
    _shuttlecock = ShuttlecockModel();
    _rallyStats = RallyStats();
    _kalmanFilter = ShuttlecockKalmanFilter();
  }

  List<String> _getParsedPlayerNames() {
    final raw = _playerNamesController.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    const defaults = ['Tú', 'Cường', 'Nam', 'Thành'];
    return List.generate(4, (i) => i < raw.length ? raw[i] : defaults[i]);
  }

  void _initPlayers(Size videoSize) {
    final double w = videoSize.width > 0 ? videoSize.width : 732.0;
    final double h = videoSize.height > 0 ? videoSize.height : 414.0;
    final names = _getParsedPlayerNames();

    Offset projectBwf(Offset bwf) {
      final px = _court.inverseHomography?.transform(bwf);
      if (px != null && px.dx > 0 && px.dx < w && px.dy > 0 && px.dy < h) {
        return px;
      }
      return Offset(
        w * (0.18 + 0.62 * (bwf.dx / 6.10)),
        h * (0.45 + 0.38 * (bwf.dy / 13.40)),
      );
    }

    Rect makeBbox(Offset foot, bool isTop) {
      final double boxW = w * (isTop ? 0.048 : 0.062);
      final double boxH = h * (isTop ? 0.21 : 0.32);
      return Rect.fromLTWH(foot.dx - boxW / 2, foot.dy - boxH, boxW, boxH);
    }

    const p1Bwf = Offset(1.45, 10.30);
    const p2Bwf = Offset(4.25, 10.50);
    const p3Bwf = Offset(2.35, 4.10);
    const p4Bwf = Offset(4.55, 2.50);

    final f1 = projectBwf(p1Bwf);
    final f2 = projectBwf(p2Bwf);
    final f3 = projectBwf(p3Bwf);
    final f4 = projectBwf(p4Bwf);

    _players = [
      PlayerModel(
        id: 1,
        name: names[0],
        team: "Đội bạn",
        side: "bottom",
        color: HawkEyeTheme.playerTu,
        bbox: makeBbox(f1, false),
        footPx: f1,
        footBwf: p1Bwf,
        totalDistanceMeters: 0.4,
        rallyDistanceMeters: 0.1,
        historyBwf: const [Offset(1.40, 10.60), p1Bwf],
      ),
      PlayerModel(
        id: 2,
        name: names[1],
        team: "Đội bạn",
        side: "bottom",
        color: HawkEyeTheme.playerCuong,
        bbox: makeBbox(f2, false),
        footPx: f2,
        footBwf: p2Bwf,
        totalDistanceMeters: 0.4,
        rallyDistanceMeters: 0.2,
        historyBwf: const [Offset(4.35, 10.80), p2Bwf],
      ),
      PlayerModel(
        id: 3,
        name: names[2],
        team: "Đội mình",
        side: "top",
        color: HawkEyeTheme.playerNam,
        bbox: makeBbox(f3, true),
        footPx: f3,
        footBwf: p3Bwf,
        totalDistanceMeters: 0.3,
        rallyDistanceMeters: 0.1,
        historyBwf: const [Offset(2.25, 3.85), p3Bwf],
      ),
      PlayerModel(
        id: 4,
        name: names[3],
        team: "Đội mình",
        side: "top",
        color: HawkEyeTheme.playerThanh,
        bbox: makeBbox(f4, true),
        footPx: f4,
        footBwf: p4Bwf,
        totalDistanceMeters: 0.7,
        rallyDistanceMeters: 0.3,
        historyBwf: const [Offset(4.65, 2.25), p4Bwf],
      ),
    ];
  }

  @override
  void dispose() {
    _demoSimulationTimer?.cancel();
    _seekThrottler.dispose();
    _playerNamesController.dispose();
    _videoController?.removeListener(_onVideoTick);
    _videoController?.dispose();
    super.dispose();
  }

  Size get _effectiveVideoSize {
    if (_videoController != null && _videoController!.value.isInitialized) {
      final sz = _videoController!.value.size;
      if (sz.width > 0 && sz.height > 0) return sz;
    }
    return const Size(732, 414);
  }

  Future<void> _handlePickVideo() async {
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    try {
      final path = await XiaomiSafeFilePicker.pickVideo();
      if (path != null) {
        _demoSimulationTimer?.cancel();
        _demoSimulationTimer = null;
        _videoPath = path;
        _lastExportedVideoPath = null;
        await _initializeVideo(File(path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải video: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _initializeVideo(File file) async {
    final oldController = _videoController;
    if (oldController != null) {
      oldController.removeListener(_onVideoTick);
      await oldController.dispose();
    }

    final controller = VideoPlayerController.file(file);
    _videoController = controller;
    await controller.initialize();
    if (!mounted) return;

    final videoSize = controller.value.size;
    if (_autoDetectCorners) {
      _court = CourtModel.initial(_court.mode, videoSize: videoSize);
    }
    _kalmanFilter.reset();
    _initPlayers(videoSize);

    await controller.setLooping(true);
    controller.addListener(_onVideoTick);
    await controller.play();
    if (mounted) setState(() {});
  }

  void _runAnalysisNow() {
    FocusScope.of(context).unfocus();
    _initPlayers(_effectiveVideoSize);
    setState(() {
      _selectedTabIndex = 2; // Jump to Tab 3: Phân tích & Xuất Video
    });
    if (_videoController != null && _videoController!.value.isInitialized) {
      if (!_videoController!.value.isPlaying) {
        _videoController!.play();
      }
    } else {
      if (_demoSimulationTimer == null || !_demoSimulationTimer!.isActive) {
        _startOrToggleDemoSimulation();
      }
    }
  }

  void _startOrToggleDemoSimulation() {
    if (_demoSimulationTimer != null && _demoSimulationTimer!.isActive) {
      _demoSimulationTimer!.cancel();
      _demoSimulationTimer = null;
      setState(() {
        _rallyStats = _rallyStats.copyWith(state: RallyState.paused);
      });
    } else {
      _demoSimulationTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
        if (!mounted) return;
        _demoElapsedSeconds += 0.033;
        _updateTelemetryAtTime(_demoElapsedSeconds, _effectiveVideoSize);
      });
    }
  }

  void _onVideoTick() {
    if (!mounted || _videoController == null || !_videoController!.value.isInitialized) {
      return;
    }

    final value = _videoController!.value;
    if (!value.isPlaying) {
      if (_rallyStats.state != RallyState.paused) {
        setState(() {
          _rallyStats = _rallyStats.copyWith(state: RallyState.paused);
        });
      }
      return;
    }

    final double t = value.position.inMilliseconds / 1000.0;
    _updateTelemetryAtTime(t, value.size);
  }

  void _updateTelemetryAtTime(double t, Size videoSize) {
    final double w = videoSize.width > 0 ? videoSize.width : 732.0;
    final double h = videoSize.height > 0 ? videoSize.height : 414.0;
    final names = _getParsedPlayerNames();

    final double sBwfX = (_court.width * 0.52) + (_court.width * 0.25) * math.sin(t * 1.9);
    final double sBwfY = (_court.length * 0.50) + (_court.length * 0.36) * math.cos(t * 1.45);
    final Offset rawShuttlePx = _court.inverseHomography?.transform(Offset(sBwfX, sBwfY)) ??
        Offset(w * 0.5, h * 0.55);
    final Offset elevatedPx = Offset(
      rawShuttlePx.dx,
      (rawShuttlePx.dy - (h * 0.14) * math.sin(t * 1.45).abs()).clamp(8.0, h - 8.0),
    );

    _kalmanFilter.predict();
    final Offset smoothedPx = _kalmanFilter.update(elevatedPx);
    final Offset bwfPos = Offset(sBwfX, sBwfY);
    final double simSpeed =
        ((115.0 + 80.0 * math.sin(t * 2.2).abs()) * _speedCalib).clamp(40.0, 380.0);

    final List<TrajectoryPoint> updatedTrail = List.from(_shuttlecock.trajectory);
    updatedTrail.add(TrajectoryPoint(
      frame: (t * 30).toInt(),
      px: smoothedPx,
      bwf: bwfPos,
      speedKmh: simSpeed,
    ));
    if (updatedTrail.length > 16) updatedTrail.removeAt(0);

    const List<Offset> anchors = [
      Offset(1.45, 10.30), // Tú
      Offset(4.25, 10.50), // Cường
      Offset(2.35, 4.10),  // Nam
      Offset(4.55, 2.50),  // Thành
    ];

    final List<PlayerModel> updatedPlayers = [];
    for (int i = 0; i < _players.length; i++) {
      final p = _players[i];
      final anchor = anchors[i % anchors.length];
      final double phase = (i + 1) * 1.35;
      final Offset newBwf = Offset(
        (anchor.dx + 0.38 * math.sin(t * 1.4 + phase)).clamp(0.45, _court.width - 0.45),
        (anchor.dy + 0.45 * math.cos(t * 1.1 + phase * 0.8)).clamp(0.75, _court.length - 0.75),
      );

      final Offset newFootPx = _court.inverseHomography?.transform(newBwf) ??
          Offset(w * (0.18 + 0.62 * (newBwf.dx / 6.10)), h * (0.45 + 0.38 * (newBwf.dy / 13.40)));
      final bool isTop = p.side == "top";
      final double boxW = w * (isTop ? 0.048 : 0.062);
      final double boxH = h * (isTop ? 0.21 : 0.32);
      final Rect newBbox = Rect.fromLTWH(newFootPx.dx - boxW / 2, newFootPx.dy - boxH, boxW, boxH);

      final double stepDist = p.footBwf != null ? (newBwf - p.footBwf!).distance : 0.02;
      final double validDelta =
          ((stepDist > 0.001 && stepDist < 0.35) ? stepDist : 0.016) * _speedCalib;

      final List<Offset> newHistory = List.from(p.historyBwf)..add(newBwf);
      if (newHistory.length > 22) newHistory.removeAt(0);

      updatedPlayers.add(
        PlayerModel(
          id: p.id,
          name: names[i % names.length],
          team: p.team,
          side: p.side,
          color: p.color,
          bbox: newBbox,
          footPx: newFootPx,
          footBwf: newBwf,
          totalDistanceMeters: p.totalDistanceMeters + validDelta,
          rallyDistanceMeters: p.rallyDistanceMeters + validDelta * 0.92,
          historyBwf: newHistory,
        ),
      );
    }

    setState(() {
      _players = updatedPlayers;
      _shuttlecock = _shuttlecock.copyWith(
        currentPx: smoothedPx,
        currentBwf: bwfPos,
        currentSpeedKmh: simSpeed,
        maxSpeedKmh: simSpeed > _shuttlecock.maxSpeedKmh ? simSpeed : _shuttlecock.maxSpeedKmh,
        trajectory: updatedTrail,
        isTracking: true,
      );

      _rallyStats = _rallyStats.copyWith(
        durationSeconds: t,
        activePlaySeconds: t,
        shotCount: math.max(1, (t * 1.3).round()),
        state: RallyState.inPlay,
      );
    });
  }

  void _onModeChanged(CourtMode mode) {
    setState(() {
      _court = CourtModel.initial(mode, videoSize: _effectiveVideoSize);
      final currentText = _playerNamesController.text.trim();
      if (mode == CourtMode.singles &&
          (currentText.isEmpty || currentText == 'Tú, Cường, Nam, Thành')) {
        _playerNamesController.text = 'Người chơi 1, Người chơi 2';
      } else if (mode == CourtMode.doubles &&
          (currentText.isEmpty || currentText == 'Người chơi 1, Người chơi 2')) {
        _playerNamesController.text = 'Tú, Cường, Nam, Thành';
      }
      _initPlayers(_effectiveVideoSize);
    });
  }

  void _applyOccludedCornerExtrapolation() {
    final sz = _effectiveVideoSize;
    final c = List<Offset>.from(_court.corners);
    List<Offset> updated = c;
    if (_occludedCorner == 'bl') {
      updated = HomographyMatrix.extrapolateMissingCorners(
        tl: c[0],
        tr: c[1],
        br: c[2],
        bl: null,
        imageWidth: sz.width,
        imageHeight: sz.height,
      );
    } else if (_occludedCorner == 'br') {
      updated = HomographyMatrix.extrapolateMissingCorners(
        tl: c[0],
        tr: c[1],
        br: null,
        bl: c[3],
        imageWidth: sz.width,
        imageHeight: sz.height,
      );
    } else if (_occludedCorner == 'bottom_both' || _occludedCorner == 'auto') {
      updated = HomographyMatrix.extrapolateMissingCorners(
        tl: c[0],
        tr: c[1],
        br: null,
        bl: null,
        imageWidth: sz.width,
        imageHeight: sz.height,
      );
    }
    setState(() {
      _court = _court.copyWithCorners(updated);
      _initPlayers(sz);
    });
  }

  void _togglePlayPause() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      _startOrToggleDemoSimulation();
      return;
    }
    if (_videoController!.value.isPlaying) {
      _videoController!.pause();
      setState(() {
        _rallyStats = _rallyStats.copyWith(state: RallyState.paused);
      });
    } else {
      _videoController!.play();
      setState(() {
        _rallyStats = _rallyStats.copyWith(state: RallyState.inPlay);
      });
    }
  }

  void _stepFrame(int frames) {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      _demoElapsedSeconds = math.max(0.0, _demoElapsedSeconds + frames * (1.0 / 30.0));
      _updateTelemetryAtTime(_demoElapsedSeconds, _effectiveVideoSize);
      return;
    }
    final currentMs = _videoController!.value.position.inMilliseconds;
    final stepMs = (frames * (1000 / 30)).toInt();
    final maxMs = _videoController!.value.duration.inMilliseconds;
    final target = Duration(milliseconds: (currentMs + stepMs).clamp(0, maxMs));
    _videoController!.seekTo(target);
  }

  Future<void> _executeVideoExport(String exportTarget) async {
    if (_isExporting) return;

    final bool wasPlaying = _videoController?.value.isPlaying ?? false;
    if (wasPlaying) {
      await _videoController?.pause();
    }

    setState(() {
      _isExporting = true;
      _exportProgress = 0.05;
      _exportStatusMessage = 'Đang khởi tạo Engine kết xuất Broadcast Split-Screen 976×576...';
    });

    try {
      Map<String, dynamic>? exportResult;

      if (_lastExportedVideoPath != null && File(_lastExportedVideoPath!).existsSync()) {
        setState(() {
          _exportProgress = 0.92;
          _exportStatusMessage = 'Đang xuất file video MP4 đã xử lý...';
        });
        if (exportTarget == 'gallery') {
          exportResult = await XiaomiSafeFilePicker.exportVideoToGallery(_lastExportedVideoPath!);
        } else if (exportTarget == 'save_as') {
          exportResult = await XiaomiSafeFilePicker.saveVideoAsDialog(_lastExportedVideoPath!);
        } else if (exportTarget == 'share') {
          await XiaomiSafeFilePicker.shareVideoFile(_lastExportedVideoPath!);
          exportResult = {
            'status': 'success',
            'filePath': _lastExportedVideoPath,
            'displayPath': 'Đã mở bảng chia sẻ'
          };
        }
      } else {
        File? serverProcessedFile;
        if (_videoPath != null && File(_videoPath!).existsSync()) {
          final bool serverOnline = await _videoEngineService.checkServerHealth();
          if (serverOnline && mounted) {
            setState(() {
              _exportProgress = 0.25;
              _exportStatusMessage = 'Đang xử lý video trên Server Python CV v4.0...';
            });
            final analysis = await _videoEngineService.uploadAndAnalyze(
              videoFile: File(_videoPath!),
              mode: _court.mode,
              playerNames: _playerNamesController.text,
              occludedCorner: _occludedCorner,
              sensitivity: _shuttleSensitivity,
              speedCalib: _speedCalib,
            );
            if (analysis != null && analysis['video_url'] != null) {
              setState(() {
                _exportProgress = 0.75;
                _exportStatusMessage = 'Đang tải video Broadcast MP4 về máy...';
              });
              final cacheDir =
                  await XiaomiSafeFilePicker.getCacheDirectory() ?? Directory.systemTemp.path;
              final localOut =
                  '$cacheDir/BadmintonAI_v4_${DateTime.now().millisecondsSinceEpoch}.mp4';
              serverProcessedFile = await _videoEngineService.downloadProcessedVideo(
                videoUrlPath: analysis['video_url'].toString(),
                targetFilePath: localOut,
              );
            }
          }
        }

        if (serverProcessedFile != null && serverProcessedFile.existsSync()) {
          _lastExportedVideoPath = serverProcessedFile.path;
          if (exportTarget == 'gallery') {
            exportResult =
                await XiaomiSafeFilePicker.exportVideoToGallery(serverProcessedFile.path);
          } else if (exportTarget == 'save_as') {
            exportResult =
                await XiaomiSafeFilePicker.saveVideoAsDialog(serverProcessedFile.path);
          } else if (exportTarget == 'share') {
            await XiaomiSafeFilePicker.shareVideoFile(serverProcessedFile.path);
            exportResult = {
              'status': 'success',
              'filePath': serverProcessedFile.path,
              'displayPath': 'Đã chia sẻ video'
            };
          }
        } else {
          exportResult = await XiaomiSafeFilePicker.renderAndExportVideo(
            inputPath: _videoPath,
            mode: _court.mode == CourtMode.singles ? 'singles' : 'doubles',
            playerNames: _playerNamesController.text,
            occludedCorner: _occludedCorner,
            sensitivity: _shuttleSensitivity,
            speedCalib: _speedCalib,
            exportTarget: exportTarget,
            onProgress: (p) {
              if (!mounted) return;
              setState(() {
                _exportProgress = p.clamp(0.05, 1.0);
                _exportStatusMessage =
                    'Đang kết xuất Video Broadcast HUD + COURT MAP (${(_exportProgress * 100).toInt()}%)...';
              });
            },
          );

          if (exportResult != null && exportResult['filePath'] != null) {
            _lastExportedVideoPath = exportResult['filePath'].toString();
          }
        }
      }

      if (!mounted) return;

      if (exportResult != null && exportResult['status'] == 'success') {
        final String displayPath =
            (exportResult['displayPath'] ?? 'Movies/BadmintonHawkEye').toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF065F46),
            duration: const Duration(seconds: 6),
            content: Text(
              'Đã tải xuống video thành công: $displayPath',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            action: _lastExportedVideoPath != null
                ? SnackBarAction(
                    label: 'CHIA SẺ',
                    textColor: HawkEyeTheme.playerCuong,
                    onPressed: () {
                      XiaomiSafeFilePicker.shareVideoFile(_lastExportedVideoPath!);
                    },
                  )
                : null,
          ),
        );
      } else if (exportResult != null && exportResult['status'] == 'cancelled') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã huỷ lưu file video.')),
        );
      } else {
        final String errMsg = (exportResult?['error'] ?? 'Không thể xuất video').toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi xuất video: $errMsg'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi xuất video: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _exportProgress = 0.0;
          _exportStatusMessage = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HawkEyeTheme.background,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildTopHeaderAndTabs(),
                Expanded(
                  child: IndexedStack(
                    index: _selectedTabIndex,
                    children: [
                      _buildTab1VideoAndConfig(),
                      _buildTab2CornerCalibration(),
                      _buildTab3BroadcastAnalyzeAndExport(),
                    ],
                  ),
                ),
              ],
            ),
            if (_isLoading || _isExporting)
              Container(
                color: Colors.black87,
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        value: _isExporting && _exportProgress > 0 ? _exportProgress : null,
                        color: HawkEyeTheme.runGreen,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isExporting ? _exportStatusMessage : 'Đang tải video cầu lông...',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Header & 3-Tab Segmented Bar matching Screenshot_2026-11-02-02-50-29-076_com.badminton.aianalyzer.jpg
  Widget _buildTopHeaderAndTabs() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF0D141F),
        border: Border(
          bottom: BorderSide(color: Color(0xFF1E293B), width: 1.0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Blue vertical oval Play icon badge
              Container(
                width: 32,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0284C7), Color(0xFF0EA5E9)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.play_circle_outline,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        const Text(
                          'Badminton AI Analyzer',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: HawkEyeTheme.badgeTealBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF14B8A6), width: 0.8),
                          ),
                          child: const Text(
                            'v4.0 PRO AI',
                            style: TextStyle(
                              color: HawkEyeTheme.badgeTealText,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Tự Nhận Diện 4 Góc Sân AI • Ảnh Mờ Chấm Góc • Đo Tốc Độ Cầu (km/h) • BWF 13.4m × 6.1m',
                      style: TextStyle(
                        color: HawkEyeTheme.textSecondary,
                        fontSize: 11.0,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 3-Tab Segmented Navigation Container
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: const Color(0xFF090E17),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1E293B), width: 1.0),
            ),
            child: Row(
              children: [
                _buildTabButton(0, '1. Video &\nCấu hình'),
                _buildTabButton(1, '2. Chấm\ngóc sân BWF'),
                _buildTabButton(2, '3. Phân tích &\nXuất Video'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, String label) {
    final bool isSelected = _selectedTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          setState(() => _selectedTabIndex = index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected ? HawkEyeTheme.tabActiveBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : HawkEyeTheme.textSecondary,
              fontSize: 12.0,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              height: 1.25,
            ),
          ),
        ),
      ),
    );
  }

  /// TAB 1: Video Input & Algorithm Parameters (Exact match to uploaded screenshot)
  Widget _buildTab1VideoAndConfig() {
    final bool hasVideo = _videoController != null && _videoController!.value.isInitialized;
    final Size vSize = _effectiveVideoSize;
    final String aspectStr =
        '${vSize.width.toInt()}×${vSize.height.toInt()} (Tỉ lệ ${(vSize.width / vSize.height).toStringAsFixed(2)}:1)';

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        // CARD 1: Video Input & Quick Actions
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: HawkEyeTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1E293B), width: 1.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildStepCircle('1'),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Nguồn Video Cầu Lông Đầu Vào',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _handlePickVideo,
                    icon: const Icon(Icons.video_library_outlined, size: 16, color: HawkEyeTheme.accentBlue),
                    label: Text(
                      hasVideo ? 'Đổi Video' : 'Chọn Video',
                      style: const TextStyle(color: HawkEyeTheme.accentBlue, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Video Preview Box (Flexible Aspect Ratio - Never Stretched!)
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF090E17),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: HawkEyeTheme.borderSubtle),
                ),
                child: hasVideo
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: _videoController!.value.aspectRatio,
                            child: VideoPlayer(_videoController!),
                          ),
                        ),
                      )
                    : InkWell(
                        onTap: _handlePickVideo,
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.cloud_upload_outlined, size: 36, color: HawkEyeTheme.accentBlue),
                              const SizedBox(height: 8),
                              const Text(
                                'Bấm để chọn video cầu lông từ điện thoại (MP4 / MOV)',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Hỗ trợ mọi tỉ lệ khung hình (16:9 ngang, 9:16 dọc, 4:3) không bị bóp méo',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: HawkEyeTheme.textSecondary, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
              if (hasVideo) ...[
                const SizedBox(height: 8),
                Text(
                  'Khung hình gốc: $aspectStr • Giữ nguyên tỉ lệ (Không kéo giãn)',
                  style: const TextStyle(color: HawkEyeTheme.badgeTealText, fontSize: 11.5),
                ),
              ],
              const SizedBox(height: 14),
              // Action Buttons matching top of screenshot:
              // [Chấm Góc Sân (--calibrate)] & [Chạy Phân Tích Ngay ->]
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      setState(() => _selectedTabIndex = 1);
                    },
                    style: OutlinedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E293B),
                      side: const BorderSide(color: Color(0xFF334155)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text(
                      'Chấm Góc Sân (--calibrate)',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _runAnalysisNow,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HawkEyeTheme.runGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    label: const Icon(Icons.arrow_forward, size: 18),
                    icon: const Text(
                      'Chạy Phân Tích Ngay',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // CARD 2: Tham Số Thuật Toán (Chuẩn File Python v3.0) - Exact match to screenshot!
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: HawkEyeTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1E293B), width: 1.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildStepCircle('2'),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Tham Số Thuật Toán (Chuẩn File Python v3.0)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // 1. Chế độ trận đấu (--mode)
              _buildParamLabel('Chế độ trận đấu (', '--mode', ')'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: HawkEyeTheme.surfaceInput,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: HawkEyeTheme.borderSubtle),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<CourtMode>(
                    value: _court.mode,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF16202E),
                    icon: const Icon(Icons.keyboard_arrow_down, color: HawkEyeTheme.textSecondary),
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                    items: const [
                      DropdownMenuItem(
                        value: CourtMode.singles,
                        child: Text(
                          'Đánh Đơn 2 Người (Singles - Mặc định, Biên 5.18m)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: CourtMode.doubles,
                        child: Text(
                          'Đánh Đôi 4 Người (Doubles - Chuẩn BWF 6.10m)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) _onModeChanged(val);
                    },
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 2. Tên người chơi (--player-names)
              _buildParamLabel('Tên người chơi (', '--player-names', ')'),
              const SizedBox(height: 8),
              TextField(
                controller: _playerNamesController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                onChanged: (_) => _initPlayers(_effectiveVideoSize),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: HawkEyeTheme.surfaceInput,
                  hintText: 'Người chơi 1, Người chơi 2',
                  hintStyle: const TextStyle(color: HawkEyeTheme.textMuted),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: HawkEyeTheme.borderSubtle),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: HawkEyeTheme.accentBlue, width: 1.4),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Cách nhau bằng dấu phẩy (Sân xa trước, Sân gần sau).',
                style: TextStyle(color: HawkEyeTheme.textMuted, fontSize: 11.5),
              ),

              const SizedBox(height: 16),

              // 3. Góc sân bị khuất ngoài khung hình (--occluded-corner)
              _buildParamLabel('Góc sân bị khuất ngoài khung hình (', '--occluded-corner', ')'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: HawkEyeTheme.surfaceInput,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: HawkEyeTheme.borderSubtle),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _occludedCorner,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF16202E),
                    icon: const Icon(Icons.keyboard_arrow_down, color: HawkEyeTheme.textSecondary),
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                    items: const [
                      DropdownMenuItem(
                        value: 'none',
                        child: Text(
                          'Không khuất (Đủ 4 góc sân trong hình)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'bl',
                        child: Text(
                          'Khuất góc Dưới-Trái (Bottom-Left)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'br',
                        child: Text(
                          'Khuất góc Dưới-Phải (Bottom-Right)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'bottom_both',
                        child: Text(
                          'Khuất cả 2 góc dưới (Near Baseline)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'auto',
                        child: Text(
                          'Tự động nội suy bằng AI (Auto Extrapolate)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _occludedCorner = val);
                        _applyOccludedCornerExtrapolation();
                      }
                    },
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // 4. Độ nhạy bắt cầu (--shuttle-sensitivity) - Smooth Slider (0.5 .. 2.4)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: _buildParamLabel('Độ nhạy bắt cầu (', '--shuttle-sensitivity', ')'),
                  ),
                  Text(
                    _shuttleSensitivity.toStringAsFixed(1),
                    style: const TextStyle(
                      color: HawkEyeTheme.accentBlue,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              RepaintBoundary(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: HawkEyeTheme.accentBlue,
                    inactiveTrackColor: const Color(0xFF2E3846),
                    thumbColor: HawkEyeTheme.accentBlue,
                    overlayColor: HawkEyeTheme.accentBlue.withAlpha(40),
                    trackHeight: 5.0,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9.0),
                  ),
                  child: Slider(
                    value: _shuttleSensitivity.clamp(0.5, 2.4),
                    min: 0.5,
                    max: 2.4,
                    divisions: 19,
                    onChangeStart: (_) => FocusScope.of(context).unfocus(),
                    onChanged: (val) {
                      setState(() {
                        _shuttleSensitivity = double.parse(val.toStringAsFixed(1));
                      });
                    },
                  ),
                ),
              ),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('0.5 (Sân sáng rõ)', style: TextStyle(color: HawkEyeTheme.textMuted, fontSize: 11)),
                  Text('1.2 (Mặc định)', style: TextStyle(color: HawkEyeTheme.textMuted, fontSize: 11)),
                  Text('2.4 (Sân tối / Cầu mờ)', style: TextStyle(color: HawkEyeTheme.textMuted, fontSize: 11)),
                ],
              ),

              const SizedBox(height: 20),

              // 5. Hệ số hiệu chuẩn đo tốc độ cầu (--speed-calib) - Smooth Slider (0.6x .. 1.6x)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: _buildParamLabel('Hệ số hiệu chuẩn đo tốc độ cầu (', '--speed-calib', ')'),
                  ),
                  Text(
                    '${_speedCalib.toStringAsFixed(1)}x',
                    style: const TextStyle(
                      color: HawkEyeTheme.sliderAmber,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              RepaintBoundary(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: HawkEyeTheme.sliderAmber,
                    inactiveTrackColor: const Color(0xFF2E3846),
                    thumbColor: HawkEyeTheme.sliderAmber,
                    overlayColor: HawkEyeTheme.sliderAmber.withAlpha(40),
                    trackHeight: 5.0,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9.0),
                  ),
                  child: Slider(
                    value: _speedCalib.clamp(0.6, 1.6),
                    min: 0.6,
                    max: 1.6,
                    divisions: 10,
                    onChangeStart: (_) => FocusScope.of(context).unfocus(),
                    onChanged: (val) {
                      setState(() {
                        _speedCalib = double.parse(val.toStringAsFixed(1));
                      });
                    },
                  ),
                ),
              ),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('0.6x (Góc máy\nthấp)', style: TextStyle(color: HawkEyeTheme.textMuted, fontSize: 11)),
                  Text('1.0x (Chuẩn BWF\n3D)', style: TextStyle(color: HawkEyeTheme.textMuted, fontSize: 11)),
                  Text('1.6x (Góc máy\ncao/xa)', style: TextStyle(color: HawkEyeTheme.textMuted, fontSize: 11)),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(color: Color(0xFF1E293B), height: 1),
              const SizedBox(height: 10),

              // Checkboxes matching screenshot style
              _buildPurpleCheckboxRow(
                value: _autoDetectCorners,
                label: 'Tự động nhận diện 4 góc sân bằng AI khi tải video',
                onChanged: (v) => setState(() => _autoDetectCorners = v ?? true),
              ),
              _buildPurpleCheckboxRow(
                value: _showShuttleSpeed,
                label: 'Bật hiển thị tốc độ cầu trực tiếp (km/h) & Vệt cầu Parabol',
                onChanged: (v) => setState(() => _showShuttleSpeed = v ?? true),
              ),
              _buildPurpleCheckboxRow(
                value: _preserveAspectRatio,
                label: 'Giữ nguyên tỉ lệ khung hình video gốc (Không bị bóp méo)',
                onChanged: (v) => setState(() => _preserveAspectRatio = v ?? true),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepCircle(String number) {
    return Container(
      width: 26,
      height: 26,
      decoration: const BoxDecoration(
        color: Color(0xFF064E3B),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        number,
        style: const TextStyle(
          color: Color(0xFF34D399),
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildParamLabel(String prefix, String flag, String suffix) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          color: Color(0xFFCBD5E1),
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
        children: [
          TextSpan(text: prefix),
          TextSpan(
            text: flag,
            style: const TextStyle(
              color: Color(0xFF38BDF8),
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: suffix),
        ],
      ),
    );
  }

  Widget _buildPurpleCheckboxRow({
    required bool value,
    required String label,
    required ValueChanged<bool?> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: value,
                onChanged: onChanged,
                activeColor: HawkEyeTheme.checkboxPurple,
                checkColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// TAB 2: Interactive 4-Corner BWF Court Calibration ("Chấm góc sân BWF • Ảnh Mờ Chấm Góc")
  Widget _buildTab2CornerCalibration() {
    final bool hasVideo = _videoController != null && _videoController!.value.isInitialized;
    final Size vSize = _effectiveVideoSize;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: HawkEyeTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: const Row(
              children: [
                Icon(Icons.ads_click, color: HawkEyeTheme.accentBlue, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Chạm và kéo 4 điểm góc sân (TL, TR, BR, BL) để hiệu chuẩn ma trận Homography BWF 13.4m × 6.1m. Kính lúp phóng đại tự động bật khi kéo.',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF05080F),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: HawkEyeTheme.borderSubtle),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
                  final fitted = applyBoxFit(BoxFit.contain, vSize, canvasSize);
                  final dstRect = Alignment.center.inscribe(
                    fitted.destination,
                    Offset.zero & canvasSize,
                  );

                  Offset videoToScreen(Offset vPt) {
                    return Offset(
                      dstRect.left + (vPt.dx / vSize.width) * dstRect.width,
                      dstRect.top + (vPt.dy / vSize.height) * dstRect.height,
                    );
                  }

                  Offset screenToVideo(Offset sPt) {
                    final vx = ((sPt.dx - dstRect.left) / dstRect.width) * vSize.width;
                    final vy = ((sPt.dy - dstRect.top) / dstRect.height) * vSize.height;
                    return Offset(
                      vx.clamp(0.0, vSize.width),
                      vy.clamp(0.0, vSize.height),
                    );
                  }

                  return GestureDetector(
                    onPanStart: (details) {
                      final local = details.localPosition;
                      int bestIdx = -1;
                      double bestDist = 42.0;
                      for (int i = 0; i < _court.corners.length; i++) {
                        final sc = videoToScreen(_court.corners[i]);
                        final d = (sc - local).distance;
                        if (d < bestDist) {
                          bestDist = d;
                          bestIdx = i;
                        }
                      }
                      if (bestIdx != -1) {
                        setState(() {
                          _activeDraggingCornerIndex = bestIdx;
                          _activeDragCanvasPos = local;
                        });
                      }
                    },
                    onPanUpdate: (details) {
                      if (_activeDraggingCornerIndex == null) return;
                      final idx = _activeDraggingCornerIndex!;
                      final newVideoPt = screenToVideo(details.localPosition);
                      final updated = List<Offset>.from(_court.corners);
                      updated[idx] = newVideoPt;
                      setState(() {
                        _activeDragCanvasPos = details.localPosition;
                        _court = _court.copyWithCorners(updated);
                        _initPlayers(vSize);
                      });
                    },
                    onPanEnd: (_) {
                      setState(() {
                        _activeDraggingCornerIndex = null;
                        _activeDragCanvasPos = null;
                      });
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (hasVideo)
                          Center(
                            child: AspectRatio(
                              aspectRatio: _videoController!.value.aspectRatio,
                              child: VideoPlayer(_videoController!),
                            ),
                          ),
                        CustomPaint(
                          painter: _CornerCalibrationPainter(
                            cornersScreen: _court.corners.map(videoToScreen).toList(),
                            activeCornerIndex: _activeDraggingCornerIndex,
                            dragPos: _activeDragCanvasPos,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.spaceBetween,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _court = CourtModel.initial(_court.mode, videoSize: vSize);
                    _initPlayers(vSize);
                  });
                },
                icon: const Icon(Icons.auto_fix_high, size: 17, color: HawkEyeTheme.accentBlue),
                label: const Text(
                  'AI Tự Nhận Diện 4 Góc',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  side: const BorderSide(color: Color(0xFF334155)),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _runAnalysisNow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: HawkEyeTheme.runGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                ),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text(
                  'Áp Dụng & Xem Phân Tích →',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// TAB 3: Exact Broadcast Split-Screen Analyzer & Video Download/Export
  /// Matches reference video v1c044g50000dbiq5e7og65sqi867lkg.mp4
  Widget _buildTab3BroadcastAnalyzeAndExport() {
    final bool hasVideo = _videoController != null && _videoController!.value.isInitialized;
    final Size videoSize = _effectiveVideoSize;
    final bool isPlaying = hasVideo
        ? _videoController!.value.isPlaying
        : (_demoSimulationTimer?.isActive ?? false);

    final Duration currentPos = hasVideo
        ? _videoController!.value.position
        : Duration(milliseconds: (_demoElapsedSeconds * 1000).toInt());
    final Duration totalDur = hasVideo && _videoController!.value.duration.inMilliseconds > 0
        ? _videoController!.value.duration
        : const Duration(seconds: 22);

    final double maxMs = math.max(1.0, totalDur.inMilliseconds.toDouble());
    final double curMs = (_seekingValueMs ?? currentPos.inMilliseconds.toDouble()).clamp(0.0, maxMs);

    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 24),
      children: [
        // 1. EXACT BROADCAST SPLIT-SCREEN VIEWPORT (976:576)
        Container(
          decoration: BoxDecoration(
            color: HawkEyeTheme.panelBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF1E293B), width: 1.0),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: AspectRatio(
            aspectRatio: 976.0 / 576.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // A. Top 5-Column Telemetry Banner (Full Width)
                StatsHudWidget(stats: _rallyStats, shuttlecock: _shuttlecock),

                // B. Main Split Area: Left (75%: Video Viewport + Bottom 4-Player Cards) | Right (25%: Full-Height COURT MAP)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // LEFT 75% COLUMN: Video Viewport + Bottom 4-Player Distance Cards
                      Expanded(
                        flex: 75,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Video Viewport (Preserves native aspect ratio via BoxFit.contain - never stretched!)
                            Expanded(
                              child: Container(
                                color: const Color(0xFF0A0E16),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (hasVideo)
                                      Center(
                                        child: AspectRatio(
                                          aspectRatio: _videoController!.value.aspectRatio,
                                          child: VideoPlayer(_videoController!),
                                        ),
                                      )
                                    else
                                      Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.sports_tennis,
                                              size: 32,
                                              color: HawkEyeTheme.playerCuong,
                                            ),
                                            const SizedBox(height: 6),
                                            const Text(
                                              'CHẾ ĐỘ MÔ PHỎNG BROADCAST HAWK-EYE',
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            OutlinedButton.icon(
                                              onPressed: _handlePickVideo,
                                              icon: const Icon(Icons.folder_open, size: 14),
                                              label: const Text(
                                                'Chọn Video Thật',
                                                style: TextStyle(fontSize: 10.5),
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: HawkEyeTheme.accentBlue,
                                                side: const BorderSide(color: HawkEyeTheme.accentBlue),
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 4,
                                                ),
                                                minimumSize: Size.zero,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                    // AR HUD Overlay (Rings, Badges, Parabolic Shuttle Arc) fitted inside Video Viewport
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: CustomPaint(
                                          painter: HawkEyePainter(
                                            court: _court,
                                            players: _players,
                                            shuttlecock: _shuttlecock,
                                            rallyStats: _rallyStats,
                                            originalVideoSize: videoSize,
                                            drawCourtGrid: !hasVideo,
                                            showShuttleSpeed: _showShuttleSpeed,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // Bottom 4-Player Distance Cards (Directly under Video Viewport)
                            ControlPanelWidget(players: _players),
                          ],
                        ),
                      ),

                      // RIGHT 25% COLUMN: Dedicated Full-Height 2D COURT MAP
                      Expanded(
                        flex: 25,
                        child: MiniCourtWidget(
                          court: _court,
                          players: _players,
                          shuttlecock: _shuttlecock,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // 2. SMOOTH PLAYBACK & TIMELINE SEEK BAR
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: HawkEyeTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1E293B)),
          ),
          child: Row(
            children: [
              IconButton(
                iconSize: 22,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.skip_previous, color: Colors.white70),
                onPressed: () => _stepFrame(-1),
                tooltip: 'Lùi 1 frame',
              ),
              IconButton(
                iconSize: 28,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(
                  isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                  color: HawkEyeTheme.runGreen,
                ),
                onPressed: _togglePlayPause,
              ),
              IconButton(
                iconSize: 22,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.skip_next, color: Colors.white70),
                onPressed: () => _stepFrame(1),
                tooltip: 'Tiến 1 frame',
              ),
              const SizedBox(width: 6),
              Expanded(
                child: RepaintBoundary(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: HawkEyeTheme.accentBlue,
                      inactiveTrackColor: const Color(0xFF2E3846),
                      thumbColor: HawkEyeTheme.accentBlue,
                      trackHeight: 4.0,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.0),
                    ),
                    child: Slider(
                      value: curMs,
                      min: 0.0,
                      max: maxMs,
                      onChanged: (val) {
                        setState(() => _seekingValueMs = val);
                        _seekThrottler.run(() {
                          if (hasVideo) {
                            _videoController!.seekTo(Duration(milliseconds: val.toInt()));
                          } else {
                            _demoElapsedSeconds = val / 1000.0;
                            _updateTelemetryAtTime(_demoElapsedSeconds, videoSize);
                          }
                        });
                      },
                      onChangeEnd: (val) {
                        setState(() => _seekingValueMs = null);
                        if (hasVideo) {
                          _videoController!.seekTo(Duration(milliseconds: val.toInt()));
                        } else {
                          _demoElapsedSeconds = val / 1000.0;
                          _updateTelemetryAtTime(_demoElapsedSeconds, videoSize);
                        }
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${(curMs / 1000.0).toStringAsFixed(1)}s',
                style: const TextStyle(
                  color: HawkEyeTheme.textSecondary,
                  fontSize: 11.5,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // 3. VIDEO DOWNLOAD & EXPORT PANEL
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: HawkEyeTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1E293B)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.download_for_offline_outlined, color: HawkEyeTheme.runGreen, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tải Xuống & Xuất Video Đã Xử Lý (Chuẩn Broadcast 976×576)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Video tải xuống giữ nguyên tỉ lệ khung hình gốc bên trái, kèm thanh HUD 5 cột phía trên, 4 thẻ cầu thủ phía dưới và bản đồ sân 2D COURT MAP bên phải.',
                style: TextStyle(color: HawkEyeTheme.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: _isExporting ? null : () => _executeVideoExport('gallery'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: HawkEyeTheme.runGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.file_download_outlined, size: 20),
                label: const Text(
                  'Tải Xuống Video MP4 (Lưu vào Bộ Sưu Tập / Gallery)',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isExporting ? null : () => _executeVideoExport('save_as'),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E293B),
                        side: const BorderSide(color: Color(0xFF334155)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.save_alt, size: 17, color: HawkEyeTheme.accentBlue),
                      label: const Text(
                        'Lưu Thành File...',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isExporting ? null : () => _executeVideoExport('share'),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E293B),
                        side: const BorderSide(color: Color(0xFF334155)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.share_outlined, size: 17, color: HawkEyeTheme.sliderAmber),
                      label: const Text(
                        'Chia Sẻ Video',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CornerCalibrationPainter extends CustomPainter {
  final List<Offset> cornersScreen;
  final int? activeCornerIndex;
  final Offset? dragPos;

  _CornerCalibrationPainter({
    required this.cornersScreen,
    this.activeCornerIndex,
    this.dragPos,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (cornersScreen.length != 4) return;

    final Path poly = Path()
      ..moveTo(cornersScreen[0].dx, cornersScreen[0].dy)
      ..lineTo(cornersScreen[1].dx, cornersScreen[1].dy)
      ..lineTo(cornersScreen[2].dx, cornersScreen[2].dy)
      ..lineTo(cornersScreen[3].dx, cornersScreen[3].dy)
      ..close();

    canvas.drawPath(
      poly,
      Paint()
        ..color = const Color(0x4410B981)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      poly,
      Paint()
        ..color = HawkEyeTheme.runGreen
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );

    // Net line
    final netL = Offset.lerp(cornersScreen[0], cornersScreen[3], 0.5)!;
    final netR = Offset.lerp(cornersScreen[1], cornersScreen[2], 0.5)!;
    canvas.drawLine(
      netL,
      netR,
      Paint()
        ..color = Colors.white70
        ..strokeWidth = 1.5,
    );

    const labels = ['1. TL (Xa-Trái)', '2. TR (Xa-Phải)', '3. BR (Gần-Phải)', '4. BL (Gần-Trái)'];
    for (int i = 0; i < 4; i++) {
      final pt = cornersScreen[i];
      final bool isActive = activeCornerIndex == i;
      canvas.drawCircle(
        pt,
        isActive ? 13.0 : 9.0,
        Paint()..color = isActive ? HawkEyeTheme.sliderAmber : HawkEyeTheme.accentBlue,
      );
      canvas.drawCircle(
        pt,
        isActive ? 13.0 : 9.0,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10.5,
            fontWeight: FontWeight.bold,
            backgroundColor: Color(0xAA000000),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(pt.dx - tp.width / 2, pt.dy - 24));
    }

    // Draw zoomed crosshair loupe ("Ảnh Mờ Chấm Góc") when dragging a corner
    if (activeCornerIndex != null && dragPos != null) {
      const double loupeRadius = 42.0;
      final Offset loupeCenter = Offset(
        (dragPos!.dx).clamp(loupeRadius + 10, size.width - loupeRadius - 10),
        math.max(loupeRadius + 10, dragPos!.dy - 70),
      );

      canvas.drawCircle(loupeCenter, loupeRadius, Paint()..color = const Color(0xE60B111A));
      canvas.drawCircle(
        loupeCenter,
        loupeRadius,
        Paint()
          ..color = HawkEyeTheme.sliderAmber
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
      canvas.drawLine(
        Offset(loupeCenter.dx - 18, loupeCenter.dy),
        Offset(loupeCenter.dx + 18, loupeCenter.dy),
        Paint()
          ..color = HawkEyeTheme.runGreen
          ..strokeWidth = 1.5,
      );
      canvas.drawLine(
        Offset(loupeCenter.dx, loupeCenter.dy - 18),
        Offset(loupeCenter.dx, loupeCenter.dy + 18),
        Paint()
          ..color = HawkEyeTheme.runGreen
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CornerCalibrationPainter oldDelegate) => true;
}
