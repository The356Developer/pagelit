import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'encoding_utils.dart';

/// A document found on the device — either through "All files access" or inside a
/// folder the user picked with the system folder picker.
class DevicePdf {
  const DevicePdf({
    required this.name,
    required this.size,
    required this.modified,
    this.path,
    this.uri,
  });

  final String name;
  final int size;
  final DateTime modified;

  /// A path Dart can read directly (only available with "All files access").
  final String? path;

  /// A `content://` URI, copied into the cache when the document is opened.
  final String? uri;

  /// Stable identity for list keys and de-duplication.
  String get id => path ?? uri ?? name;

  factory DevicePdf.fromMap(Map<Object?, Object?> map) {
    final milliseconds = (map['modified'] as num?)?.toInt() ?? 0;
    final rawName = map['name'] as String? ?? 'document';
    return DevicePdf(
      name: EncodingUtils.cleanDisplayName(rawName),
      size: (map['size'] as num?)?.toInt() ?? 0,
      modified: DateTime.fromMillisecondsSinceEpoch(milliseconds),
      path: map['path'] as String?,
      uri: map['uri'] as String?,
    );
  }
}

/// Lists documents stored on the device, newest first.
///
/// Supports PDF, Word (.docx, .doc), Excel (.xlsx, .xls), and PowerPoint (.pptx, .ppt).
class DevicePdfLibrary {
  const DevicePdfLibrary._();

  static const _channel = MethodChannel('pagelit/device_pdfs');
  static const _foldersKey = 'device_pdf_folders';
  static const _supportedExtensions = {
    '.pdf',
    '.docx',
    '.doc',
    '.pptx',
    '.ppt',
    '.xlsx',
    '.xls',
  };

