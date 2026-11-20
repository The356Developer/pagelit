import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'encoding_utils.dart';

/// Origin of a detected or extracted Table of Contents entry.
enum PdfTocSource {
  embeddedBookmarks,
  detectedTocPage,
  detectedHeadings,
  slideTitles,
}

/// A hierarchical entry in a PDF's Table of Contents / Chapter list.
class PdfTocEntry {
  const PdfTocEntry({
    required this.title,
    this.pageNumber,
    this.level = 0,
    this.children = const [],
    this.bookmark,
    required this.source,
  });

  final String title;

  /// 1-based PDF page number, or `null` if unknown.
  final int? pageNumber;

  /// Nesting depth (`0` = top chapter, `1` = section, `2` = subsection).
  final int level;

  final List<PdfTocEntry> children;

  /// Live bookmark reference when extracted on the main isolate via Tier 1.
  /// Always `null` for isolate-extracted entries (Tier 2 & Tier 3).
  final PdfBookmark? bookmark;

  final PdfTocSource source;

  PdfTocEntry copyWith({
    String? title,
    int? pageNumber,
    int? level,
    List<PdfTocEntry>? children,
    PdfBookmark? bookmark,
    PdfTocSource? source,
  }) {
    return PdfTocEntry(
      title: title ?? this.title,
      pageNumber: pageNumber ?? this.pageNumber,
      level: level ?? this.level,
      children: children ?? this.children,
      bookmark: bookmark ?? this.bookmark,
      source: source ?? this.source,
    );
  }

  /// Flattens this subtree in pre-order for search and page lookup.
  List<PdfTocEntry> flatten() {
    final out = <PdfTocEntry>[this];
    for (final child in children) {
      out.addAll(child.flatten());
    }
    return out;
  }
}

/// Complete extraction result returned by [PdfTocExtractor].
class PdfTocResult {
  const PdfTocResult({
    required this.entries,
    this.source,
    this.tocPageNumber,
  });

  static const PdfTocResult empty = PdfTocResult(entries: []);

  final List<PdfTocEntry> entries;
  final PdfTocSource? source;
  final int? tocPageNumber;

  bool get isEmpty => entries.isEmpty;
  bool get isNotEmpty => entries.isNotEmpty;

  /// Returns all entries in reading order.
  List<PdfTocEntry> get flattened {
    final out = <PdfTocEntry>[];
    for (final entry in entries) {
      out.addAll(entry.flatten());
    }
    return out;
  }

  /// Distinct 1-based page numbers for top-level chapters (used by PageScrubber).
  List<int> get topLevelPages {
    final pages = <int>{};
    for (final entry in entries) {
      if (entry.pageNumber != null && entry.pageNumber! >= 1) {
        pages.add(entry.pageNumber!);
      }
    }
    final sorted = pages.toList()..sort();
    return sorted;
  }

  /// Returns the most specific chapter/section title active on [pageNumber].
  String? chapterTitleForPage(int pageNumber) {
    String? bestTitle;
    int bestPage = -1;
    int bestDepth = -1;

    for (final entry in flattened) {
      final p = entry.pageNumber;
      if (p == null || p > pageNumber) continue;
      if (p > bestPage || (p == bestPage && entry.level >= bestDepth)) {
        bestPage = p;
        bestDepth = entry.level;
        bestTitle = entry.title;
      }
    }
    return bestTitle;
  }
}

class _TocFileRequest {
  const _TocFileRequest(this.filePath, this.password);

  final String filePath;
  final String? password;
}

class _LineSegment {
  const _LineSegment({
    required this.text,
    required this.left,
    required this.right,
    required this.fontSize,
    required this.isBold,
  });

  final String text;
  final double left;
  final double right;
  final double fontSize;
  final bool isBold;
}

class _VisualLine {
  const _VisualLine({
    required this.text,
    required this.segments,
    required this.minLeft,
    required this.maxRight,
    required this.top,
    required this.bottom,
    required this.fontSize,
    required this.isBold,
  });

  final String text;
  final List<_LineSegment> segments;
  final double minLeft;
  final double maxRight;
  final double top;
  final double bottom;
  final double fontSize;
  final bool isBold;
}

class _RawTocCandidate {
  const _RawTocCandidate({
    required this.title,
    required this.pageNumber,
    required this.minLeft,
    required this.fontSize,
    required this.isBold,
  });

  final String title;
  final int pageNumber;
  final double minLeft;
  final double fontSize;
  final bool isBold;
}

class _HeadingCandidate {
  const _HeadingCandidate({
    required this.title,
    required this.pageNumber,
    required this.fontSize,
    required this.isBold,
    required this.top,
    required this.isExplicitChapter,
    required this.numericDepth,
  });

  final String title;
  final int pageNumber;
  final double fontSize;
  final bool isBold;
  final double top;
  final bool isExplicitChapter;
  final int? numericDepth;
}

/// Multi-tier smart PDF Table of Contents & Chapter detector:
/// - Tier 1: Embedded PDF outline bookmarks (with parent destination fallback)
/// - Tier 2: Printed TOC / Sommaire / Index pages (with front-matter offset calibration)
/// - Tier 3: Visual & structural heading scanner / landscape slide title detector
class PdfTocExtractor {
  const PdfTocExtractor._();

  static const int _maxTocScanFrontPages = 20;
  static const int _maxTocContinuationPages = 6;
  static const int _maxHeadingScanPages = 220;

  static final RegExp _boldFontNameRegex = RegExp(
    r'bold|demi|heavy|black|semibold|extrabold|medi',
    caseSensitive: false,
  );

  static final RegExp _arabicCharsRegex =
      RegExp(r'[\u0600-\u06FF\uFE70-\uFEFF]');

  static final RegExp _leaderRowRegex = RegExp(
    r'^(.+?)\s*[\.\·•_…\-]{2,}\s*([0-9٠-٩]{1,4})\s*$',
  );

  static final RegExp _spacedColumnRowRegex = RegExp(
    r'^(.+?)\s{2,}([0-9٠-٩]{1,4})\s*$',
  );

