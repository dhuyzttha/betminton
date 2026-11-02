import 'dart:ui';
import 'package:flutter/material.dart';

class PlayerModel {
  final int id;
  final String name;
  final String team; // "Đội bạn" or "Đội mình"
  final String side; // "bottom" (near court) or "top" (far court)
  final Color color;
  final Rect? bbox;
  final Offset? footPx;
  final Offset? footBwf; // in meters (X: 0..6.10, Y: 0..13.40)
  final double totalDistanceMeters; // "cả trận"
  final double rallyDistanceMeters; // "pha này"
  final List<Offset> historyBwf;

  PlayerModel({
    required this.id,
    required this.name,
    required this.team,
    required this.side,
    required this.color,
    this.bbox,
    this.footPx,
    this.footBwf,
    this.totalDistanceMeters = 0.0,
    this.rallyDistanceMeters = 0.0,
    this.historyBwf = const [],
  });

  PlayerModel copyWith({
    Rect? bbox,
    Offset? footPx,
    Offset? footBwf,
    double? totalDistanceMeters,
    double? rallyDistanceMeters,
    List<Offset>? historyBwf,
  }) {
    return PlayerModel(
      id: id,
      name: name,
      team: team,
      side: side,
      color: color,
      bbox: bbox ?? this.bbox,
      footPx: footPx ?? this.footPx,
      footBwf: footBwf ?? this.footBwf,
      totalDistanceMeters: totalDistanceMeters ?? this.totalDistanceMeters,
      rallyDistanceMeters: rallyDistanceMeters ?? this.rallyDistanceMeters,
      historyBwf: historyBwf ?? this.historyBwf,
    );
  }
}