  static bool get _isDesktop =>
      !Platform.environment.containsKey('FLUTTER_TEST') &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// Whether "All files access" is granted (Android 11+ only; always true on desktop).
  static Future<bool> hasAllFilesAccess() async {
    if (_isDesktop) return true;
    try {
      return await _channel.invokeMethod<bool>('hasAllFilesAccess') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens the system screen where "All files access" can be granted.
  static Future<bool> requestAllFilesAccess() async {
    if (_isDesktop) return true;
    try {
      return await _channel.invokeMethod<bool>('requestAllFilesAccess') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Folders the user added, as persisted tree URIs or filesystem paths.
  static Future<List<String>> loadFolders() async {
    final prefs = await SharedPreferences.getInstance();
    return List<String>.of(prefs.getStringList(_foldersKey) ?? const []);
  }

  /// Shows the system folder picker and stores the chosen folder.
  static Future<List<String>> addFolder() async {
    String? uri;
    if (_isDesktop) {
      uri = await FilePicker.getDirectoryPath();
    } else {
      try {
        uri = await _channel.invokeMethod<String>('pickFolder');
      } on PlatformException {
        uri = null;
      } on MissingPluginException {
        uri = null;
      }
    }
    final folders = await loadFolders();
    if (uri == null || uri.isEmpty || folders.contains(uri)) return folders;
    folders.add(uri);
    await _saveFolders(folders);
    return folders;
  }

  /// Forgets a folder and drops its persisted read permission.
  static Future<List<String>> removeFolder(String uri) async {
    final folders = await loadFolders()
      ..remove(uri);
    await _saveFolders(folders);
    try {
      await _channel.invokeMethod<bool>('releaseFolder', {'uri': uri});
    } on PlatformException {
      // The permission may already be gone: nothing to clean up.
    } on MissingPluginException {
      // Running outside Android.
    }
    return folders;
  }

  /// Every document inside [folders], plus all device documents when access is granted.
  static Future<List<DevicePdf>> listPdfs(List<String> folders) async {
    if (_isDesktop) {
      return _listDesktopDocuments(folders);
    }
    List<Object?>? raw;
    try {
      raw = await _channel.invokeMethod<List<Object?>>('listPdfs', {
        'folders': folders,
      });
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
    if (raw == null) return const [];
    final pdfs =
        raw.whereType<Map<Object?, Object?>>().map(DevicePdf.fromMap).toList()
          ..sort((a, b) => b.modified.compareTo(a.modified));
    return pdfs;
  }

  static const _ignoredDesktopDirNames = {
    'node_modules',
    'appdata',
    'build',
    'windows',
    'program files',
    'program files (x86)',
    '\$recycle.bin',
    'system volume information',
  };

  /// Returns `true` when [bytes] starts with the OLE2 Compound Document magic
  /// header used by legacy Office 97–2003 binary files (`.ppt`, `.doc`, `.xls`).
  static bool isLegacyOleBinary(List<int> bytes) {
    if (bytes.length < 8) return false;
    return bytes[0] == 0xD0 &&
        bytes[1] == 0xCF &&
        bytes[2] == 0x11 &&
        bytes[3] == 0xE0 &&
        bytes[4] == 0xA1 &&
        bytes[5] == 0xB1 &&
        bytes[6] == 0x1A &&
        bytes[7] == 0xE1;
  }

  static Future<List<DevicePdf>> _listDesktopDocuments(
    List<String> folders,
  ) async {
    final searchRoots = <String>{...folders};
    if (searchRoots.isEmpty) {
      try {
        final downloads = await getDownloadsDirectory();
        if (downloads != null && downloads.existsSync()) {
          searchRoots.add(downloads.path);
        }
      } catch (_) {}
      try {
        final docs = await getApplicationDocumentsDirectory();
        if (docs.existsSync()) {
          searchRoots.add(docs.path);
        }
      } catch (_) {}
    }

    final seen = <String>{};
    final results = <DevicePdf>[];
    for (final root in searchRoots) {
      await _scanDesktopDirectory(
        Directory(root),
        depth: 0,
        maxDepth: 4,
        seen: seen,
        results: results,
      );
    }
    results.sort((a, b) => b.modified.compareTo(a.modified));
    return results;
  }

  static Future<void> _scanDesktopDirectory(
    Directory dir, {
    required int depth,
    required int maxDepth,
    required Set<String> seen,
    required List<DevicePdf> results,
  }) async {
    try {
      if (!dir.existsSync()) return;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is Directory) {
          if (depth >= maxDepth) continue;
          final dirName =
              entity.path.split(Platform.pathSeparator).last.toLowerCase();
          if (dirName.isEmpty ||
              dirName.startsWith('.') ||
              _ignoredDesktopDirNames.contains(dirName)) {
            continue;
          }
          await _scanDesktopDirectory(
            entity,
            depth: depth + 1,
            maxDepth: maxDepth,
            seen: seen,
            results: results,
          );
          continue;
        }
        if (entity is! File) continue;
        final filePath = entity.path;
        final sep = Platform.pathSeparator;
        final rawName = filePath.split(sep).last;
        if (rawName.startsWith('~\$') || rawName.startsWith('.')) continue;

        final lower = rawName.toLowerCase();
        final dot = lower.lastIndexOf('.');
        if (dot == -1) continue;
        if (!_supportedExtensions.contains(lower.substring(dot))) continue;
        if (!seen.add(filePath)) continue;
        try {
          final stat = await entity.stat();
          results.add(
            DevicePdf(
              name: EncodingUtils.cleanDisplayName(rawName),
              size: stat.size,
              modified: stat.modified,
              path: filePath,
            ),
          );
        } catch (_) {
          // Skip unreadable files.
        }
      }
    } catch (_) {
      // Skip folders without read permission.
    }
  }

  /// A path the reader can open for [pdf].
  static Future<String?> openPath(DevicePdf pdf) async {
    final path = pdf.path;
    if (path != null && path.isNotEmpty) return path;
    final uri = pdf.uri;
    if (uri == null) return null;
    try {
      return await _channel.invokeMethod<String>('resolvePdf', {'uri': uri});
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Gets the total size of cached shared documents in bytes.
  static Future<int> getCacheSize() async {
    try {
      return await _channel.invokeMethod<int>('getCacheSize') ?? 0;
    } on PlatformException {
      return 0;
    } on MissingPluginException {
      return 0;
    }
  }

  /// Clears the cached shared documents folder.
  static Future<bool> clearCache() async {
    try {
      return await _channel.invokeMethod<bool>('clearCache') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Prints a document file using the system print spooler.
  static Future<bool> printFile(String path) async {
    try {
      return await _channel.invokeMethod<bool>('printFile', {'path': path}) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> _saveFolders(List<String> folders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_foldersKey, folders);
  }
}