  static final RegExp _singleSpacedRowRegex = RegExp(
    r'^(.+?)\s+([0-9٠-٩]{1,4})\s*$',
  );

  static final RegExp _rtlLeadingPageRowRegex = RegExp(
    r'^([0-9٠-٩]{1,4})\s*(?:[\.\·•_…\-]{2,}|\s{2,})(.+?)\s*$',
  );

  static final RegExp _standaloneIntRegex = RegExp(r'^[0-9٠-٩]{1,4}$');

  static final RegExp _pureNumericOrPunctRegex = RegExp(
    r'^[\d٠-٩\s\.\-\–\—\(\)\[\]/:,•·]+$',
  );

  static final RegExp _urlOrEmailRegex = RegExp(
    r'^(?:https?://|www\.|\S+@\S+\.\S+)',
    caseSensitive: false,
  );

  static final RegExp _explicitChapterRegex = RegExp(
    r'^(?:\d+(?:\.\d+)*\s*[-:\.]?\s*)?(?:'
    r'chapter|chapitre|part|partie|unit|unite|module|section|lesson|lecon|'
    r'appendix|annexe|introduction|conclusion|abstract|summary|resume|'
    r'references|bibliography|bibliographie|preface|foreword|overview|glossary|'
    r'الفصل|الباب|الوحدة|الوحده|الدرس|المقدمة|المقدمه|الخاتمة|الخاتمه|المراجع'
    r')\b',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _numberedHeadingRegex = RegExp(
    r'^(?:(\d{1,2}(?:\.\d{1,2}){0,2})|([IVXLCDM]{1,5}))[\.\)\s:\-]+\p{L}',
    unicode: true,
  );

  static final RegExp _chapterPrefixLevelRegex = RegExp(
    r'^(?:chapter|chapitre|part|partie|unit|unite|module|الفصل|الباب|الوحدة)\b',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _subPrefixLevelRegex = RegExp(
    r'^(\d+(?:\.\d+)+)\b',
  );

  static final RegExp _topNumericPrefixRegex = RegExp(
    r'^(\d{1,2})\.(?!\d)',
  );

  /// Tier 1: Extracts embedded PDF outline bookmarks on the main isolate.
  static PdfTocResult extractFromBookmarks(PdfDocument document) {
    final rootBookmarks = document.bookmarks;
    if (rootBookmarks.count == 0) {
      return PdfTocResult.empty;
    }

    final entries = _walkBookmarks(rootBookmarks, document, level: 0);
    if (entries.isEmpty) {
      return PdfTocResult.empty;
    }

    return PdfTocResult(
      entries: entries,
      source: PdfTocSource.embeddedBookmarks,
    );
  }

  static List<PdfTocEntry> _walkBookmarks(
    PdfBookmarkBase parent,
    PdfDocument document, {
    required int level,
  }) {
    final result = <PdfTocEntry>[];
    final count = parent.count;
    for (int i = 0; i < count; i++) {
      final bm = parent[i];
      final rawTitle = EncodingUtils.cleanDisplayName(bm.title).trim();

      final children = bm.count > 0
          ? _walkBookmarks(bm, document, level: (level + 1).clamp(0, 2))
          : const <PdfTocEntry>[];

      if (rawTitle.isEmpty && children.isEmpty) {
        continue;
      }

      int? pageNumber = _resolveBookmarkPage(bm, document);
      if (pageNumber == null && children.isNotEmpty) {
        pageNumber = _firstResolvedPage(children);
      }

      final displayTitle = rawTitle.isNotEmpty
          ? rawTitle
          : (children.firstOrNull?.title ?? 'Section');

      result.add(
        PdfTocEntry(
          title: displayTitle,
          pageNumber: pageNumber,
          level: level,
          children: children,
          bookmark: bm,
          source: PdfTocSource.embeddedBookmarks,
        ),
      );
    }
    return result;
  }

  static int? _firstResolvedPage(List<PdfTocEntry> entries) {
    for (final entry in entries) {
      if (entry.pageNumber != null) return entry.pageNumber;
      final nested = _firstResolvedPage(entry.children);
      if (nested != null) return nested;
    }
    return null;
  }

  static int? _resolveBookmarkPage(PdfBookmark bm, PdfDocument document) {
    try {
      final dest = bm.destination ?? bm.namedDestination?.destination;
      if (dest == null) return null;
      final page = dest.page;
      final idx = document.pages.indexOf(page);
      if (idx >= 0) {
        return idx + 1;
      }
    } catch (_) {
      // Malformed PDF bookmark destination; fall back safely.
    }
    return null;
  }

  /// Runs Tier 2 & Tier 3 smart chapter detection in a background isolate.
  static Future<PdfTocResult> extractFromFile(
    String filePath, {
    String? password,
  }) {
    return compute(
      _extractFromFileIsolate,
      _TocFileRequest(filePath, password),
    );
  }

  static PdfTocResult _extractFromFileIsolate(_TocFileRequest req) {
    try {
      final file = File(req.filePath);
      if (!file.existsSync()) return PdfTocResult.empty;
      final bytes = file.readAsBytesSync();
      return _extractHeuristicFromBytesSync(bytes, password: req.password);
    } catch (_) {
      return PdfTocResult.empty;
    }
  }

  /// Synchronous full extraction from raw PDF bytes (safe in unit tests and isolates).
  /// When embedded bookmarks exist, returns Tier 1 entries (with `bookmark: null` so
  /// results remain sendable across isolates). Otherwise runs Tier 2 -> Tier 3.
  static PdfTocResult extractFromBytesSync(
    Uint8List bytes, {
    String? password,
  }) {
    if (bytes.isEmpty) return PdfTocResult.empty;
    PdfDocument? document;
    try {
      document = PdfDocument(inputBytes: bytes, password: password);
      if (document.bookmarks.count > 0) {
        final tier1 = extractFromBookmarks(document);
        if (tier1.isNotEmpty) {
          return PdfTocResult(
            entries: _stripBookmarks(tier1.entries),
            source: tier1.source,
          );
        }
      }
      return _extractHeuristicsFromLoadedDocument(document);
    } catch (_) {
      return PdfTocResult.empty;
    } finally {
      document?.dispose();
    }
  }

  static PdfTocResult _extractHeuristicFromBytesSync(
    Uint8List bytes, {
    String? password,
  }) {
    if (bytes.isEmpty) return PdfTocResult.empty;
    PdfDocument? document;
    try {
      document = PdfDocument(inputBytes: bytes, password: password);
      return _extractHeuristicsFromLoadedDocument(document);
    } catch (_) {
      return PdfTocResult.empty;
    } finally {
      document?.dispose();
    }
  }

  static List<PdfTocEntry> _stripBookmarks(List<PdfTocEntry> entries) {
    return [
      for (final e in entries)
        PdfTocEntry(
          title: e.title,
          pageNumber: e.pageNumber,
          level: e.level,
          children: _stripBookmarks(e.children),
          bookmark: null,
          source: e.source,
        ),
    ];
  }

  static PdfTocResult _extractHeuristicsFromLoadedDocument(
    PdfDocument document,
  ) {
    final pageCount = document.pages.count;
    if (pageCount == 0) return PdfTocResult.empty;

    final extractor = PdfTextExtractor(document);

    // Tier 2: Printed TOC page detection
    final tier2 = _detectPrintedToc(document, extractor);
    if (tier2.isNotEmpty) return tier2;

    // Tier 3: Visual & structural headings / slide titles
    return _detectVisualHeadings(document, extractor);
  }

  // ---------------------------------------------------------------------------
  // Visual Line Reconstruction
  // ---------------------------------------------------------------------------

  static List<_VisualLine> _extractVisualLinesForPage(
    PdfTextExtractor extractor,
    int pageIndex,
  ) {
    final rawLines = extractor.extractTextLines(
      startPageIndex: pageIndex,
      endPageIndex: pageIndex,
    );
    return _reconstructVisualLines(rawLines);
  }

  static List<_VisualLine> _reconstructVisualLines(List<TextLine> rawLines) {
    final segments = <({
      String text,
      Rect bounds,
      double fontSize,
      bool isBold,
    })>[];

    for (final line in rawLines) {
      final cleaned = _cleanLineText(line.text);
      if (cleaned.isEmpty) continue;

      final (fontSize, isBold) = _resolveLineStyle(line);
      segments.add((
        text: cleaned,
        bounds: line.bounds,
        fontSize: fontSize,
        isBold: isBold,
      ));
    }

    if (segments.isEmpty) return const [];

    // Sort top-to-bottom by vertical center, then left-to-right.
    segments.sort((a, b) {
      final dyCmp = a.bounds.center.dy.compareTo(b.bounds.center.dy);
      if (dyCmp != 0) return dyCmp;
      return a.bounds.left.compareTo(b.bounds.left);
    });

    final rows = <List<({
      String text,
      Rect bounds,
      double fontSize,
      bool isBold,
    })>>[];
    final rowCenters = <double>[];
    final rowFontSizes = <double>[];

    for (final seg in segments) {
      final cy = seg.bounds.center.dy;
      int matchedRow = -1;
      for (int i = rows.length - 1; i >= 0 && i >= rows.length - 4; i--) {
        final tol = math.max(math.max(seg.fontSize, rowFontSizes[i]), 8.0) * 0.55;
        if ((cy - rowCenters[i]).abs() <= tol) {
          matchedRow = i;
          break;
        }
      }
      if (matchedRow == -1) {
        rows.add([seg]);
        rowCenters.add(cy);
        rowFontSizes.add(seg.fontSize);
      } else {
        rows[matchedRow].add(seg);
        final count = rows[matchedRow].length;
        rowCenters[matchedRow] =
            ((rowCenters[matchedRow] * (count - 1)) + cy) / count;
        if (seg.fontSize > rowFontSizes[matchedRow]) {
          rowFontSizes[matchedRow] = seg.fontSize;
        }
      }
    }

    final visualLines = <_VisualLine>[];
    for (final row in rows) {
      row.sort((a, b) => a.bounds.left.compareTo(b.bounds.left));

      final lineSegments = <_LineSegment>[];
      final buffer = StringBuffer();
      double minLeft = double.infinity;
      double maxRight = double.negativeInfinity;
      double minTop = double.infinity;
      double maxBottom = double.negativeInfinity;

      double totalWeight = 0;
      double weightedFontSize = 0;
      double boldWeight = 0;
      double nonNumericWeight = 0;

      for (int i = 0; i < row.length; i++) {
        final seg = row[i];
        lineSegments.add(
          _LineSegment(
            text: seg.text,
            left: seg.bounds.left,
            right: seg.bounds.right,
            fontSize: seg.fontSize,
            isBold: seg.isBold,
          ),
        );

        if (i > 0) {
          final prev = row[i - 1];
          final prevText = prev.text;
          final currText = seg.text;
          final gap = seg.bounds.left - prev.bounds.right;
          final needsSpace = gap > 1.5 ||
              (!prevText.endsWith(' ') && !currText.startsWith(' '));
          if (needsSpace) {
            buffer.write(gap > 14.0 ? '  ' : ' ');
          }
        }
        buffer.write(seg.text);

        if (seg.bounds.left < minLeft) minLeft = seg.bounds.left;
        if (seg.bounds.right > maxRight) maxRight = seg.bounds.right;
        if (seg.bounds.top < minTop) minTop = seg.bounds.top;
        if (seg.bounds.bottom > maxBottom) maxBottom = seg.bounds.bottom;

        final charLen = seg.text.replaceAll(RegExp(r'\s+'), '').length;
        final weight = math.max(1, charLen).toDouble();
        totalWeight += weight;
        weightedFontSize += seg.fontSize * weight;

        if (!_standaloneIntRegex.hasMatch(seg.text.trim())) {
          nonNumericWeight += weight;
          if (seg.isBold) boldWeight += weight;
        }
      }

      final joined = buffer.toString().trim();
      if (joined.isEmpty) continue;

      final dominantFont = totalWeight > 0 ? weightedFontSize / totalWeight : 11.0;
      final effectiveBold =
          nonNumericWeight > 0 ? (boldWeight / nonNumericWeight) >= 0.55 : false;

      visualLines.add(
        _VisualLine(
          text: joined,
          segments: lineSegments,
          minLeft: minLeft.isFinite ? minLeft : 0.0,
          maxRight: maxRight.isFinite ? maxRight : 0.0,
          top: minTop.isFinite ? minTop : 0.0,
          bottom: maxBottom.isFinite ? maxBottom : 0.0,
          fontSize: dominantFont,
          isBold: effectiveBold,
        ),
      );
    }

    visualLines.sort((a, b) => a.top.compareTo(b.top));
    return visualLines;
  }

  static (double, bool) _resolveLineStyle(TextLine line) {
    double fontSize = line.fontSize;
    bool isBold = line.fontStyle.contains(PdfFontStyle.bold) ||
        _boldFontNameRegex.hasMatch(line.fontName);

    if (line.wordCollection.isNotEmpty) {
      double sizeSum = 0;
      double weightSum = 0;
      double boldChars = 0;
      double totalChars = 0;

      for (final word in line.wordCollection) {
        final len = word.text.trim().length;
        final w = math.max(1, len).toDouble();
        if (word.fontSize > 0) {
          sizeSum += word.fontSize * w;
          weightSum += w;
        }
        final wordBold = word.fontStyle.contains(PdfFontStyle.bold) ||
            _boldFontNameRegex.hasMatch(word.fontName);
        totalChars += w;
        if (wordBold) boldChars += w;
      }

      if (fontSize <= 0 && weightSum > 0) {
        fontSize = sizeSum / weightSum;
      }
      if (!isBold && totalChars > 0) {
        isBold = (boldChars / totalChars) >= 0.55;
      }
    }

    if (fontSize <= 0) {
      fontSize = line.bounds.height > 0 ? line.bounds.height : 11.0;
    }
    return (fontSize, isBold);
  }

  static String _cleanLineText(String raw) {
    final fixed = EncodingUtils.fixMojibake(raw);
    return fixed
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '')
        .trim();
  }

  // ---------------------------------------------------------------------------
  // Tier 2: Printed TOC Page Detector
  // ---------------------------------------------------------------------------

  static PdfTocResult _detectPrintedToc(
    PdfDocument document,
    PdfTextExtractor extractor,
  ) {
    final pageCount = document.pages.count;
    final frontLimit = math.min(_maxTocScanFrontPages, pageCount);
    final pageCache = <int, List<_VisualLine>>{};

    List<_VisualLine> getLines(int pageIdx) {
      return pageCache.putIfAbsent(
        pageIdx,
        () => _extractVisualLinesForPage(extractor, pageIdx),
      );
    }

    int? firstTocPageIndex;
    final collectedCandidates = <_RawTocCandidate>[];

    for (int p = 0; p < frontLimit; p++) {
      final lines = getLines(p);
      if (lines.isEmpty) continue;

      final hasTocHeader = _pageHasTocHeader(lines);
      final pageCandidates = _extractTocRowsFromPage(
        lines,
        pageCount: pageCount,
        hasExplicitHeader: hasTocHeader,
      );

      if (pageCandidates.isEmpty) continue;

      final confirmed = hasTocHeader
          ? pageCandidates.length >= 2
          : (pageCandidates.length >= 4 &&
              _hasMostlyNonDecreasingPages(pageCandidates));

      if (!confirmed) continue;

      firstTocPageIndex = p;
      collectedCandidates.addAll(pageCandidates);

      // Scan contiguous continuation pages.
      final maxCont = math.min(pageCount - 1, p + _maxTocContinuationPages);
      for (int q = p + 1; q <= maxCont; q++) {
        final nextLines = getLines(q);
        final nextHasHeader = _pageHasTocHeader(nextLines);
        final nextRows = _extractTocRowsFromPage(
          nextLines,
          pageCount: pageCount,
          hasExplicitHeader: hasTocHeader || nextHasHeader,
        );
        if (nextRows.length < 2) break;
        collectedCandidates.addAll(nextRows);
      }
      break;
    }

    if (collectedCandidates.isEmpty || firstTocPageIndex == null) {
      return PdfTocResult.empty;
    }

    // Calibrate printed page numbering vs PDF page index (front-matter offset).
    final offset = _calibrateTocOffset(
      document: document,
      extractor: extractor,
      candidates: collectedCandidates,
      tocStartPdfPage: firstTocPageIndex + 1,
      pageCache: pageCache,
    );

    final calibrated = <_RawTocCandidate>[
      for (final c in collectedCandidates)
        _RawTocCandidate(
          title: c.title,
          pageNumber: (c.pageNumber + offset).clamp(1, pageCount),
          minLeft: c.minLeft,
          fontSize: c.fontSize,
          isBold: c.isBold,
        ),
    ];

    final entries = _buildTocHierarchyFromPrintedRows(calibrated);
    if (entries.isEmpty) return PdfTocResult.empty;

    return PdfTocResult(
      entries: entries,
      source: PdfTocSource.detectedTocPage,
      tocPageNumber: firstTocPageIndex + 1,
    );
  }

  static bool _pageHasTocHeader(List<_VisualLine> lines) {
    final inspectCount = math.min(10, lines.length);
    for (int i = 0; i < inspectCount; i++) {
      final normalized = _normalizeForKeywordMatch(lines[i].text);
      if (normalized.isEmpty || normalized.length > 60) continue;
      if (_isTocHeaderNormalized(normalized)) return true;
    }
    return false;
  }

  static bool _isTocHeaderNormalized(String normalized) {
    const keywords = [
      'table of contents',
      'contents',
      'sommaire',
      'table des matieres',
      'plan',
      'chapitres',
      'chapters',
      'table of content',
    ];
    for (final kw in keywords) {
      if (normalized == kw ||
          normalized.startsWith('$kw ') ||
          normalized.startsWith('$kw:') ||
          normalized.endsWith(' $kw')) {
        return true;
      }
    }

    const arabicKeywords = [
      'جدول المحتويات',
      'الفهرس',
      'فهرس',
      'المحتويات',
    ];
    for (final kw in arabicKeywords) {
      if (normalized.contains(kw)) return true;
    }
    return false;
  }

  static String _normalizeForKeywordMatch(String text) {
    final cleaned = EncodingUtils.removeDiacritics(text.toLowerCase())
        .replaceAll(RegExp(r'[:\-_\.\u0640]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (_arabicCharsRegex.hasMatch(cleaned)) {
      final reversed = String.fromCharCodes(cleaned.runes.toList().reversed);
      return '$cleaned $reversed';
    }
    return cleaned;
  }

  static List<_RawTocCandidate> _extractTocRowsFromPage(
    List<_VisualLine> lines, {
    required int pageCount,
    required bool hasExplicitHeader,
  }) {
    final candidates = <_RawTocCandidate>[];

    for (final line in lines) {
      final parsed = _parseTocRow(
        line,
        pageCount: pageCount,
        hasExplicitHeader: hasExplicitHeader,
      );
      if (parsed != null) {
        candidates.add(parsed);
      }
    }
    return candidates;
  }

  static _RawTocCandidate? _parseTocRow(
    _VisualLine line, {
    required int pageCount,
    required bool hasExplicitHeader,
  }) {
    final text = line.text.trim();
    if (text.length < 4) return null;

    String? rawTitle;
    int? parsedPage;

    // 1. Dot / dash / underscore leader pattern: "Chapter 1 .... 12"
    final leaderMatch = _leaderRowRegex.firstMatch(text);
    if (leaderMatch != null) {
      rawTitle = leaderMatch.group(1);
      parsedPage = _parseWesternOrArabicInt(leaderMatch.group(2)!);
    }

    // 2. Column-separated visual segments (e.g. separate TextLines for title & page)
    if (rawTitle == null && line.segments.length >= 2) {
      final lastSeg = line.segments.last;
      final firstSeg = line.segments.first;
      final lastToken = lastSeg.text.trim();
      final firstToken = firstSeg.text.trim();

      if (_standaloneIntRegex.hasMatch(lastToken)) {
        final prevRight = line.segments[line.segments.length - 2].right;
        if ((lastSeg.left - prevRight) >= 6.0 || hasExplicitHeader) {
          final p = _parseWesternOrArabicInt(lastToken);
          if (p != null && p >= 1 && p <= pageCount) {
            rawTitle = line.segments
                .sublist(0, line.segments.length - 1)
                .map((s) => s.text)
                .join(' ');
            parsedPage = p;
          }
        }
      } else if (_standaloneIntRegex.hasMatch(firstToken) &&
          _arabicCharsRegex.hasMatch(text)) {
        final nextLeft = line.segments[1].left;
        if ((nextLeft - firstSeg.right) >= 6.0 || hasExplicitHeader) {
          final p = _parseWesternOrArabicInt(firstToken);
          if (p != null && p >= 1 && p <= pageCount) {
            rawTitle = line.segments
                .sublist(1)
                .map((s) => s.text)
                .join(' ');
            parsedPage = p;
          }
        }
      }
    }

    // 3. Multi-space separation in a single TextLine
    if (rawTitle == null) {
      final spacedMatch = _spacedColumnRowRegex.firstMatch(text);
      if (spacedMatch != null) {
        rawTitle = spacedMatch.group(1);
        parsedPage = _parseWesternOrArabicInt(spacedMatch.group(2)!);
      }
    }

    // 4. RTL visual-ordered line starting with page number on left
    if (rawTitle == null && _arabicCharsRegex.hasMatch(text)) {
      final rtlMatch = _rtlLeadingPageRowRegex.firstMatch(text);
      if (rtlMatch != null) {
        parsedPage = _parseWesternOrArabicInt(rtlMatch.group(1)!);
        rawTitle = rtlMatch.group(2);
      }
    }

    // 5. Single-space separation allowed only when the page has a confirmed TOC header
    if (rawTitle == null && hasExplicitHeader) {
      final singleMatch = _singleSpacedRowRegex.firstMatch(text);
      if (singleMatch != null) {
        rawTitle = singleMatch.group(1);
        parsedPage = _parseWesternOrArabicInt(singleMatch.group(2)!);
      }
    }

    if (rawTitle == null || parsedPage == null) return null;
    if (parsedPage < 1 || parsedPage > pageCount) return null;

    final cleanedTitle = _stripTrailingLeaders(rawTitle);
    if (cleanedTitle.length < 2 || cleanedTitle.length > 130) return null;
    if (_pureNumericOrPunctRegex.hasMatch(cleanedTitle)) return null;
    if (_urlOrEmailRegex.hasMatch(cleanedTitle)) return null;

    return _RawTocCandidate(
      title: cleanedTitle,
      pageNumber: parsedPage,
      minLeft: line.minLeft,
      fontSize: line.fontSize,
      isBold: line.isBold,
    );
  }

  static String _stripTrailingLeaders(String input) {
    return input
        .replaceAll(RegExp(r'[\.\·•_…\-]{2,}\s*$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _hasMostlyNonDecreasingPages(List<_RawTocCandidate> rows) {
    if (rows.length < 2) return false;
    int nonDecreasing = 0;
    for (int i = 1; i < rows.length; i++) {
      if (rows[i].pageNumber >= rows[i - 1].pageNumber) {
        nonDecreasing++;
      }
    }
    return nonDecreasing / (rows.length - 1) >= 0.6;
  }

  static int _calibrateTocOffset({
    required PdfDocument document,
    required PdfTextExtractor extractor,
    required List<_RawTocCandidate> candidates,
    required int tocStartPdfPage,
    required Map<int, List<_VisualLine>> pageCache,
  }) {
    final pageCount = document.pages.count;
    final sampleCandidates = <_RawTocCandidate>[];

    for (final c in candidates) {
      final strippedTitle = _stripLeadingNumbering(c.title);
      if (strippedTitle.length >= 4 && c.pageNumber >= 1) {
        sampleCandidates.add(c);
        if (sampleCandidates.length >= 3) break;
      }
    }
    if (sampleCandidates.isEmpty) return 0;

    final observedOffsets = <int>[];

    for (final sample in sampleCandidates) {
      final searchNeedle = _extractSearchNeedle(sample.title);
      if (searchNeedle.length < 3) continue;

      final nominalPage = sample.pageNumber.clamp(1, pageCount);
      if (nominalPage > tocStartPdfPage &&
          _pageContainsHeadingNeedle(
            extractor,
            nominalPage - 1,
            searchNeedle,
            pageCache,
          )) {
        observedOffsets.add(0);
        continue;
      }

      final startSearch =
          math.max(tocStartPdfPage + 1, sample.pageNumber - 5);
      final endSearch = math.min(pageCount, sample.pageNumber + 25);

      for (int p = startSearch; p <= endSearch; p++) {
        if (_pageContainsHeadingNeedle(
          extractor,
          p - 1,
          searchNeedle,
          pageCache,
        )) {
          observedOffsets.add(p - sample.pageNumber);
          break;
        }
      }
    }

    if (observedOffsets.isEmpty) return 0;

    // Pick consensus offset (majority mode).
    final counts = <int, int>{};
    for (final off in observedOffsets) {
      counts[off] = (counts[off] ?? 0) + 1;
    }

    int bestOffset = 0;
    int bestCount = 0;
    counts.forEach((off, count) {
      if (count > bestCount) {
        bestCount = count;
        bestOffset = off;
      }
    });

    if (bestCount * 2 >= observedOffsets.length) {
      return bestOffset;
    }
    return 0;
  }

  static String _stripLeadingNumbering(String title) {
    return title
        .replaceFirst(
          RegExp(r'^(?:\d+(?:\.\d+)*|[IVXLCDM]+)[\.\)\s:\-]+'),
          '',
        )
        .trim();
  }

  static String _extractSearchNeedle(String title) {
    final cleaned = EncodingUtils.removeDiacritics(title.toLowerCase())
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final words = cleaned.split(' ').where((w) => w.length >= 2).toList();
    if (words.isEmpty) return cleaned;
    return words.take(4).join(' ');
  }

  static bool _pageContainsHeadingNeedle(
    PdfTextExtractor extractor,
    int pageIndex,
    String needle,
    Map<int, List<_VisualLine>> pageCache,
  ) {
    final lines = pageCache.putIfAbsent(
      pageIndex,
      () => _extractVisualLinesForPage(extractor, pageIndex),
    );
    final needleWords = needle.split(' ');

    for (final line in lines) {
      final norm = EncodingUtils.removeDiacritics(line.text.toLowerCase())
          .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (norm.contains(needle)) return true;

      if (_arabicCharsRegex.hasMatch(line.text)) {
        final rev = String.fromCharCodes(norm.runes.toList().reversed);
        if (rev.contains(needle)) return true;
      }

      if (needleWords.length >= 2 &&
          needleWords.every((w) => norm.contains(w))) {
        return true;
      }
    }
    return false;
  }

  static List<PdfTocEntry> _buildTocHierarchyFromPrintedRows(
    List<_RawTocCandidate> rows,
  ) {
    if (rows.isEmpty) return const [];

    // Compute distinct left-indent buckets (within 10pt tolerance).
    final leftBuckets = <double>[];
    final sortedLefts = rows.map((r) => r.minLeft).toList()..sort();
    for (final x in sortedLefts) {
      if (leftBuckets.isEmpty || (x - leftBuckets.last).abs() > 10.0) {
        leftBuckets.add(x);
      }
    }

    final levels = <int>[];
    for (final r in rows) {
      final t = r.title;
      int level;
      final subMatch = _subPrefixLevelRegex.firstMatch(t);
      if (_chapterPrefixLevelRegex.hasMatch(t) ||
          _topNumericPrefixRegex.hasMatch(t)) {
        level = 0;
      } else if (subMatch != null) {
        final dots = '.'.allMatches(subMatch.group(1)!).length;
        level = dots.clamp(1, 2);
      } else if (leftBuckets.length > 1) {
        int nearest = 0;
        double bestDist = double.infinity;
        for (int b = 0; b < leftBuckets.length; b++) {
          final dist = (r.minLeft - leftBuckets[b]).abs();
          if (dist < bestDist) {
            bestDist = dist;
            nearest = b;
          }
        }
        level = nearest.clamp(0, 2);
      } else {
        level = 0;
      }
      levels.add(level);
    }

    // Ensure first entry starts at level 0 if everything was shifted.
    final minLevel = levels.reduce(math.min);
    final flat = <PdfTocEntry>[
      for (int i = 0; i < rows.length; i++)
        PdfTocEntry(
          title: rows[i].title,
          pageNumber: rows[i].pageNumber,
          level: (levels[i] - minLevel).clamp(0, 2),
          source: PdfTocSource.detectedTocPage,
        ),
    ];

    return _nestEntriesByLevel(flat);
  }

  // ---------------------------------------------------------------------------
  // Tier 3: Visual & Structural Heading Scanner / Slide Titles
  // ---------------------------------------------------------------------------

  static PdfTocResult _detectVisualHeadings(
    PdfDocument document,
    PdfTextExtractor extractor,
  ) {
    final pageCount = document.pages.count;
    final scanPages = math.min(pageCount, _maxHeadingScanPages);

    // 1. Determine whether PDF is primarily landscape slide deck
    final sampleCount = math.min(pageCount, 12);
    int landscapePages = 0;
    for (int i = 0; i < sampleCount; i++) {
      final pageSize = document.pages[i].size;
      if (pageSize.width > pageSize.height * 1.15) {
        landscapePages++;
      }
    }
    final isSlideDeck =
        sampleCount > 0 && (landscapePages / sampleCount) >= 0.70;

    final pageLines = <int, List<_VisualLine>>{};
    final fontSizeWeights = <double, double>{};
    final edgeLineCounts = <String, int>{};

    for (int p = 0; p < scanPages; p++) {
      final lines = _extractVisualLinesForPage(extractor, p);
      pageLines[p] = lines;

      final pageHeight = document.pages[p].size.height;
      final seenEdgeOnPage = <String>{};

      for (final line in lines) {
        final roundedSize = (line.fontSize * 2).round() / 2.0;
        final charWeight =
            math.max(1, line.text.replaceAll(RegExp(r'\s+'), '').length)
                .toDouble();
        fontSizeWeights[roundedSize] =
            (fontSizeWeights[roundedSize] ?? 0) + charWeight;

        if (pageHeight > 0 &&
            (line.top <= pageHeight * 0.12 ||
                line.bottom >= pageHeight * 0.88)) {
          final sig = _runningHeaderSignature(line.text);
          if (sig.length >= 2 && seenEdgeOnPage.add(sig)) {
            edgeLineCounts[sig] = (edgeLineCounts[sig] ?? 0) + 1;
          }
        }
      }
    }

    // Identify repeating headers/footers appearing on >= 3 pages and >= 15% of scanned pages
    final repeatingThreshold = math.max(3, (scanPages * 0.15).ceil());
    final repeatingEdgeSigs = <String>{
      for (final entry in edgeLineCounts.entries)
        if (entry.value >= repeatingThreshold) entry.key,
    };

    if (isSlideDeck) {
      return _extractSlideDeckTitles(
        document: document,
        scanPages: scanPages,
        pageLines: pageLines,
        repeatingEdgeSigs: repeatingEdgeSigs,
      );
    }

    final bodyFontSize = _weightedMedianFontSize(fontSizeWeights);
    final candidates = <_HeadingCandidate>[];

    for (int p = 0; p < scanPages; p++) {
      final lines = pageLines[p] ?? const <_VisualLine>[];
      if (lines.isEmpty) continue;

      final pageHeight = document.pages[p].size.height;
      final filtered = <_VisualLine>[];
      for (final line in lines) {
        if (pageHeight > 0 &&
            (line.top <= pageHeight * 0.12 ||
                line.bottom >= pageHeight * 0.88)) {
          final sig = _runningHeaderSignature(line.text);
          if (repeatingEdgeSigs.contains(sig)) continue;
        }
        filtered.add(line);
      }

      // Merge consecutive wrapped heading lines with matching style before scoring
      final merged = _mergeWrappedHeadingLines(filtered, bodyFontSize);

      for (int idx = 0; idx < merged.length; idx++) {
        final line = merged[idx];
        final text = line.text.trim();
        if (text.length < 2 || text.length > 110) continue;
        if (_pureNumericOrPunctRegex.hasMatch(text)) continue;
        if (_urlOrEmailRegex.hasMatch(text)) continue;

        final isExplicit = _explicitChapterRegex.hasMatch(text);
        final numberedMatch = _numberedHeadingRegex.firstMatch(text);
        final isNumbered = numberedMatch != null;

        // Avoid treating full prose sentences as headings
        final endsWithPeriod = text.endsWith('.') && !text.endsWith('..');
        if (endsWithPeriod && !isExplicit && !isNumbered) continue;
        if ((text.endsWith(',') || text.endsWith(';')) && !isExplicit) continue;

        final sizeRatio =
            bodyFontSize > 0 ? (line.fontSize / bodyFontSize) : 1.0;

        bool accept = false;
        if (isExplicit &&
            sizeRatio >= 0.98 &&
            (line.isBold || sizeRatio >= 1.05 || idx <= 2 || text.length <= 65)) {
          accept = true;
        } else if (isNumbered &&
            (line.isBold || sizeRatio >= 1.08) &&
            text.length <= 95) {
          accept = true;
        } else if (sizeRatio >= 1.24) {
          accept = true;
        } else if (sizeRatio >= 1.10 && line.isBold && text.length <= 80) {
          accept = true;
        }

        if (!accept) continue;

        int? numericDepth;
        if (numberedMatch != null && numberedMatch.group(1) != null) {
          numericDepth = '.'.allMatches(numberedMatch.group(1)!).length;
        }

        candidates.add(
          _HeadingCandidate(
            title: text,
            pageNumber: p + 1,
            fontSize: line.fontSize,
            isBold: line.isBold,
            top: line.top,
            isExplicitChapter: isExplicit,
            numericDepth: numericDepth,
          ),
        );
      }
    }

    if (candidates.isEmpty) return PdfTocResult.empty;

    // Deduplicate consecutive identical headings (e.g., section title repeated across pages)
    final deduped = <_HeadingCandidate>[];
    for (final c in candidates) {
      if (deduped.isNotEmpty &&
          deduped.last.title.toLowerCase() == c.title.toLowerCase()) {
        continue;
      }
      deduped.add(c);
    }

    // Assign level 0 vs 1 vs 2
    final maxHeadingSize =
        deduped.map((c) => c.fontSize).reduce(math.max);
    final hasExplicitTop =
        deduped.any((c) => c.isExplicitChapter || _chapterPrefixLevelRegex.hasMatch(c.title));

    final flatEntries = <PdfTocEntry>[];
    for (final c in deduped) {
      int level;
      if (_chapterPrefixLevelRegex.hasMatch(c.title) ||
          (c.isExplicitChapter && c.numericDepth == null)) {
        level = 0;
      } else if (c.numericDepth != null) {
        level = c.numericDepth!.clamp(0, 2);
      } else if (c.fontSize >= maxHeadingSize * 0.90 &&
          (!hasExplicitTop || c.fontSize >= bodyFontSize * 1.25)) {
        level = 0;
      } else {
        level = 1;
      }

      flatEntries.add(
        PdfTocEntry(
          title: c.title,
          pageNumber: c.pageNumber,
          level: level,
          source: PdfTocSource.detectedHeadings,
        ),
      );
    }

    // Normalize top level so root list always contains level 0 entries
    final minLvl = flatEntries.map((e) => e.level).reduce(math.min);
    final normalized = [
      for (final e in flatEntries)
        e.copyWith(level: (e.level - minLvl).clamp(0, 2)),
    ];

    return PdfTocResult(
      entries: _nestEntriesByLevel(normalized),
      source: PdfTocSource.detectedHeadings,
    );
  }

  static PdfTocResult _extractSlideDeckTitles({
    required PdfDocument document,
    required int scanPages,
    required Map<int, List<_VisualLine>> pageLines,
    required Set<String> repeatingEdgeSigs,
  }) {
    final entries = <PdfTocEntry>[];

    for (int p = 0; p < scanPages; p++) {
      final lines = pageLines[p] ?? const <_VisualLine>[];
      if (lines.isEmpty) continue;

      final pageHeight = document.pages[p].size.height;
      final candidates = <_VisualLine>[];

      for (final line in lines) {
        final text = line.text.trim();
        if (text.length < 2 || text.length > 110) continue;
        if (_pureNumericOrPunctRegex.hasMatch(text)) continue;
        if (_urlOrEmailRegex.hasMatch(text)) continue;
        if (pageHeight > 0 &&
            (line.top <= pageHeight * 0.12 ||
                line.bottom >= pageHeight * 0.88)) {
          if (repeatingEdgeSigs.contains(_runningHeaderSignature(text))) {
            continue;
          }
        }
        candidates.add(line);
      }

      if (candidates.isEmpty) continue;

      final topCutoff = pageHeight > 0 ? pageHeight * 0.42 : double.infinity;
      final topZone =
          candidates.where((l) => l.top <= topCutoff).toList();
      final pool = topZone.isNotEmpty ? topZone : candidates;

      // Pick largest-font line(s) in pool (merging consecutive wrapped lines of same size)
      final maxFont = pool.map((l) => l.fontSize).reduce(math.max);
      final titleLines = <_VisualLine>[];

      for (final l in pool) {
        if ((l.fontSize - maxFont).abs() <= maxFont * 0.08) {
          if (titleLines.isEmpty) {
            titleLines.add(l);
          } else {
            final gap = l.top - titleLines.last.bottom;
            if (gap <= maxFont * 1.6) {
              titleLines.add(l);
            } else {
              break;
            }
          }
        } else if (titleLines.isNotEmpty) {
          break;
        }
      }

      final title = titleLines.isNotEmpty
          ? titleLines.map((l) => l.text).join(' ').trim()
          : pool.first.text.trim();

      if (title.isEmpty || title.length > 120) continue;

      entries.add(
        PdfTocEntry(
          title: title,
          pageNumber: p + 1,
          level: 0,
          source: PdfTocSource.slideTitles,
        ),
      );
    }

    if (entries.isEmpty) return PdfTocResult.empty;

    return PdfTocResult(
      entries: entries,
      source: PdfTocSource.slideTitles,
    );
  }

  static List<_VisualLine> _mergeWrappedHeadingLines(
    List<_VisualLine> lines,
    double bodyFontSize,
  ) {
    if (lines.length <= 1) return lines;
    final out = <_VisualLine>[];

    for (final curr in lines) {
      if (out.isEmpty) {
        out.add(curr);
        continue;
      }
      final prev = out.last;
      final sameStyle = (curr.fontSize - prev.fontSize).abs() <=
              math.max(1.0, prev.fontSize * 0.08) &&
          curr.isBold == prev.isBold;
      final isProminent =
          curr.fontSize >= bodyFontSize * 1.08 || curr.isBold;
      final gap = curr.top - prev.bottom;

      if (sameStyle &&
          isProminent &&
          gap >= -4.0 &&
          gap <= prev.fontSize * 1.5 &&
          prev.text.length + curr.text.length <= 105 &&
          !prev.text.endsWith('.')) {
        out[out.length - 1] = _VisualLine(
          text: '${prev.text} ${curr.text}'.trim(),
          segments: [...prev.segments, ...curr.segments],
          minLeft: math.min(prev.minLeft, curr.minLeft),
          maxRight: math.max(prev.maxRight, curr.maxRight),
          top: prev.top,
          bottom: curr.bottom,
          fontSize: math.max(prev.fontSize, curr.fontSize),
          isBold: prev.isBold,
        );
      } else {
        out.add(curr);
      }
    }
    return out;
  }

  static String _runningHeaderSignature(String text) {
    return EncodingUtils.removeDiacritics(text.toLowerCase())
        .replaceAll(RegExp(r'[0-9٠-٩]+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static double _weightedMedianFontSize(Map<double, double> weights) {
    if (weights.isEmpty) return 11.0;
    final sorted = weights.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final total = sorted.fold<double>(0, (acc, e) => acc + e.value);
    double cumulative = 0;
    for (final e in sorted) {
      cumulative += e.value;
      if (cumulative >= total * 0.5) {
        return e.key;
      }
    }
    return sorted.first.key;
  }

  static int? _parseWesternOrArabicInt(String raw) {
    const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
    const easternArabic = '۰۱۲۳۴۵۶۷۸۹';
    final buf = StringBuffer();
    for (int i = 0; i < raw.length; i++) {
      final ch = raw[i];
      final idx1 = arabicIndic.indexOf(ch);
      if (idx1 >= 0) {
        buf.write(idx1);
        continue;
      }
      final idx2 = easternArabic.indexOf(ch);
      if (idx2 >= 0) {
        buf.write(idx2);
        continue;
      }
      buf.write(ch);
    }
    return int.tryParse(buf.toString().trim());
  }

  /// Nests flat level-annotated entries into a clean parent/children tree.
  static List<PdfTocEntry> _nestEntriesByLevel(List<PdfTocEntry> flat) {
    final roots = <_MutableTocNode>[];
    final stack = <_MutableTocNode>[];

    for (final raw in flat) {
      final node = _MutableTocNode(raw);

      while (stack.isNotEmpty && stack.last.entry.level >= raw.level) {
        stack.removeLast();
      }

      if (stack.isEmpty) {
        roots.add(node);
      } else {
        stack.last.children.add(node);
      }
      stack.add(node);
    }

    return [for (final r in roots) r.freeze()];
  }
}

class _MutableTocNode {
  _MutableTocNode(this.entry);

  final PdfTocEntry entry;
  final List<_MutableTocNode> children = [];

  PdfTocEntry freeze() {
    return entry.copyWith(
      children: children.isEmpty
          ? const []
          : [for (final c in children) c.freeze()],
    );
  }
}
