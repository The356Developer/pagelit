import 'dart:ui';

/// Physical display / monitor descriptor reported by the OS.
class DisplayInfo {
  const DisplayInfo({
    required this.id,
    required this.name,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.workLeft,
    required this.workTop,
    required this.workWidth,
    required this.workHeight,
    required this.scaleFactor,
    required this.isPrimary,
  });

  final String id;
  final String name;

  /// Physical pixel coordinates of the full monitor bounds (`rcMonitor`).
  final int left;
  final int top;
  final int width;
  final int height;

  /// Physical pixel coordinates of the work area excluding taskbar (`rcWork`).
  final int workLeft;
  final int workTop;
  final int workWidth;
  final int workHeight;

  final double scaleFactor;
  final bool isPrimary;

  Rect get bounds => Rect.fromLTWH(
        left.toDouble(),
        top.toDouble(),
        width.toDouble(),
        height.toDouble(),
      );

  String get resolutionLabel => '${width}x$height';

  factory DisplayInfo.fromMap(Map<Object?, Object?> map) {
    final width = (map['width'] as num?)?.toInt() ?? 1920;
    final height = (map['height'] as num?)?.toInt() ?? 1080;
    final left = (map['left'] as num?)?.toInt() ?? 0;
    final top = (map['top'] as num?)?.toInt() ?? 0;
    return DisplayInfo(
      id: (map['id'] as String?) ?? 'display_0',
      name: (map['name'] as String?) ?? 'Display',
      left: left,
      top: top,
      width: width,
      height: height,
      workLeft: (map['workLeft'] as num?)?.toInt() ?? left,
      workTop: (map['workTop'] as num?)?.toInt() ?? top,
      workWidth: (map['workWidth'] as num?)?.toInt() ?? width,
      workHeight: (map['workHeight'] as num?)?.toInt() ?? height,
      scaleFactor: (map['scaleFactor'] as num?)?.toDouble() ?? 1.0,
      isPrimary: (map['isPrimary'] as bool?) ?? true,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'left': left,
        'top': top,
        'width': width,
        'height': height,
        'workLeft': workLeft,
        'workTop': workTop,
        'workWidth': workWidth,
        'workHeight': workHeight,
        'scaleFactor': scaleFactor,
        'isPrimary': isPrimary,
      };
}
