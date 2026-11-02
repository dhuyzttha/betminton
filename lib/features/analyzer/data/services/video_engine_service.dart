import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../domain/models/court_model.dart';

class VideoEngineService {
  String serverUrl;

  VideoEngineService({this.serverUrl = "http://10.0.2.2:8000"});

  Future<bool> checkServerHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$serverUrl/'))
          .timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> uploadAndAnalyze({
    required File videoFile,
    required CourtMode mode,
    String playerNames = "Tú, Cường, Nam, Thành",
    String occludedCorner = "none",
    double sensitivity = 1.2,
    double speedCalib = 1.0,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$serverUrl/api/analyze_video'),
      );

      final parts = playerNames
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      request.fields['mode'] = mode == CourtMode.singles ? 'singles' : 'doubles';
      request.fields['player_names'] = playerNames;
      request.fields['player1'] = parts.isNotEmpty ? parts[0] : 'Tú';
      request.fields['player2'] = parts.length > 1 ? parts[1] : 'Cường';
      request.fields['player3'] = parts.length > 2 ? parts[2] : 'Nam';
      request.fields['player4'] = parts.length > 3 ? parts[3] : 'Thành';
      request.fields['occluded_corner'] = occludedCorner;
      request.fields['sensitivity'] = sensitivity.toString();
      request.fields['speed_calib'] = speedCalib.toString();

      request.files.add(await http.MultipartFile.fromPath('file', videoFile.path));

      final streamedResponse = await request.send().timeout(const Duration(minutes: 3));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        debugPrint('Server analysis failed with status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Network exception connecting to CV engine: $e');
      return null;
    }
  }

  Future<File?> downloadProcessedVideo({
    required String videoUrlPath,
    required String targetFilePath,
  }) async {
    try {
      final fullUrl = videoUrlPath.startsWith('http')
          ? videoUrlPath
          : '$serverUrl${videoUrlPath.startsWith('/') ? '' : '/'}$videoUrlPath';

      final response = await http
          .get(Uri.parse(fullUrl))
          .timeout(const Duration(minutes: 2));

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        final outFile = File(targetFilePath);
        await outFile.writeAsBytes(response.bodyBytes, flush: true);
        return outFile;
      }
      return null;
    } catch (e) {
      debugPrint('Failed to download processed video: $e');
      return null;
    }
  }
}
