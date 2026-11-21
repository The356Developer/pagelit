import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/material.dart' show TextAlign;
import 'package:xml/xml.dart';

import 'encoding_utils.dart';

/// Represents a single Word border edge parsed from OOXML.
class WordBorder {
  const WordBorder({
    this.colorHex,
    this.widthPt = 0.5,
    this.style = 'single',
  });

  final String? colorHex;
  final double widthPt;
  final String style;

  bool get isVisible =>
      style != 'none' && style != 'nil' && widthPt > 0;
}

/// Collection of border edges on a paragraph, table, or table cell.
class WordBorders {
  const WordBorders({
    this.top,
    this.bottom,
    this.left,
    this.right,
    this.insideH,
    this.insideV,
  });

  final WordBorder? top;
  final WordBorder? bottom;
  final WordBorder? left;
  final WordBorder? right;
  final WordBorder? insideH;
  final WordBorder? insideV;

  bool get hasAny =>
      (top?.isVisible ?? false) ||
      (bottom?.isVisible ?? false) ||
      (left?.isVisible ?? false) ||
      (right?.isVisible ?? false) ||
      (insideH?.isVisible ?? false) ||
      (insideV?.isVisible ?? false);

  WordBorders mergeOver(WordBorders? parent) {
    if (parent == null) return this;
    return WordBorders(
      top: top ?? parent.top,
      bottom: bottom ?? parent.bottom,
      left: left ?? parent.left,
      right: right ?? parent.right,
      insideH: insideH ?? parent.insideH,
      insideV: insideV ?? parent.insideV,
    );
  }
}

/// Page dimensions, margins, borders, and background parsed from `<w:sectPr>` and `<w:background>`.
class WordPageSettings {
  const WordPageSettings({
    this.widthPt = 612.0,
    this.heightPt = 792.0,
    this.marginTopPt = 72.0,
    this.marginBottomPt = 72.0,
    this.marginLeftPt = 72.0,
    this.marginRightPt = 72.0,
    this.backgroundColorHex,
    this.pageBorders,
  });

  final double widthPt;
  final double heightPt;
  final double marginTopPt;
  final double marginBottomPt;
  final double marginLeftPt;
  final double marginRightPt;
  final String? backgroundColorHex;
  final WordBorders? pageBorders;
}

sealed class WordBlock {
  const WordBlock();
}

/// Explicit page break inside a Word document (`<w:br w:type="page"/>`).
class WordPageBreakBlock extends WordBlock {
  const WordPageBreakBlock();
}

class WordParagraph extends WordBlock {
  const WordParagraph({
    required this.spans,
    this.headingLevel,
    this.isBullet = false,
    this.alignment,
    this.indent,
    this.backgroundColorHex,
    this.indentRight,
    this.firstLineIndent,
    this.spaceBeforePt,
    this.spaceAfterPt,
    this.lineSpacingMultiplier,
    this.lineSpacingExactPt,
    this.listMarker,
    this.listLevel = 0,
    this.borders,
    this.pageBreakBefore = false,
    this.isEmptySpacer = false,
    this.defaultFontSize,
    this.isRightToLeft = false,
  });

  final List<WordSpan> spans;
  final int? headingLevel;
  final bool isBullet;
  final TextAlign? alignment;
  final double? indent;
  final String? backgroundColorHex;
  final double? indentRight;
  final double? firstLineIndent;
  final double? spaceBeforePt;
  final double? spaceAfterPt;
  final double? lineSpacingMultiplier;
  final double? lineSpacingExactPt;
  final String? listMarker;
  final int listLevel;
  final WordBorders? borders;
  final bool pageBreakBefore;
  final bool isEmptySpacer;
  final double? defaultFontSize;
  final bool isRightToLeft;

  String get fullText => spans.map((s) => s.text).join();
}

class WordSpan {
  const WordSpan({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.fontSize,
    this.colorHex,
    this.highlightHex,
    this.linkUrl,
    this.fontFamily,
    this.shadingColorHex,
    this.isSuperscript = false,
    this.isSubscript = false,
    this.allCaps = false,
    this.smallCaps = false,
    this.letterSpacingPt,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;
  final double? fontSize;
  final String? colorHex;
  final String? highlightHex;
  final String? linkUrl;
  final String? fontFamily;
  final String? shadingColorHex;
  final bool isSuperscript;
  final bool isSubscript;
  final bool allCaps;
  final bool smallCaps;
  final double? letterSpacingPt;
}

class WordTableCell {
  const WordTableCell({
    required this.text,
    this.isHeader = false,
    this.backgroundColorHex,
    this.alignment,
    this.blocks = const [],
    this.colSpan = 1,
    this.rowSpan = 1,
    this.isVerticalMergeContinue = false,
    this.widthPt,
    this.borders,
    this.verticalAlignment,
    this.paddingTopPt,
    this.paddingBottomPt,
    this.paddingLeftPt,
    this.paddingRightPt,
  });

  final String text;
  final bool isHeader;
  final String? backgroundColorHex;
  final TextAlign? alignment;
  final List<WordBlock> blocks;
  final int colSpan;
  final int rowSpan;
  final bool isVerticalMergeContinue;
  final double? widthPt;
  final WordBorders? borders;
  final String? verticalAlignment;
  final double? paddingTopPt;
  final double? paddingBottomPt;
  final double? paddingLeftPt;
  final double? paddingRightPt;
}

class WordTableBlock extends WordBlock {
  const WordTableBlock({
    required this.rows,
    this.richCells,
    this.columnWidthsPt,
    this.borders,
    this.alignment,
    this.widthPt,
    this.widthPercent,
    this.hasExplicitHeaderRow = false,
    this.defaultCellPaddingTopPt,
    this.defaultCellPaddingBottomPt,
    this.defaultCellPaddingLeftPt,
    this.defaultCellPaddingRightPt,
  });

  final List<List<String>> rows;
  final List<List<WordTableCell>>? richCells;
  final List<double>? columnWidthsPt;
  final WordBorders? borders;
  final TextAlign? alignment;
  final double? widthPt;
  final double? widthPercent;
  final bool hasExplicitHeaderRow;
  final double? defaultCellPaddingTopPt;
  final double? defaultCellPaddingBottomPt;
  final double? defaultCellPaddingLeftPt;
  final double? defaultCellPaddingRightPt;
}

class WordImageBlock extends WordBlock {
  const WordImageBlock({
    required this.bytes,
    this.altText,
    this.widthPt,
    this.heightPt,
    this.alignment,
  });

  final Uint8List bytes;
  final String? altText;
  final double? widthPt;
  final double? heightPt;
  final TextAlign? alignment;
}

/// Inline text box or shape (`<wp:inline>` with `<wps:txbx>` or inline VML `<v:textbox>`).
class WordTextBoxBlock extends WordBlock {
  const WordTextBoxBlock({
    required this.blocks,
    this.widthPt,
    this.heightPt,
    this.fillColorHex,
    this.strokeColorHex,
    this.strokeWidthPt,
    this.shapeType,
    this.alignment,
  });

  final List<WordBlock> blocks;
  final double? widthPt;
  final double? heightPt;
  final String? fillColorHex;
  final String? strokeColorHex;
  final double? strokeWidthPt;
  final String? shapeType;
  final TextAlign? alignment;
}

/// Floating / anchored drawing element (image, shape, or text box) positioned on a Word page.
class WordFloatingElement {
  const WordFloatingElement({
    required this.xPt,
    required this.yPt,
    required this.widthPt,
    required this.heightPt,
    this.behindDoc = false,
    this.zOrder = 0,
    this.rotationDeg = 0.0,
    this.flipH = false,
    this.flipV = false,
    this.pageIndex = 0,
    this.imageBytes,
    this.shapeType,
    this.fillColorHex,
    this.strokeColorHex,
    this.strokeWidthPt,
    this.textBlocks = const [],
    this.altText,
  });

  final double xPt;
  final double yPt;
  final double widthPt;
  final double heightPt;
  final bool behindDoc;
  final int zOrder;
  final double rotationDeg;
  final bool flipH;
  final bool flipV;
  /// 0-based page index where anchored, or `-1` when repeating from a header/footer.
  final int pageIndex;
  final Uint8List? imageBytes;
  final String? shapeType;
  final String? fillColorHex;
  final String? strokeColorHex;
  final double? strokeWidthPt;
  final List<WordBlock> textBlocks;
  final String? altText;

  WordFloatingElement copyWithPageIndex(int newPageIndex) {
    return WordFloatingElement(
      xPt: xPt,
      yPt: yPt,
      widthPt: widthPt,
      heightPt: heightPt,
      behindDoc: behindDoc,
      zOrder: zOrder,
      rotationDeg: rotationDeg,
      flipH: flipH,
      flipV: flipV,
      pageIndex: newPageIndex,
      imageBytes: imageBytes,
      shapeType: shapeType,
      fillColorHex: fillColorHex,
      strokeColorHex: strokeColorHex,
      strokeWidthPt: strokeWidthPt,
      textBlocks: textBlocks,
      altText: altText,
    );
  }
}

class WordDocument {
  const WordDocument({
    required this.blocks,
    this.pageSettings = const WordPageSettings(),
    this.defaultFontSizePt,
    this.defaultFontFamily,
    this.floatingElements = const [],
    this.headerBlocks = const [],
    this.footerBlocks = const [],
  });

  final List<WordBlock> blocks;
  final WordPageSettings pageSettings;
  final double? defaultFontSizePt;
  final String? defaultFontFamily;
  final List<WordFloatingElement> floatingElements;
  final List<WordBlock> headerBlocks;
  final List<WordBlock> footerBlocks;
}

// ---------------------------------------------------------------------------
// Internal XML & OOXML Style / Theme / Numbering Models
// ---------------------------------------------------------------------------

XmlElement? _child(XmlElement parent, String localName) {
  for (final node in parent.children) {
    if (node is XmlElement && node.name.local == localName) {
      return node;
    }
  }
  return null;
}

Iterable<XmlElement> _children(XmlElement parent, String localName) sync* {
  for (final node in parent.children) {
    if (node is XmlElement && node.name.local == localName) {
      yield node;
    }
  }
}

Iterable<XmlElement> _descendants(XmlElement root, String localName) sync* {
  for (final node in root.descendants) {
    if (node is XmlElement && node.name.local == localName) {
      yield node;
    }
  }
}

String? _attr(XmlElement el, String localName) {
  for (final attr in el.attributes) {
    if (attr.name.local == localName) {
      return attr.value;
    }
  }
  return null;
}

ArchiveFile? _findArchiveFile(Archive archive, String path) {
  final exact = archive.findFile(path);
  if (exact != null) return exact;
  final normalizedTarget = path.replaceAll('\\', '/').toLowerCase();
  for (final file in archive.files) {
    if (!file.isFile) continue;
    if (file.name.replaceAll('\\', '/').toLowerCase() == normalizedTarget) {
      return file;
    }
  }
  return null;
}

String? _normalizeHexColor(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final lower = trimmed.toLowerCase();
  if (lower == 'auto' || lower == 'none' || lower == 'nil' || lower == 'clear') {
    return null;
  }
  final clean = trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
  if (clean.length == 6 && int.tryParse(clean, radix: 16) != null) {
    return clean.toUpperCase();
  }
  return null;
}

bool? _parseToggleAttr(XmlElement? el) {
  if (el == null) return null;
  final val = _attr(el, 'val')?.toLowerCase();
  if (val == null || val == '1' || val == 'true' || val == 'on') {
    return true;
  }
  if (val == '0' || val == 'false' || val == 'off') {
    return false;
  }
  return true;
}

TextAlign? _parseJcValue(String? val) {
  return switch (val?.toLowerCase()) {
    'center' => TextAlign.center,
    'right' || 'end' => TextAlign.right,
    'both' || 'justify' || 'distribute' => TextAlign.justify,
    'left' || 'start' => TextAlign.left,
    _ => null,
  };
}

class _WordTheme {
  const _WordTheme({
    this.colors = const {},
    this.majorFont,
    this.minorFont,
  });

  final Map<String, String> colors;
  final String? majorFont;
  final String? minorFont;

  static _WordTheme parse(String xmlContent) {
    final doc = XmlDocument.parse(xmlContent);
    final colors = <String, String>{};

    final clrScheme = _descendants(doc.rootElement, 'clrScheme').firstOrNull;
    if (clrScheme != null) {
      for (final node in clrScheme.children) {
        if (node is! XmlElement) continue;
        final key = node.name.local.toLowerCase();
        final srgb = _child(node, 'srgbClr');
        final sysClr = _child(node, 'sysClr');
        String? hex = _normalizeHexColor(srgb != null ? _attr(srgb, 'val') : null);
        hex ??= _normalizeHexColor(sysClr != null ? _attr(sysClr, 'lastClr') : null);
        if (hex == null && sysClr != null) {
          final sysVal = _attr(sysClr, 'val')?.toLowerCase();
          if (sysVal == 'windowtext') hex = '000000';
          if (sysVal == 'window') hex = 'FFFFFF';
        }
        if (hex != null) {
          colors[key] = hex;
        }
      }
    }

    String? majorFont;
    String? minorFont;
    final fontScheme = _descendants(doc.rootElement, 'fontScheme').firstOrNull;
    if (fontScheme != null) {
      final majorEl = _child(fontScheme, 'majorFont');
      if (majorEl != null) {
        majorFont = _extractSchemeFont(majorEl);
      }
      final minorEl = _child(fontScheme, 'minorFont');
      if (minorEl != null) {
        minorFont = _extractSchemeFont(minorEl);
      }
    }

    return _WordTheme(
      colors: colors,
      majorFont: majorFont,
      minorFont: minorFont,
    );
  }

  static String? _extractSchemeFont(XmlElement fontGroup) {
    final latin = _child(fontGroup, 'latin');
    final latinFace = latin != null ? _attr(latin, 'typeface') : null;
    if (latinFace != null && latinFace.trim().isNotEmpty) {
      return latinFace.trim();
    }
    for (final fallbackName in const ['ea', 'cs']) {
      final child = _child(fontGroup, fallbackName);
      final face = child != null ? _attr(child, 'typeface') : null;
      if (face != null && face.trim().isNotEmpty) {
        return face.trim();
      }
    }
    return null;
  }

  String? resolveThemeColor(
    String? themeColorName,
    String? tintHex,
    String? shadeHex,
  ) {
    if (themeColorName == null || themeColorName.isEmpty) return null;
    final lower = themeColorName.toLowerCase();
    final mappedKey = switch (lower) {
      'text1' => 'dk1',
      'background1' => 'lt1',
      'text2' => 'dk2',
      'background2' => 'lt2',
      'hyperlink' => 'hlink',
      'followedhyperlink' => 'folhlink',
      _ => lower,
    };
    final baseHex = colors[mappedKey] ?? colors[lower];
    if (baseHex == null) return null;

    var r = int.parse(baseHex.substring(0, 2), radix: 16).toDouble();
    var g = int.parse(baseHex.substring(2, 4), radix: 16).toDouble();
    var b = int.parse(baseHex.substring(4, 6), radix: 16).toDouble();

    if (tintHex != null && tintHex.isNotEmpty) {
      final tintVal = int.tryParse(tintHex, radix: 16);
      if (tintVal != null) {
        final t = tintVal.clamp(0, 255) / 255.0;
        r = r * t + 255.0 * (1.0 - t);
        g = g * t + 255.0 * (1.0 - t);
        b = b * t + 255.0 * (1.0 - t);
      }
    }

    if (shadeHex != null && shadeHex.isNotEmpty) {
      final shadeVal = int.tryParse(shadeHex, radix: 16);
      if (shadeVal != null) {
        final s = shadeVal.clamp(0, 255) / 255.0;
        r *= s;
        g *= s;
        b *= s;
      }
    }

    String toHex(double channel) =>
        channel.round().clamp(0, 255).toRadixString(16).padLeft(2, '0').toUpperCase();
    return '${toHex(r)}${toHex(g)}${toHex(b)}';
  }

  String? resolveThemeFont(String? themeFontRef) {
    if (themeFontRef == null || themeFontRef.isEmpty) return null;
    final lower = themeFontRef.toLowerCase();
    if (lower.startsWith('major')) return majorFont;
    if (lower.startsWith('minor')) return minorFont;
    return null;
  }

  /// Resolves a DrawingML `<a:solidFill>` or color reference element (`srgbClr`/`schemeClr`).
  String? resolveDrawingColorContainer(XmlElement? container) {
    if (container == null) return null;
    final srgb = _child(container, 'srgbClr');
    if (srgb != null) {
      final base = _normalizeHexColor(_attr(srgb, 'val'));
      if (base != null) return _applyDrawingModifiers(base, srgb);
    }
    final schemeClr = _child(container, 'schemeClr');
    if (schemeClr != null) {
      final schemeKey = (_attr(schemeClr, 'val') ?? '').toLowerCase();
      final mapped = switch (schemeKey) {
        'tx1' => 'dk1',
        'bg1' => 'lt1',
        'tx2' => 'dk2',
        'bg2' => 'lt2',
        _ => schemeKey,
      };
      final base = colors[mapped] ?? colors[schemeKey];
      if (base != null) return _applyDrawingModifiers(base, schemeClr);
    }
    return null;
  }

  static String _applyDrawingModifiers(String baseHex, XmlElement colorEl) {
    var r = int.parse(baseHex.substring(0, 2), radix: 16).toDouble();
    var g = int.parse(baseHex.substring(2, 4), radix: 16).toDouble();
    var b = int.parse(baseHex.substring(4, 6), radix: 16).toDouble();

    final tintEl = _child(colorEl, 'tint');
    if (tintEl != null) {
      final pct = double.tryParse(_attr(tintEl, 'val') ?? '');
      if (pct != null) {
        final t = (pct / 100000.0).clamp(0.0, 1.0);
        r = r * t + 255.0 * (1.0 - t);
        g = g * t + 255.0 * (1.0 - t);
        b = b * t + 255.0 * (1.0 - t);
      }
    }

    final shadeEl = _child(colorEl, 'shade');
    if (shadeEl != null) {
      final pct = double.tryParse(_attr(shadeEl, 'val') ?? '');
      if (pct != null) {
        final s = (pct / 100000.0).clamp(0.0, 1.0);
        r *= s;
        g *= s;
        b *= s;
      }
    }

    final lumModEl = _child(colorEl, 'lumMod');
    final lumOffEl = _child(colorEl, 'lumOff');
    if (lumModEl != null || lumOffEl != null) {
      final mod =
          (double.tryParse(lumModEl != null ? (_attr(lumModEl, 'val') ?? '') : '') ??
                  100000.0) /
              100000.0;
      final off =
          (double.tryParse(lumOffEl != null ? (_attr(lumOffEl, 'val') ?? '') : '') ??
                  0.0) /
              100000.0;
      r = r * mod + 255.0 * off;
      g = g * mod + 255.0 * off;
      b = b * mod + 255.0 * off;
    }

    String toHex(double c) =>
        c.round().clamp(0, 255).toRadixString(16).padLeft(2, '0').toUpperCase();
    return '${toHex(r)}${toHex(g)}${toHex(b)}';
  }
}

class _RawRPr {
  const _RawRPr({
    this.rStyleId,
    this.bold,
    this.italic,
    this.underline,
    this.strikethrough,
    this.allCaps,
    this.smallCaps,
    this.fontSizePt,
    this.colorHex,
    this.highlightHex,
    this.shadingColorHex,
    this.fontFamily,
    this.vertAlign,
    this.letterSpacingPt,
  });

  final String? rStyleId;
  final bool? bold;
  final bool? italic;
  final bool? underline;
  final bool? strikethrough;
  final bool? allCaps;
  final bool? smallCaps;
  final double? fontSizePt;
  final String? colorHex;
  final String? highlightHex;
  final String? shadingColorHex;
  final String? fontFamily;
  final String? vertAlign;
  final double? letterSpacingPt;

  static _RawRPr parse(XmlElement? rPr, _WordTheme theme) {
    if (rPr == null) return const _RawRPr();

    final rStyleEl = _child(rPr, 'rStyle');
    final rStyleId = rStyleEl != null ? _attr(rStyleEl, 'val') : null;

    final bold = _parseToggleAttr(_child(rPr, 'b'));
    final italic = _parseToggleAttr(_child(rPr, 'i'));

    bool? underline;
    final uEl = _child(rPr, 'u');
    if (uEl != null) {
      final val = _attr(uEl, 'val')?.toLowerCase();
      underline = val == null || (val != 'none' && val != '0' && val != 'false');
    }

    bool? strikethrough;
    final strikeEl = _child(rPr, 'strike') ?? _child(rPr, 'dstrike');
    if (strikeEl != null) {
      strikethrough = _parseToggleAttr(strikeEl);
    }

    final allCaps = _parseToggleAttr(_child(rPr, 'caps'));
    final smallCaps = _parseToggleAttr(_child(rPr, 'smallCaps'));

    double? fontSizePt;
    final szEl = _child(rPr, 'sz');
    if (szEl != null) {
      final halfPts = double.tryParse(_attr(szEl, 'val') ?? '');
      if (halfPts != null && halfPts > 0) {
        fontSizePt = halfPts / 2.0;
      }
    }

    String? colorHex;
    final colorEl = _child(rPr, 'color');
    if (colorEl != null) {
      colorHex = _normalizeHexColor(_attr(colorEl, 'val'));
      colorHex ??= theme.resolveThemeColor(
        _attr(colorEl, 'themeColor'),
        _attr(colorEl, 'themeTint'),
        _attr(colorEl, 'themeShade'),
      );
    }

    String? highlightHex;
    final highlightEl = _child(rPr, 'highlight');
    if (highlightEl != null) {
      final val = _attr(highlightEl, 'val');
      if (val != null && val.toLowerCase() != 'none') {
        highlightHex = val;
      }
    }

    final shadingColorHex = _parseShadingHex(_child(rPr, 'shd'), theme);

    String? fontFamily;
    final rFontsEl = _child(rPr, 'rFonts');
    if (rFontsEl != null) {
      fontFamily = _attr(rFontsEl, 'ascii') ??
          _attr(rFontsEl, 'hAnsi') ??
          _attr(rFontsEl, 'cs') ??
          _attr(rFontsEl, 'eastAsia') ??
          theme.resolveThemeFont(
            _attr(rFontsEl, 'asciiTheme') ??
                _attr(rFontsEl, 'hAnsiTheme') ??
                _attr(rFontsEl, 'cstheme') ??
                _attr(rFontsEl, 'eastAsiaTheme'),
          );
      if (fontFamily != null && fontFamily.trim().isEmpty) {
        fontFamily = null;
      }
    }

    String? vertAlign;
    final vertAlignEl = _child(rPr, 'vertAlign');
    if (vertAlignEl != null) {
      vertAlign = _attr(vertAlignEl, 'val')?.toLowerCase();
    }

    double? letterSpacingPt;
    final spacingEl = _child(rPr, 'spacing');
    if (spacingEl != null) {
      final dxa = double.tryParse(_attr(spacingEl, 'val') ?? '');
      if (dxa != null) {
        letterSpacingPt = dxa / 20.0;
      }
    }

    return _RawRPr(
      rStyleId: rStyleId,
      bold: bold,
      italic: italic,
      underline: underline,
      strikethrough: strikethrough,
      allCaps: allCaps,
      smallCaps: smallCaps,
      fontSizePt: fontSizePt,
      colorHex: colorHex,
      highlightHex: highlightHex,
      shadingColorHex: shadingColorHex,
      fontFamily: fontFamily,
      vertAlign: vertAlign,
      letterSpacingPt: letterSpacingPt,
    );
  }

  _RawRPr mergeOver(_RawRPr base) {
    return _RawRPr(
      rStyleId: rStyleId ?? base.rStyleId,
      bold: bold ?? base.bold,
      italic: italic ?? base.italic,
      underline: underline ?? base.underline,
      strikethrough: strikethrough ?? base.strikethrough,
      allCaps: allCaps ?? base.allCaps,
      smallCaps: smallCaps ?? base.smallCaps,
      fontSizePt: fontSizePt ?? base.fontSizePt,
      colorHex: colorHex ?? base.colorHex,
      highlightHex: highlightHex ?? base.highlightHex,
      shadingColorHex: shadingColorHex ?? base.shadingColorHex,
      fontFamily: fontFamily ?? base.fontFamily,
      vertAlign: vertAlign ?? base.vertAlign,
      letterSpacingPt: letterSpacingPt ?? base.letterSpacingPt,
    );
  }
}

class _RawPPr {
  const _RawPPr({
    this.pStyleId,
    this.alignment,
    this.indentLeftPt,
    this.indentRightPt,
    this.firstLineIndentPt,
    this.spaceBeforePt,
    this.spaceAfterPt,
    this.lineSpacingMultiplier,
    this.lineSpacingExactPt,
    this.backgroundColorHex,
    this.borders,
    this.numId,
    this.ilvl,
    this.outlineLvl,
    this.pageBreakBefore,
    this.isRightToLeft,
    this.pMarkRPr = const _RawRPr(),
  });

  final String? pStyleId;
  final TextAlign? alignment;
  final double? indentLeftPt;
  final double? indentRightPt;
  final double? firstLineIndentPt;
  final double? spaceBeforePt;
  final double? spaceAfterPt;
  final double? lineSpacingMultiplier;
  final double? lineSpacingExactPt;
  final String? backgroundColorHex;
  final WordBorders? borders;
  final String? numId;
  final int? ilvl;
  final int? outlineLvl;
  final bool? pageBreakBefore;
  final bool? isRightToLeft;
  final _RawRPr pMarkRPr;

  static _RawPPr parse(XmlElement? pPr, _WordTheme theme) {
    if (pPr == null) return const _RawPPr();

    final pStyleEl = _child(pPr, 'pStyle');
    final pStyleId = pStyleEl != null ? _attr(pStyleEl, 'val') : null;

    final jcEl = _child(pPr, 'jc');
    final alignment = jcEl != null ? _parseJcValue(_attr(jcEl, 'val')) : null;

    double? indentLeftPt;
    double? indentRightPt;
    double? firstLineIndentPt;
    final indEl = _child(pPr, 'ind');
    if (indEl != null) {
      final leftStr = _attr(indEl, 'left') ?? _attr(indEl, 'start');
      if (leftStr != null) {
        final dxa = double.tryParse(leftStr);
        if (dxa != null) indentLeftPt = dxa / 20.0;
      }
      final rightStr = _attr(indEl, 'right') ?? _attr(indEl, 'end');
      if (rightStr != null) {
        final dxa = double.tryParse(rightStr);
        if (dxa != null) indentRightPt = dxa / 20.0;
      }
      final firstLineStr = _attr(indEl, 'firstLine');
      if (firstLineStr != null) {
        final dxa = double.tryParse(firstLineStr);
        if (dxa != null) firstLineIndentPt = dxa / 20.0;
      } else {
        final hangingStr = _attr(indEl, 'hanging');
        if (hangingStr != null) {
          final dxa = double.tryParse(hangingStr);
          if (dxa != null) firstLineIndentPt = -(dxa / 20.0);
        }
      }
    }

    double? spaceBeforePt;
    double? spaceAfterPt;
    double? lineSpacingMultiplier;
    double? lineSpacingExactPt;
    final spacingEl = _child(pPr, 'spacing');
    if (spacingEl != null) {
      final beforeStr = _attr(spacingEl, 'before');
      if (beforeStr != null) {
        final dxa = double.tryParse(beforeStr);
        if (dxa != null) spaceBeforePt = dxa / 20.0;
      } else if (_attr(spacingEl, 'beforeAutospacing') == '1') {
        spaceBeforePt = 12.0;
      }

      final afterStr = _attr(spacingEl, 'after');
      if (afterStr != null) {
        final dxa = double.tryParse(afterStr);
        if (dxa != null) spaceAfterPt = dxa / 20.0;
      } else if (_attr(spacingEl, 'afterAutospacing') == '1') {
        spaceAfterPt = 12.0;
      }

      final lineStr = _attr(spacingEl, 'line');
      if (lineStr != null) {
        final lineVal = double.tryParse(lineStr);
        if (lineVal != null && lineVal > 0) {
          final lineRule = (_attr(spacingEl, 'lineRule') ?? 'auto').toLowerCase();
          if (lineRule == 'exact' || lineRule == 'atleast') {
            lineSpacingExactPt = lineVal / 20.0;
          } else {
            lineSpacingMultiplier = lineVal / 240.0;
          }
        }
      }
    }

    final backgroundColorHex = _parseShadingHex(_child(pPr, 'shd'), theme);
    final borders = _parseBorders(_child(pPr, 'pBdr'), theme);

    String? numId;
    int? ilvl;
    final numPrEl = _child(pPr, 'numPr');
    if (numPrEl != null) {
      final numIdEl = _child(numPrEl, 'numId');
      if (numIdEl != null) {
        numId = _attr(numIdEl, 'val');
      }
      final ilvlEl = _child(numPrEl, 'ilvl');
      if (ilvlEl != null) {
        ilvl = int.tryParse(_attr(ilvlEl, 'val') ?? '');
      }
      numId ??= '__implicit__';
    }

    int? outlineLvl;
    final outlineEl = _child(pPr, 'outlineLvl');
    if (outlineEl != null) {
      outlineLvl = int.tryParse(_attr(outlineEl, 'val') ?? '');
    }

    final pageBreakBefore = _parseToggleAttr(_child(pPr, 'pageBreakBefore'));
    final isRightToLeft = _parseToggleAttr(_child(pPr, 'bidi'));
    final pMarkRPr = _RawRPr.parse(_child(pPr, 'rPr'), theme);

    return _RawPPr(
      pStyleId: pStyleId,
      alignment: alignment,
      indentLeftPt: indentLeftPt,
      indentRightPt: indentRightPt,
      firstLineIndentPt: firstLineIndentPt,
      spaceBeforePt: spaceBeforePt,
      spaceAfterPt: spaceAfterPt,
      lineSpacingMultiplier: lineSpacingMultiplier,
      lineSpacingExactPt: lineSpacingExactPt,
      backgroundColorHex: backgroundColorHex,
      borders: borders,
      numId: numId,
      ilvl: ilvl,
      outlineLvl: outlineLvl,
      pageBreakBefore: pageBreakBefore,
      isRightToLeft: isRightToLeft,
      pMarkRPr: pMarkRPr,
    );
  }

  _RawPPr mergeOver(_RawPPr base) {
    return _RawPPr(
      pStyleId: pStyleId ?? base.pStyleId,
      alignment: alignment ?? base.alignment,
      indentLeftPt: indentLeftPt ?? base.indentLeftPt,
      indentRightPt: indentRightPt ?? base.indentRightPt,
      firstLineIndentPt: firstLineIndentPt ?? base.firstLineIndentPt,
      spaceBeforePt: spaceBeforePt ?? base.spaceBeforePt,
      spaceAfterPt: spaceAfterPt ?? base.spaceAfterPt,
      lineSpacingMultiplier:
          lineSpacingMultiplier ?? base.lineSpacingMultiplier,
      lineSpacingExactPt: lineSpacingExactPt ?? base.lineSpacingExactPt,
      backgroundColorHex: backgroundColorHex ?? base.backgroundColorHex,
      borders: borders != null ? borders!.mergeOver(base.borders) : base.borders,
      numId: numId ?? base.numId,
      ilvl: ilvl ?? base.ilvl,
      outlineLvl: outlineLvl ?? base.outlineLvl,
      pageBreakBefore: pageBreakBefore ?? base.pageBreakBefore,
      isRightToLeft: isRightToLeft ?? base.isRightToLeft,
      pMarkRPr: pMarkRPr.mergeOver(base.pMarkRPr),
    );
  }
}

class _RawTcProps {
  const _RawTcProps({
    this.backgroundColorHex,
    this.borders,
    this.verticalAlignment,
    this.paddingTopPt,
    this.paddingBottomPt,
    this.paddingLeftPt,
    this.paddingRightPt,
  });

  final String? backgroundColorHex;
  final WordBorders? borders;
  final String? verticalAlignment;
  final double? paddingTopPt;
  final double? paddingBottomPt;
  final double? paddingLeftPt;
  final double? paddingRightPt;

  static _RawTcProps parse(XmlElement? tcPr, _WordTheme theme) {
    if (tcPr == null) return const _RawTcProps();
    final bg = _parseShadingHex(_child(tcPr, 'shd'), theme);
    final borders = _parseBorders(_child(tcPr, 'tcBorders'), theme);
    final vAlignEl = _child(tcPr, 'vAlign');
    final vAlign = vAlignEl != null ? _attr(vAlignEl, 'val')?.toLowerCase() : null;
    final mar = _parseCellMargins(_child(tcPr, 'tcMar'));
    return _RawTcProps(
      backgroundColorHex: bg,
      borders: borders,
      verticalAlignment: vAlign,
      paddingTopPt: mar.top,
      paddingBottomPt: mar.bottom,
      paddingLeftPt: mar.left,
      paddingRightPt: mar.right,
    );
  }

  _RawTcProps mergeOver(_RawTcProps base) {
    return _RawTcProps(
      backgroundColorHex: backgroundColorHex ?? base.backgroundColorHex,
      borders: borders != null ? borders!.mergeOver(base.borders) : base.borders,
      verticalAlignment: verticalAlignment ?? base.verticalAlignment,
      paddingTopPt: paddingTopPt ?? base.paddingTopPt,
      paddingBottomPt: paddingBottomPt ?? base.paddingBottomPt,
      paddingLeftPt: paddingLeftPt ?? base.paddingLeftPt,
      paddingRightPt: paddingRightPt ?? base.paddingRightPt,
    );
  }
}

class _TblStyleConditional {
  const _TblStyleConditional({
    this.pPr = const _RawPPr(),
    this.rPr = const _RawRPr(),
    this.tcProps = const _RawTcProps(),
  });

  final _RawPPr pPr;
  final _RawRPr rPr;
  final _RawTcProps tcProps;
}

class _WordStyleDef {
  const _WordStyleDef({
    required this.styleId,
    required this.type,
    this.name,
    this.basedOn,
    this.isDefault = false,
    this.pPr = const _RawPPr(),
    this.rPr = const _RawRPr(),
    this.tblBorders,
    this.tblCellPadding = (top: null, bottom: null, left: null, right: null),
    this.tcProps = const _RawTcProps(),
    this.conditionals = const {},
  });

  final String styleId;
  final String type; // paragraph, character, table, numbering
  final String? name;
  final String? basedOn;
  final bool isDefault;
  final _RawPPr pPr;
  final _RawRPr rPr;
  final WordBorders? tblBorders;
  final ({double? top, double? bottom, double? left, double? right}) tblCellPadding;
  final _RawTcProps tcProps;
  final Map<String, _TblStyleConditional> conditionals;
}

class _WordStyleSheet {
  const _WordStyleSheet({
    this.docDefaultsPPr = const _RawPPr(),
    this.docDefaultsRPr = const _RawRPr(),
    this.styles = const {},
    this.defaultParagraphStyleId,
    this.defaultTableStyleId,
  });

  final _RawPPr docDefaultsPPr;
  final _RawRPr docDefaultsRPr;
  final Map<String, _WordStyleDef> styles;
  final String? defaultParagraphStyleId;
  final String? defaultTableStyleId;

  static _WordStyleSheet parse(String xmlContent, _WordTheme theme) {
    final doc = XmlDocument.parse(xmlContent);
    final root = doc.rootElement;

    var docDefaultsPPr = const _RawPPr();
    var docDefaultsRPr = const _RawRPr();
    final docDefaultsEl = _child(root, 'docDefaults');
    if (docDefaultsEl != null) {
      final pPrDef = _child(docDefaultsEl, 'pPrDefault');
      if (pPrDef != null) {
        docDefaultsPPr = _RawPPr.parse(_child(pPrDef, 'pPr'), theme);
      }
      final rPrDef = _child(docDefaultsEl, 'rPrDefault');
      if (rPrDef != null) {
        docDefaultsRPr = _RawRPr.parse(_child(rPrDef, 'rPr'), theme);
      }
    }

    final styles = <String, _WordStyleDef>{};
    String? defaultParagraphStyleId;
    String? defaultTableStyleId;

    for (final styleEl in _children(root, 'style')) {
      final styleId = _attr(styleEl, 'styleId');
      if (styleId == null || styleId.isEmpty) continue;

      final type = (_attr(styleEl, 'type') ?? 'paragraph').toLowerCase();
      final isDefault = _attr(styleEl, 'default') == '1' ||
          _attr(styleEl, 'default')?.toLowerCase() == 'true';
      final nameEl = _child(styleEl, 'name');
      final name = nameEl != null ? _attr(nameEl, 'val') : null;
      final basedOnEl = _child(styleEl, 'basedOn');
      final basedOn = basedOnEl != null ? _attr(basedOnEl, 'val') : null;

      final pPr = _RawPPr.parse(_child(styleEl, 'pPr'), theme);
      final rPr = _RawRPr.parse(_child(styleEl, 'rPr'), theme);

      WordBorders? tblBorders;
      ({double? top, double? bottom, double? left, double? right}) tblCellPadding =
          (top: null, bottom: null, left: null, right: null);
      final tblPrEl = _child(styleEl, 'tblPr');
      if (tblPrEl != null) {
        tblBorders = _parseBorders(_child(tblPrEl, 'tblBorders'), theme);
        tblCellPadding = _parseCellMargins(_child(tblPrEl, 'tblCellMar'));
      }
      final tcProps = _RawTcProps.parse(_child(styleEl, 'tcPr'), theme);

      final conditionals = <String, _TblStyleConditional>{};
      for (final condEl in _children(styleEl, 'tblStylePr')) {
        final condType = _attr(condEl, 'type')?.toLowerCase();
        if (condType == null || condType.isEmpty) continue;
        conditionals[condType] = _TblStyleConditional(
          pPr: _RawPPr.parse(_child(condEl, 'pPr'), theme),
          rPr: _RawRPr.parse(_child(condEl, 'rPr'), theme),
          tcProps: _RawTcProps.parse(_child(condEl, 'tcPr'), theme),
        );
      }

      if (isDefault && type == 'paragraph') {
        defaultParagraphStyleId = styleId;
      } else if (isDefault && type == 'table') {
        defaultTableStyleId = styleId;
      }

      styles[styleId] = _WordStyleDef(
        styleId: styleId,
        type: type,
        name: name,
        basedOn: basedOn,
        isDefault: isDefault,
        pPr: pPr,
        rPr: rPr,
        tblBorders: tblBorders,
        tblCellPadding: tblCellPadding,
        tcProps: tcProps,
        conditionals: conditionals,
      );
    }

    defaultParagraphStyleId ??= styles.containsKey('Normal') ? 'Normal' : null;

    return _WordStyleSheet(
      docDefaultsPPr: docDefaultsPPr,
      docDefaultsRPr: docDefaultsRPr,
      styles: styles,
      defaultParagraphStyleId: defaultParagraphStyleId,
      defaultTableStyleId: defaultTableStyleId,
    );
  }

  List<_WordStyleDef> _chain(String? styleId) {
    if (styleId == null || !styles.containsKey(styleId)) return const [];
    final visited = <String>{};
    final reversed = <_WordStyleDef>[];
    String? currentId = styleId;
    var depth = 0;
    while (currentId != null && depth < 16 && !visited.contains(currentId)) {
      final def = styles[currentId];
      if (def == null) break;
      visited.add(currentId);
      reversed.add(def);
      currentId = def.basedOn;
      depth++;
    }
    return reversed.reversed.toList();
  }

  _RawPPr resolveParagraphPPr(String? pStyleId, _RawPPr directPPr) {
    var acc = docDefaultsPPr;
    final effectiveStyleId = pStyleId ?? defaultParagraphStyleId;
    for (final def in _chain(effectiveStyleId)) {
      acc = def.pPr.mergeOver(acc);
    }
    return directPPr.mergeOver(acc);
  }

  _RawRPr resolveParagraphBaseRPr(
    String? pStyleId, {
    _RawRPr? tableRunOverride,
  }) {
    var acc = docDefaultsRPr;
    if (defaultParagraphStyleId != null) {
      for (final def in _chain(defaultParagraphStyleId)) {
        acc = def.rPr.mergeOver(acc);
      }
    }
    if (tableRunOverride != null) {
      acc = tableRunOverride.mergeOver(acc);
    }
    if (pStyleId != null && pStyleId != defaultParagraphStyleId) {
      for (final def in _chain(pStyleId)) {
        if (def.styleId == defaultParagraphStyleId) continue;
        acc = def.rPr.mergeOver(acc);
      }
    }
    return acc;
  }

  _RawRPr resolveCharacterStyleRPr(String? rStyleId) {
    var acc = const _RawRPr();
    for (final def in _chain(rStyleId)) {
      acc = def.rPr.mergeOver(acc);
    }
    return acc;
  }

  ({
    WordBorders? tblBorders,
    ({double? top, double? bottom, double? left, double? right}) cellPadding,
    _RawTcProps baseTcProps,
    _RawRPr baseRPr,
    Map<String, _TblStyleConditional> conditionals,
  }) resolveTableStyle(String? tblStyleId) {
    final effectiveId = tblStyleId ?? defaultTableStyleId;
    WordBorders? borders;
    ({double? top, double? bottom, double? left, double? right}) padding =
        (top: null, bottom: null, left: null, right: null);
    var tcProps = const _RawTcProps();
    var rPr = const _RawRPr();
    final conditionals = <String, _TblStyleConditional>{};

    for (final def in _chain(effectiveId)) {
      if (def.tblBorders != null) {
        borders = def.tblBorders!.mergeOver(borders);
      }
      padding = (
        top: def.tblCellPadding.top ?? padding.top,
        bottom: def.tblCellPadding.bottom ?? padding.bottom,
        left: def.tblCellPadding.left ?? padding.left,
        right: def.tblCellPadding.right ?? padding.right,
      );
      tcProps = def.tcProps.mergeOver(tcProps);
      rPr = def.rPr.mergeOver(rPr);
      for (final entry in def.conditionals.entries) {
        final prev = conditionals[entry.key];
        conditionals[entry.key] = prev == null
            ? entry.value
            : _TblStyleConditional(
                pPr: entry.value.pPr.mergeOver(prev.pPr),
                rPr: entry.value.rPr.mergeOver(prev.rPr),
                tcProps: entry.value.tcProps.mergeOver(prev.tcProps),
              );
      }
    }

    return (
      tblBorders: borders,
      cellPadding: padding,
      baseTcProps: tcProps,
      baseRPr: rPr,
      conditionals: conditionals,
    );
  }

  int? resolveHeadingLevel(String? pStyleId, int? resolvedOutlineLvl) {
    if (resolvedOutlineLvl != null &&
        resolvedOutlineLvl >= 0 &&
        resolvedOutlineLvl <= 5) {
      return resolvedOutlineLvl + 1;
    }

    final candidates = <String>[];
    if (pStyleId != null) {
      candidates.add(pStyleId);
      for (final def in _chain(pStyleId).reversed) {
        if (def.name != null) candidates.add(def.name!);
        candidates.add(def.styleId);
      }
    }

    for (final raw in candidates) {
      final level = _headingLevelFromName(raw);
      if (level != null) return level;
    }
    return null;
  }

  static int? _headingLevelFromName(String raw) {
    final s = raw.trim().toLowerCase();
    if (s == 'title') return 1;
    if (s == 'subtitle') return 2;
    final compact = s.replaceAll(RegExp(r'[\s_-]+'), '');
    final headingMatch =
        RegExp(r'^(?:heading|titre|overskrift|rubrik|encabezado)(\d+)$')
            .firstMatch(compact);
    if (headingMatch != null) {
      final lvl = int.tryParse(headingMatch.group(1)!);
      if (lvl != null && lvl >= 1 && lvl <= 6) return lvl;
    }
    final digitOnly = int.tryParse(compact);
    if (digitOnly != null && digitOnly >= 1 && digitOnly <= 6) {
      return digitOnly;
    }
    return null;
  }

  double? resolveDefaultFontSizePt() {
    return resolveParagraphBaseRPr(null).fontSizePt;
  }

  String? resolveDefaultFontFamily() {
    return resolveParagraphBaseRPr(null).fontFamily;
  }
}

class _NumberingLevel {
  const _NumberingLevel({
    required this.ilvl,
    this.start = 1,
    this.numFmt = 'decimal',
    this.lvlText = '%1.',
    this.pPr = const _RawPPr(),
  });

  final int ilvl;
  final int start;
  final String numFmt;
  final String lvlText;
  final _RawPPr pPr;

  static _NumberingLevel parse(XmlElement lvlEl, _WordTheme theme) {
    final ilvl = int.tryParse(_attr(lvlEl, 'ilvl') ?? '') ?? 0;
    final startEl = _child(lvlEl, 'start');
    final start = int.tryParse(startEl != null ? (_attr(startEl, 'val') ?? '') : '') ?? 1;
    final fmtEl = _child(lvlEl, 'numFmt');
    final numFmt = (fmtEl != null ? _attr(fmtEl, 'val') : null) ?? 'decimal';
    final textEl = _child(lvlEl, 'lvlText');
    final lvlText = (textEl != null ? _attr(textEl, 'val') : null) ?? '%${ilvl + 1}.';
    final pPr = _RawPPr.parse(_child(lvlEl, 'pPr'), theme);
    return _NumberingLevel(
      ilvl: ilvl,
      start: start,
      numFmt: numFmt,
      lvlText: lvlText,
      pPr: pPr,
    );
  }
}

class _WordNumbering {
  _WordNumbering({
    required this.abstractLevels,
    required this.numToAbstract,
    required this.numOverrides,
  });

  final Map<String, Map<int, _NumberingLevel>> abstractLevels;
  final Map<String, String> numToAbstract;
  final Map<String, Map<int, _NumberingLevel>> numOverrides;
  final Map<String, Map<int, int>> _counters = {};

  factory _WordNumbering.empty() => _WordNumbering(
        abstractLevels: const {},
        numToAbstract: const {},
        numOverrides: const {},
      );

  factory _WordNumbering.parse(String xmlContent, _WordTheme theme) {
    final doc = XmlDocument.parse(xmlContent);
    final root = doc.rootElement;

    final abstractLevels = <String, Map<int, _NumberingLevel>>{};
    for (final absEl in _children(root, 'abstractNum')) {
      final absId = _attr(absEl, 'abstractNumId');
      if (absId == null) continue;
      final lvls = <int, _NumberingLevel>{};
      for (final lvlEl in _children(absEl, 'lvl')) {
        final lvl = _NumberingLevel.parse(lvlEl, theme);
        lvls[lvl.ilvl] = lvl;
      }
      abstractLevels[absId] = lvls;
    }

    final numToAbstract = <String, String>{};
    final numOverrides = <String, Map<int, _NumberingLevel>>{};
    for (final numEl in _children(root, 'num')) {
      final numId = _attr(numEl, 'numId');
      if (numId == null) continue;
      final absRef = _child(numEl, 'abstractNumId');
      final absId = absRef != null ? _attr(absRef, 'val') : null;
      if (absId != null) {
        numToAbstract[numId] = absId;
      }

      final overrides = <int, _NumberingLevel>{};
      for (final ovEl in _children(numEl, 'lvlOverride')) {
        final ilvl = int.tryParse(_attr(ovEl, 'ilvl') ?? '');
        if (ilvl == null) continue;
        final lvlEl = _child(ovEl, 'lvl');
        if (lvlEl != null) {
          overrides[ilvl] = _NumberingLevel.parse(lvlEl, theme);
        } else {
          final startOv = _child(ovEl, 'startOverride');
          final startVal =
              int.tryParse(startOv != null ? (_attr(startOv, 'val') ?? '') : '');
          if (startVal != null && absId != null) {
            final base = abstractLevels[absId]?[ilvl];
            if (base != null) {
              overrides[ilvl] = _NumberingLevel(
                ilvl: ilvl,
                start: startVal,
                numFmt: base.numFmt,
                lvlText: base.lvlText,
                pPr: base.pPr,
              );
            }
          }
        }
      }
      if (overrides.isNotEmpty) {
        numOverrides[numId] = overrides;
      }
    }

    return _WordNumbering(
      abstractLevels: abstractLevels,
      numToAbstract: numToAbstract,
      numOverrides: numOverrides,
    );
  }

  _NumberingLevel? levelFor(String numId, int ilvl) {
    final ov = numOverrides[numId]?[ilvl];
    if (ov != null) return ov;
    final absId = numToAbstract[numId];
    if (absId == null) return null;
    return abstractLevels[absId]?[ilvl];
  }

  ({String? marker, _RawPPr? levelPPr, bool isList}) nextMarker(
    String numId,
    int ilvl,
  ) {
    final lvl = levelFor(numId, ilvl);
    if (lvl == null) {
      return (marker: '•', levelPPr: null, isList: true);
    }

    final fmt = lvl.numFmt.toLowerCase();
    if (fmt == 'none') {
      return (marker: null, levelPPr: lvl.pPr, isList: false);
    }
    if (fmt == 'bullet') {
      return (
        marker: _mapBulletGlyph(lvl.lvlText),
        levelPPr: lvl.pPr,
        isList: true,
      );
    }

    final map = _counters.putIfAbsent(numId, () => {});
    // Reset deeper list levels whenever an ancestor level advances.
    map.removeWhere((k, _) => k > ilvl);
    final nextVal = map.containsKey(ilvl) ? map[ilvl]! + 1 : lvl.start;
    map[ilvl] = nextVal;

    var rendered = lvl.lvlText;
    for (int levelIdx = 0; levelIdx <= 8; levelIdx++) {
      final token = '%${levelIdx + 1}';
      if (!rendered.contains(token)) continue;
      final refLvl = levelFor(numId, levelIdx);
      final count = map[levelIdx] ?? refLvl?.start ?? 1;
      final formatted = _formatNumber(count, refLvl?.numFmt ?? 'decimal');
      rendered = rendered.replaceAll(token, formatted);
    }

    return (
      marker: rendered.trim().isEmpty ? '$nextVal.' : rendered,
      levelPPr: lvl.pPr,
      isList: true,
    );
  }

  static String _mapBulletGlyph(String raw) {
    if (raw.isEmpty) return '•';
    final code = raw.codeUnitAt(0);
    return switch (code) {
      0xF0B7 || 0x2022 => '•',
      0xF0A7 || 0xF0A8 || 0x25AA || 0x25A0 => '▪',
      0xF06F || 0x006F when raw.trim() == 'o' => '◦',
      0x25CB || 0x25E6 => '◦',
      0xF0D8 => '➢',
      0xF0FC => '✓',
      0xF076 => '❖',
      _ when code >= 0xE000 && code <= 0xF8FF => '•',
      _ => raw,
    };
  }

  static String _formatNumber(int value, String numFmt) {
    return switch (numFmt.toLowerCase()) {
      'lowerletter' => _toLetters(value, uppercase: false),
      'upperletter' => _toLetters(value, uppercase: true),
      'lowerroman' => _toRoman(value, uppercase: false),
      'upperroman' => _toRoman(value, uppercase: true),
      'decimalzero' => value < 10 ? '0$value' : '$value',
      _ => '$value',
    };
  }

  static String _toLetters(int n, {required bool uppercase}) {
    if (n <= 0) return '$n';
    var num = n;
    final sb = StringBuffer();
    while (num > 0) {
      num--;
      final base = uppercase ? 65 : 97;
      sb.writeCharCode(base + (num % 26));
      num ~/= 26;
    }
    return sb.toString().split('').reversed.join();
  }

  static String _toRoman(int n, {required bool uppercase}) {
    if (n <= 0 || n >= 4000) return '$n';
    const values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
    const numerals = [
      'M',
      'CM',
      'D',
      'CD',
      'C',
      'XC',
      'L',
      'XL',
      'X',
      'IX',
      'V',
      'IV',
      'I',
    ];
    var remaining = n;
    final sb = StringBuffer();
    for (int i = 0; i < values.length; i++) {
      while (remaining >= values[i]) {
        sb.write(numerals[i]);
        remaining -= values[i];
      }
    }
    final res = sb.toString();
    return uppercase ? res : res.toLowerCase();
  }
}

// ---------------------------------------------------------------------------
// Shared Low-Level OOXML Element Parsers
// ---------------------------------------------------------------------------

String? _parseShadingHex(XmlElement? shdEl, _WordTheme theme) {
  if (shdEl == null) return null;
  var hex = _normalizeHexColor(_attr(shdEl, 'fill'));
  hex ??= theme.resolveThemeColor(
    _attr(shdEl, 'themeFill'),
    _attr(shdEl, 'themeFillTint'),
    _attr(shdEl, 'themeFillShade'),
  );
  return hex;
}

WordBorder? _parseSingleBorder(XmlElement? el, _WordTheme theme) {
  if (el == null) return null;
  final val = (_attr(el, 'val') ?? 'single').toLowerCase();
  if (val == 'none' || val == 'nil') {
    return const WordBorder(style: 'none', widthPt: 0);
  }
  final eighthPts = double.tryParse(_attr(el, 'sz') ?? '');
  final widthPt = eighthPts != null ? math.max(0.25, eighthPts / 8.0) : 0.5;
  var colorHex = _normalizeHexColor(_attr(el, 'color'));
  colorHex ??= theme.resolveThemeColor(
    _attr(el, 'themeColor'),
    _attr(el, 'themeTint'),
    _attr(el, 'themeShade'),
  );
  colorHex ??= '000000';
  return WordBorder(
    colorHex: colorHex,
    widthPt: widthPt,
    style: val,
  );
}

WordBorders? _parseBorders(XmlElement? bdrEl, _WordTheme theme) {
  if (bdrEl == null) return null;
  final top = _parseSingleBorder(_child(bdrEl, 'top'), theme);
  final bottom = _parseSingleBorder(_child(bdrEl, 'bottom'), theme);
  final left =
      _parseSingleBorder(_child(bdrEl, 'left') ?? _child(bdrEl, 'start'), theme);
  final right =
      _parseSingleBorder(_child(bdrEl, 'right') ?? _child(bdrEl, 'end'), theme);
  final insideH = _parseSingleBorder(_child(bdrEl, 'insideH'), theme);
  final insideV = _parseSingleBorder(_child(bdrEl, 'insideV'), theme);
  if (top == null &&
      bottom == null &&
      left == null &&
      right == null &&
      insideH == null &&
      insideV == null) {
    return null;
  }
  return WordBorders(
    top: top,
    bottom: bottom,
    left: left,
    right: right,
    insideH: insideH,
    insideV: insideV,
  );
}

({double? top, double? bottom, double? left, double? right}) _parseCellMargins(
  XmlElement? marEl,
) {
  if (marEl == null) {
    return (top: null, bottom: null, left: null, right: null);
  }

  double? parseSide(List<String> names) {
    for (final name in names) {
      final el = _child(marEl, name);
      if (el != null) {
        final w = double.tryParse(_attr(el, 'w') ?? '');
        if (w != null) {
          final type = (_attr(el, 'type') ?? 'dxa').toLowerCase();
          if (type == 'dxa' || type.isEmpty) {
            return w / 20.0;
          }
        }
      }
    }
    return null;
  }

  return (
    top: parseSide(const ['top']),
    bottom: parseSide(const ['bottom']),
    left: parseSide(const ['left', 'start']),
    right: parseSide(const ['right', 'end']),
  );
}

// ---------------------------------------------------------------------------
// WordParser
// ---------------------------------------------------------------------------

class WordParser {
  const WordParser._();

  static const int _isolateThresholdBytes = 32 * 1024;

  static Future<WordDocument> parse(Uint8List bytes) async {
    if (!kIsWeb && bytes.length >= _isolateThresholdBytes) {
      return compute(parseSync, bytes);
    }
    return parseSync(bytes);
  }

  static ({
    Map<String, String> mediaMap,
    Map<String, String> linkMap,
    String? stylesPath,
    String? numberingPath,
    String? themePath,
  }) _parseRels(Archive archive, String relsPath, {String baseDir = 'word/'}) {
    final mediaMap = <String, String>{};
    final linkMap = <String, String>{};
    String? stylesPath;
    String? numberingPath;
    String? themePath;

    final relsFile = _findArchiveFile(archive, relsPath);
    if (relsFile == null) {
      return (
        mediaMap: mediaMap,
        linkMap: linkMap,
        stylesPath: stylesPath,
        numberingPath: numberingPath,
        themePath: themePath,
      );
    }

    final relsContent =
        EncodingUtils.decodeDocumentBytes(relsFile.content as List<int>);
    final relsDoc = XmlDocument.parse(relsContent);
    for (final rel in _descendants(relsDoc.rootElement, 'Relationship')) {
      final id = _attr(rel, 'Id');
      final target = _attr(rel, 'Target');
      final type = (_attr(rel, 'Type') ?? '').toLowerCase();
      if (id == null || target == null) continue;

      if (type.contains('hyperlink') ||
          _attr(rel, 'TargetMode')?.toLowerCase() == 'external') {
        linkMap[id] = target;
      }
      final resolved = _resolveRelPath(baseDir, target);
      mediaMap[id] = resolved;

      if (type.endsWith('/styles')) {
        stylesPath = resolved;
      } else if (type.endsWith('/numbering')) {
        numberingPath = resolved;
      } else if (type.endsWith('/theme')) {
        themePath = resolved;
      }
    }

    return (
      mediaMap: mediaMap,
      linkMap: linkMap,
      stylesPath: stylesPath,
      numberingPath: numberingPath,
      themePath: themePath,
    );
  }

  static String _resolveRelPath(String baseDir, String target) {
    var clean = target.replaceAll('\\', '/');
    while (clean.startsWith('./')) {
      clean = clean.substring(2);
    }
    if (clean.startsWith('/')) {
      return clean.substring(1);
    }
    if (clean.startsWith('word/')) {
      return clean;
    }
    final segments = baseDir
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();
    for (final part in clean.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (segments.isNotEmpty) segments.removeLast();
      } else {
        segments.add(part);
      }
    }
    return segments.join('/');
  }

  static String _relsPathForPart(String partPath) {
    final slash = partPath.lastIndexOf('/');
    final dir = slash >= 0 ? partPath.substring(0, slash + 1) : '';
    final file = slash >= 0 ? partPath.substring(slash + 1) : partPath;
    return '${dir}_rels/$file.rels';
  }

  static String _dirOfPart(String partPath) {
    final slash = partPath.lastIndexOf('/');
    return slash >= 0 ? partPath.substring(0, slash + 1) : '';
  }

  static WordDocument parseSync(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    final docRels = _parseRels(archive, 'word/_rels/document.xml.rels');
    final mediaMap = docRels.mediaMap;
    final linkMap = docRels.linkMap;

    var theme = const _WordTheme();
    final themeFile = _findArchiveFile(
      archive,
      docRels.themePath ?? 'word/theme/theme1.xml',
    );
    if (themeFile != null) {
      try {
        theme = _WordTheme.parse(
          EncodingUtils.decodeDocumentBytes(themeFile.content as List<int>),
        );
      } catch (_) {}
    }

    var styleSheet = const _WordStyleSheet();
    final stylesFile =
        _findArchiveFile(archive, docRels.stylesPath ?? 'word/styles.xml');
    if (stylesFile != null) {
      try {
        styleSheet = _WordStyleSheet.parse(
          EncodingUtils.decodeDocumentBytes(stylesFile.content as List<int>),
          theme,
        );
      } catch (_) {}
    }

    var numbering = _WordNumbering.empty();
    final numberingFile = _findArchiveFile(
      archive,
      docRels.numberingPath ?? 'word/numbering.xml',
    );
    if (numberingFile != null) {
      try {
        numbering = _WordNumbering.parse(
          EncodingUtils.decodeDocumentBytes(numberingFile.content as List<int>),
          theme,
        );
      } catch (_) {}
    }

    final docFile = _findArchiveFile(archive, 'word/document.xml');
    if (docFile == null) {
      return const WordDocument(blocks: []);
    }

    final docXml =
        EncodingUtils.decodeDocumentBytes(docFile.content as List<int>);
    final doc = XmlDocument.parse(docXml);
    final rootEl = doc.rootElement;
    final body = _child(rootEl, 'body');
    if (body == null) return const WordDocument(blocks: []);

    final pageInfo = _parsePageSettings(rootEl, body, theme);
    final pageSettings = pageInfo.settings;

    final ctx = _ParseContext(
      archive: archive,
      mediaMap: mediaMap,
      linkMap: linkMap,
      theme: theme,
      styleSheet: styleSheet,
      numbering: numbering,
      pageSettings: pageSettings,
    );

    final blocks = ctx.parseContainerChildren(body);
    final totalPages = ctx.currentPageIndex + 1;

    final headerBlocks = <WordBlock>[];
    final footerBlocks = <WordBlock>[];

    void parseHeaderOrFooter({
      required String? relId,
      required bool isHeader,
      required List<int> targetPages,
      required bool collectFlowBlocks,
    }) {
      if (relId == null) return;
      final partPath = mediaMap[relId];
      if (partPath == null) return;
      final partFile = _findArchiveFile(archive, partPath);
      if (partFile == null) return;

      final partRels = _parseRels(
        archive,
        _relsPathForPart(partPath),
        baseDir: _dirOfPart(partPath),
      );
      final partMedia = {...mediaMap, ...partRels.mediaMap};
      final partLinks = {...linkMap, ...partRels.linkMap};

      final partXml =
          EncodingUtils.decodeDocumentBytes(partFile.content as List<int>);
      final partDoc = XmlDocument.parse(partXml);

      final subCtx = _ParseContext(
        archive: archive,
        mediaMap: partMedia,
        linkMap: partLinks,
        theme: theme,
        styleSheet: styleSheet,
        numbering: numbering,
        pageSettings: pageSettings,
        fixedFloatingPageIndex: targetPages.length == 1 ? targetPages.first : -1,
        initialYOnPagePt: isHeader
            ? 36.0
            : math.max(36.0, pageSettings.heightPt - pageSettings.marginBottomPt),
      );

      final parsedFlow = subCtx.parseContainerChildren(partDoc.rootElement);
      if (collectFlowBlocks) {
        for (final b in parsedFlow) {
          if (b is WordParagraph && b.isEmptySpacer && b.borders == null) {
            continue;
          }
          (isHeader ? headerBlocks : footerBlocks).add(b);
        }
      }

      if (targetPages.length == 1) {
        ctx.floatingElements.addAll(
          subCtx.floatingElements.map(
            (e) => e.copyWithPageIndex(targetPages.first),
          ),
        );
      } else {
        for (final pIdx in targetPages) {
          ctx.floatingElements.addAll(
            subCtx.floatingElements.map((e) => e.copyWithPageIndex(pIdx)),
          );
        }
      }
    }

    if (pageInfo.hasTitlePage) {
      parseHeaderOrFooter(
        relId: pageInfo.headerIds['first'],
        isHeader: true,
        targetPages: const [0],
        collectFlowBlocks: totalPages == 1,
      );
      parseHeaderOrFooter(
        relId: pageInfo.footerIds['first'],
        isHeader: false,
        targetPages: const [0],
        collectFlowBlocks: totalPages == 1,
      );
      if (totalPages > 1) {
        final restPages = List<int>.generate(totalPages - 1, (i) => i + 1);
        parseHeaderOrFooter(
          relId: pageInfo.headerIds['default'],
          isHeader: true,
          targetPages: restPages,
          collectFlowBlocks: true,
        );
        parseHeaderOrFooter(
          relId: pageInfo.footerIds['default'],
          isHeader: false,
          targetPages: restPages,
          collectFlowBlocks: true,
        );
      }
    } else {
      parseHeaderOrFooter(
        relId: pageInfo.headerIds['default'] ?? pageInfo.headerIds['first'],
        isHeader: true,
        targetPages: const [-1],
        collectFlowBlocks: true,
      );
      parseHeaderOrFooter(
        relId: pageInfo.footerIds['default'] ?? pageInfo.footerIds['first'],
        isHeader: false,
        targetPages: const [-1],
        collectFlowBlocks: true,
      );
    }

    return WordDocument(
      blocks: blocks,
      pageSettings: pageSettings,
      defaultFontSizePt: styleSheet.resolveDefaultFontSizePt(),
      defaultFontFamily: styleSheet.resolveDefaultFontFamily(),
      floatingElements: ctx.floatingElements,
      headerBlocks: headerBlocks,
      footerBlocks: footerBlocks,
    );
  }

  static ({
    WordPageSettings settings,
    Map<String, String> headerIds,
    Map<String, String> footerIds,
    bool hasTitlePage,
  }) _parsePageSettings(
    XmlElement documentRoot,
    XmlElement body,
    _WordTheme theme,
  ) {
    final bgEl = _child(documentRoot, 'background');
    String? bgHex;
    if (bgEl != null) {
      bgHex = _normalizeHexColor(_attr(bgEl, 'color'));
      bgHex ??= theme.resolveThemeColor(
        _attr(bgEl, 'themeColor'),
        _attr(bgEl, 'themeTint'),
        _attr(bgEl, 'themeShade'),
      );
    }

    var widthPt = 612.0;
    var heightPt = 792.0;
    var marginTopPt = 72.0;
    var marginBottomPt = 72.0;
    var marginLeftPt = 72.0;
    var marginRightPt = 72.0;
    WordBorders? pageBorders;
    final headerIds = <String, String>{};
    final footerIds = <String, String>{};
    var hasTitlePage = false;

    final sectPr = _child(body, 'sectPr') ??
        _descendants(body, 'sectPr').lastOrNull;
    if (sectPr != null) {
      final pgSz = _child(sectPr, 'pgSz');
      if (pgSz != null) {
        final w = double.tryParse(_attr(pgSz, 'w') ?? '');
        final h = double.tryParse(_attr(pgSz, 'h') ?? '');
        if (w != null && w > 0) widthPt = w / 20.0;
        if (h != null && h > 0) heightPt = h / 20.0;
      }
      final pgMar = _child(sectPr, 'pgMar');
      if (pgMar != null) {
        double? parseMar(String name) {
          final v = double.tryParse(_attr(pgMar, name) ?? '');
          return v != null && v >= 0 ? v / 20.0 : null;
        }

        marginTopPt = parseMar('top') ?? marginTopPt;
        marginBottomPt = parseMar('bottom') ?? marginBottomPt;
        marginLeftPt = parseMar('left') ?? marginLeftPt;
        marginRightPt = parseMar('right') ?? marginRightPt;
      }

      pageBorders = _parseBorders(_child(sectPr, 'pgBorders'), theme);
      hasTitlePage = _parseToggleAttr(_child(sectPr, 'titlePg')) ?? false;

      for (final hRef in _children(sectPr, 'headerReference')) {
        final rId = _attr(hRef, 'id');
        final type = (_attr(hRef, 'type') ?? 'default').toLowerCase();
        if (rId != null) headerIds[type] = rId;
      }
      for (final fRef in _children(sectPr, 'footerReference')) {
        final rId = _attr(fRef, 'id');
        final type = (_attr(fRef, 'type') ?? 'default').toLowerCase();
        if (rId != null) footerIds[type] = rId;
      }
    }

    return (
      settings: WordPageSettings(
        widthPt: widthPt,
        heightPt: heightPt,
        marginTopPt: marginTopPt,
        marginBottomPt: marginBottomPt,
        marginLeftPt: marginLeftPt,
        marginRightPt: marginRightPt,
        backgroundColorHex: bgHex,
        pageBorders: pageBorders,
      ),
      headerIds: headerIds,
      footerIds: footerIds,
      hasTitlePage: hasTitlePage,
    );
  }
}

class _ParseContext {
  _ParseContext({
    required this.archive,
    required this.mediaMap,
    required this.linkMap,
    required this.theme,
    required this.styleSheet,
    required this.numbering,
    required this.pageSettings,
    this.fixedFloatingPageIndex,
    double? initialYOnPagePt,
  }) : estimatedYOnPagePt = initialYOnPagePt ?? pageSettings.marginTopPt;

  final Archive archive;
  final Map<String, String> mediaMap;
  final Map<String, String> linkMap;
  final _WordTheme theme;
  final _WordStyleSheet styleSheet;
  final _WordNumbering numbering;
  final WordPageSettings pageSettings;
  final int? fixedFloatingPageIndex;

  int currentPageIndex = 0;
  double estimatedYOnPagePt;
  final List<WordFloatingElement> floatingElements = [];
  int _nextFallbackZ = 0;

  int get _activeFloatingPageIndex => fixedFloatingPageIndex ?? currentPageIndex;

  List<WordBlock> parseContainerChildren(
    XmlElement container, {
    _RawRPr? tableRunOverride,
  }) {
    final blocks = <WordBlock>[];
    for (final node in container.children) {
      if (node is! XmlElement) continue;
      final name = node.name.local;
      switch (name) {
        case 'p':
          blocks.addAll(_parseParagraph(node, tableRunOverride: tableRunOverride));
          break;
        case 'tbl':
          final tbl = _parseTable(node);
          if (tbl != null) {
            blocks.add(tbl);
            estimatedYOnPagePt += tbl.rows.length * 24.0;
          }
          break;
        case 'sdt':
          final sdtContent = _child(node, 'sdtContent');
          if (sdtContent != null) {
            blocks.addAll(
              parseContainerChildren(
                sdtContent,
                tableRunOverride: tableRunOverride,
              ),
            );
          }
          break;
        case 'customXml':
        case 'smartTag':
        case 'ins':
        case 'moveTo':
          blocks.addAll(
            parseContainerChildren(node, tableRunOverride: tableRunOverride),
          );
          break;
        case 'AlternateContent':
          final selected = _child(node, 'Choice') ?? _child(node, 'Fallback');
          if (selected != null) {
            blocks.addAll(
              parseContainerChildren(
                selected,
                tableRunOverride: tableRunOverride,
              ),
            );
          }
          break;
        default:
          // Skip deleted revisions, bookmarks, sectPr, etc.
          break;
      }
    }
    return blocks;
  }

  List<WordBlock> _parseParagraph(
    XmlElement pEl, {
    _RawRPr? tableRunOverride,
  }) {
    final directPPr = _RawPPr.parse(_child(pEl, 'pPr'), theme);
    var resolvedPPr = styleSheet.resolveParagraphPPr(
      directPPr.pStyleId,
      directPPr,
    );

    if (resolvedPPr.pageBreakBefore ?? false) {
      currentPageIndex++;
      estimatedYOnPagePt = pageSettings.marginTopPt;
    }

    final headingLevel = styleSheet.resolveHeadingLevel(
      directPPr.pStyleId,
      resolvedPPr.outlineLvl,
    );

    bool isBullet = false;
    String? listMarker;
    int listLevel = 0;

    final numId = resolvedPPr.numId;
    if (numId != null && numId != '0') {
      listLevel = resolvedPPr.ilvl ?? 0;
      if (numId == '__implicit__') {
        isBullet = true;
        listMarker = '•';
      } else {
        final listInfo = numbering.nextMarker(numId, listLevel);
        isBullet = listInfo.isList;
        listMarker = listInfo.marker;
        if (listInfo.levelPPr != null) {
          // Numbering level indentation applies unless direct pPr overrode it.
          resolvedPPr = _RawPPr(
            pStyleId: resolvedPPr.pStyleId,
            alignment: resolvedPPr.alignment,
            indentLeftPt: directPPr.indentLeftPt ??
                listInfo.levelPPr!.indentLeftPt ??
                resolvedPPr.indentLeftPt,
            indentRightPt: resolvedPPr.indentRightPt,
            firstLineIndentPt: directPPr.firstLineIndentPt ??
                listInfo.levelPPr!.firstLineIndentPt ??
                resolvedPPr.firstLineIndentPt,
            spaceBeforePt: resolvedPPr.spaceBeforePt,
            spaceAfterPt: resolvedPPr.spaceAfterPt,
            lineSpacingMultiplier: resolvedPPr.lineSpacingMultiplier,
            lineSpacingExactPt: resolvedPPr.lineSpacingExactPt,
            backgroundColorHex: resolvedPPr.backgroundColorHex,
            borders: resolvedPPr.borders,
            numId: resolvedPPr.numId,
            ilvl: resolvedPPr.ilvl,
            outlineLvl: resolvedPPr.outlineLvl,
            pageBreakBefore: resolvedPPr.pageBreakBefore,
            isRightToLeft: resolvedPPr.isRightToLeft,
            pMarkRPr: resolvedPPr.pMarkRPr,
          );
        }
      }
    }

    // Build base run style for runs inside this paragraph:
    // docDefaults -> default paragraph style -> table style -> explicit pStyle -> <w:pPr><w:rPr>
    var paraBaseRPr = styleSheet.resolveParagraphBaseRPr(
      directPPr.pStyleId,
      tableRunOverride: tableRunOverride,
    );
    paraBaseRPr = directPPr.pMarkRPr.mergeOver(paraBaseRPr);

    final outBlocks = <WordBlock>[];
    var currentSpans = <WordSpan>[];
    var emittedContentInParagraph = false;
    var emittedFloatingInParagraph = false;

    WordParagraph buildParagraphBlock(
      List<WordSpan> spans, {
      required bool isEmptySpacer,
      bool includePageBreakBefore = true,
    }) {
      return WordParagraph(
        spans: spans,
        headingLevel: headingLevel,
        isBullet: isBullet,
        alignment: resolvedPPr.alignment,
        indent: resolvedPPr.indentLeftPt,
        backgroundColorHex: resolvedPPr.backgroundColorHex,
        indentRight: resolvedPPr.indentRightPt,
        firstLineIndent: resolvedPPr.firstLineIndentPt,
        spaceBeforePt: resolvedPPr.spaceBeforePt,
        spaceAfterPt: resolvedPPr.spaceAfterPt,
        lineSpacingMultiplier: resolvedPPr.lineSpacingMultiplier,
        lineSpacingExactPt: resolvedPPr.lineSpacingExactPt,
        listMarker: listMarker,
        listLevel: listLevel,
        borders: resolvedPPr.borders,
        pageBreakBefore:
            includePageBreakBefore && (resolvedPPr.pageBreakBefore ?? false),
        isEmptySpacer: isEmptySpacer,
        defaultFontSize: paraBaseRPr.fontSizePt,
        isRightToLeft: resolvedPPr.isRightToLeft ?? false,
      );
    }

    void flushSpans() {
      if (currentSpans.isEmpty) return;
      outBlocks.add(
        buildParagraphBlock(
          currentSpans,
          isEmptySpacer: false,
          includePageBreakBefore: !emittedContentInParagraph,
        ),
      );
      emittedContentInParagraph = true;
      currentSpans = <WordSpan>[];
    }

    void extractDrawingsFromElement(XmlElement container) {
      void walk(XmlElement el) {
        final local = el.name.local;
        if (local == 'AlternateContent') {
          final chosen = _child(el, 'Choice') ?? _child(el, 'Fallback');
          if (chosen != null) walk(chosen);
          return;
        }
        if (local == 'drawing') {
          final anchor = _child(el, 'anchor');
          if (anchor != null) {
            final added = _parseAnchorDrawing(anchor);
            if (added) emittedFloatingInParagraph = true;
            return;
          }
          final inline = _child(el, 'inline');
          if (inline != null) {
            final inlineBlocks = _parseInlineDrawing(
              inline,
              alignment: resolvedPPr.alignment,
            );
            if (inlineBlocks.isNotEmpty) {
              flushSpans();
              outBlocks.addAll(inlineBlocks);
              emittedContentInParagraph = true;
            }
            return;
          }
          // Fallback for raw <w:drawing> without inline/anchor wrapper.
          final extent = _descendants(el, 'extent').firstOrNull;
          double? widthPt;
          double? heightPt;
          if (extent != null) {
            final cx = double.tryParse(_attr(extent, 'cx') ?? '');
            final cy = double.tryParse(_attr(extent, 'cy') ?? '');
            if (cx != null && cx > 0) widthPt = cx / 12700.0;
            if (cy != null && cy > 0) heightPt = cy / 12700.0;
          }
          final docPr = _descendants(el, 'docPr').firstOrNull;
          final altText =
              docPr != null ? (_attr(docPr, 'descr') ?? _attr(docPr, 'title')) : null;
          for (final blip in _descendants(el, 'blip')) {
            final embedId = _attr(blip, 'embed') ?? _attr(blip, 'link');
            if (embedId != null && mediaMap.containsKey(embedId)) {
              final imgFile = _findArchiveFile(archive, mediaMap[embedId]!);
              if (imgFile != null) {
                flushSpans();
                outBlocks.add(
                  WordImageBlock(
                    bytes: Uint8List.fromList(imgFile.content as List<int>),
                    altText: altText?.trim().isEmpty == true ? null : altText,
                    widthPt: widthPt,
                    heightPt: heightPt,
                    alignment: resolvedPPr.alignment,
                  ),
                );
                emittedContentInParagraph = true;
              }
            }
          }
          return;
        }
        if (local == 'pict') {
          final pictRes = _parsePict(
            el,
            alignment: resolvedPPr.alignment,
          );
          if (pictRes.floating) {
            emittedFloatingInParagraph = true;
          }
          if (pictRes.inlineBlocks.isNotEmpty) {
            flushSpans();
            outBlocks.addAll(pictRes.inlineBlocks);
            emittedContentInParagraph = true;
          }
          return;
        }
        for (final c in el.children) {
          if (c is XmlElement) walk(c);
        }
      }

      walk(container);
    }

    void parseRun(XmlElement rEl, String? linkUrl) {
      final directRPr = _RawRPr.parse(_child(rEl, 'rPr'), theme);
      var resolvedRPr = paraBaseRPr;
      if (directRPr.rStyleId != null) {
        resolvedRPr = styleSheet
            .resolveCharacterStyleRPr(directRPr.rStyleId)
            .mergeOver(resolvedRPr);
      }
      resolvedRPr = directRPr.mergeOver(resolvedRPr);

      final bold = resolvedRPr.bold ?? false;
      final italic = resolvedRPr.italic ?? false;
      final underline = resolvedRPr.underline ?? false;
      final strikethrough = resolvedRPr.strikethrough ?? false;
      final allCaps = resolvedRPr.allCaps ?? false;
      final smallCaps = resolvedRPr.smallCaps ?? false;
      final isSup = resolvedRPr.vertAlign == 'superscript';
      final isSub = resolvedRPr.vertAlign == 'subscript';

      for (final rChild in rEl.children) {
        if (rChild is! XmlElement) continue;
        final childName = rChild.name.local;
        if (childName == 't') {
          final text = rChild.innerText;
          if (text.isNotEmpty) {
            currentSpans.add(
              WordSpan(
                text: text,
                bold: bold,
                italic: italic,
                underline: underline,
                strikethrough: strikethrough,
                fontSize: resolvedRPr.fontSizePt,
                colorHex: resolvedRPr.colorHex,
                highlightHex: resolvedRPr.highlightHex,
                linkUrl: linkUrl,
                fontFamily: resolvedRPr.fontFamily,
                shadingColorHex: resolvedRPr.shadingColorHex,
                isSuperscript: isSup,
                isSubscript: isSub,
                allCaps: allCaps,
                smallCaps: smallCaps,
                letterSpacingPt: resolvedRPr.letterSpacingPt,
              ),
            );
          }
        } else if (childName == 'br') {
          final brType = _attr(rChild, 'type')?.toLowerCase();
          if (brType == 'page') {
            flushSpans();
            outBlocks.add(const WordPageBreakBlock());
            emittedContentInParagraph = true;
            currentPageIndex++;
            estimatedYOnPagePt = pageSettings.marginTopPt;
          } else {
            currentSpans.add(WordSpan(text: '\n', fontSize: resolvedRPr.fontSizePt));
          }
        } else if (childName == 'cr') {
          currentSpans.add(WordSpan(text: '\n', fontSize: resolvedRPr.fontSizePt));
        } else if (childName == 'tab') {
          currentSpans.add(WordSpan(text: '\t', fontSize: resolvedRPr.fontSizePt));
        } else if (childName == 'noBreakHyphen') {
          currentSpans.add(
            WordSpan(
              text: '\u2011',
              bold: bold,
              italic: italic,
              underline: underline,
              strikethrough: strikethrough,
              fontSize: resolvedRPr.fontSizePt,
              colorHex: resolvedRPr.colorHex,
              highlightHex: resolvedRPr.highlightHex,
              linkUrl: linkUrl,
              fontFamily: resolvedRPr.fontFamily,
            ),
          );
        } else if (childName == 'drawing' || childName == 'pict') {
          extractDrawingsFromElement(rChild);
        }
      }
    }

    void parseRunContainer(XmlElement container, String? linkUrl) {
      for (final node in container.children) {
        if (node is! XmlElement) continue;
        final name = node.name.local;
        switch (name) {
          case 'hyperlink':
            final rId = _attr(node, 'id');
            final target = rId != null ? linkMap[rId] : null;
            parseRunContainer(node, target ?? linkUrl);
            break;
          case 'r':
            parseRun(node, linkUrl);
            break;
          case 'sdt':
            final sdtContent = _child(node, 'sdtContent');
            if (sdtContent != null) parseRunContainer(sdtContent, linkUrl);
            break;
          case 'AlternateContent':
            final chosen = _child(node, 'Choice') ?? _child(node, 'Fallback');
            if (chosen != null) parseRunContainer(chosen, linkUrl);
            break;
          case 'drawing':
          case 'pict':
            extractDrawingsFromElement(node);
            break;
          case 'pPr':
          case 'del':
          case 'moveFrom':
          case 'bookmarkStart':
          case 'bookmarkEnd':
            break;
          default:
            parseRunContainer(node, linkUrl);
            break;
        }
      }
    }

    parseRunContainer(pEl, null);
    flushSpans();

    final hasParagraphBorders = resolvedPPr.borders?.hasAny ?? false;
    if (!emittedContentInParagraph &&
        (!emittedFloatingInParagraph || hasParagraphBorders)) {
      // Keep genuine empty spacer paragraphs (including horizontal border dividers),
      // while avoiding synthetic blanks for pure floating-anchor carrier paragraphs.
      outBlocks.add(
        buildParagraphBlock(
          const [],
          isEmptySpacer: true,
          includePageBreakBefore: true,
        ),
      );
    }

    final estSize = paraBaseRPr.fontSizePt ?? 11.0;
    estimatedYOnPagePt += (resolvedPPr.spaceBeforePt ?? 0.0) +
        (resolvedPPr.spaceAfterPt ?? 6.0) +
        estSize * (resolvedPPr.lineSpacingMultiplier ?? 1.15);

    return outBlocks;
  }

  List<WordBlock> _parseInlineDrawing(
    XmlElement inlineEl, {
    TextAlign? alignment,
  }) {
    final extent = _child(inlineEl, 'extent');
    double? widthPt;
    double? heightPt;
    if (extent != null) {
      final cx = double.tryParse(_attr(extent, 'cx') ?? '');
      final cy = double.tryParse(_attr(extent, 'cy') ?? '');
      if (cx != null && cx > 0) widthPt = cx / 12700.0;
      if (cy != null && cy > 0) heightPt = cy / 12700.0;
    }

    final docPr = _child(inlineEl, 'docPr');
    final altText = docPr != null
        ? (_attr(docPr, 'descr') ?? _attr(docPr, 'title'))?.trim()
        : null;

    final graphic = _child(inlineEl, 'graphic');
    final graphicData = graphic != null ? _child(graphic, 'graphicData') : null;
    if (graphicData == null) return const [];

    final blocks = <WordBlock>[];
    for (final child in graphicData.children.whereType<XmlElement>()) {
      final local = child.name.local;
      if (local == 'pic') {
        final blip = _descendants(child, 'blip').firstOrNull;
        final bytes = _resolveBlipBytes(blip);
        if (bytes != null) {
          blocks.add(
            WordImageBlock(
              bytes: bytes,
              altText: altText?.isEmpty == true ? null : altText,
              widthPt: widthPt,
              heightPt: heightPt,
              alignment: alignment,
            ),
          );
        }
      } else if (local == 'wsp') {
        final shape = _parseWspStyle(child);
        final textBlocks = _parseTxbxInShape(child);
        if (textBlocks.isNotEmpty ||
            shape.fillColorHex != null ||
            shape.strokeColorHex != null) {
          blocks.add(
            WordTextBoxBlock(
              blocks: textBlocks,
              widthPt: widthPt,
              heightPt: heightPt,
              fillColorHex: shape.fillColorHex,
              strokeColorHex: shape.strokeColorHex,
              strokeWidthPt: shape.strokeWidthPt,
              shapeType: shape.shapeType,
              alignment: alignment,
            ),
          );
        }
      }
    }

    if (blocks.isEmpty) {
      for (final blip in _descendants(graphicData, 'blip')) {
        final bytes = _resolveBlipBytes(blip);
        if (bytes != null) {
          blocks.add(
            WordImageBlock(
              bytes: bytes,
              altText: altText?.isEmpty == true ? null : altText,
              widthPt: widthPt,
              heightPt: heightPt,
              alignment: alignment,
            ),
          );
        }
      }
    }

    return blocks;
  }

  bool _parseAnchorDrawing(XmlElement anchorEl) {
    final extent = _child(anchorEl, 'extent');
    var widthPt = 100.0;
    var heightPt = 100.0;
    if (extent != null) {
      final cx = double.tryParse(_attr(extent, 'cx') ?? '');
      final cy = double.tryParse(_attr(extent, 'cy') ?? '');
      if (cx != null && cx >= 0) widthPt = cx / 12700.0;
      if (cy != null && cy >= 0) heightPt = cy / 12700.0;
    }

    final behindDoc = _attr(anchorEl, 'behindDoc') == '1' ||
        _attr(anchorEl, 'behindDoc')?.toLowerCase() == 'true';
    final zOrder =
        int.tryParse(_attr(anchorEl, 'relativeHeight') ?? '') ?? (_nextFallbackZ++);

    final xPt = _resolveHorizontalOffsetPt(_child(anchorEl, 'positionH'), widthPt);
    final yPt = _resolveVerticalOffsetPt(_child(anchorEl, 'positionV'), heightPt);

    final docPr = _child(anchorEl, 'docPr');
    final altText = docPr != null
        ? (_attr(docPr, 'descr') ?? _attr(docPr, 'title'))?.trim()
        : null;

    final graphic = _child(anchorEl, 'graphic');
    final graphicData = graphic != null ? _child(graphic, 'graphicData') : null;
    if (graphicData == null) return false;

    var added = false;
    for (final child in graphicData.children.whereType<XmlElement>()) {
      final local = child.name.local;
      if (local == 'pic') {
        final elem = _buildFloatingPic(
          child,
          xPt: xPt,
          yPt: yPt,
          widthPt: widthPt,
          heightPt: heightPt,
          behindDoc: behindDoc,
          zOrder: zOrder,
          altText: altText,
        );
        if (elem != null) {
          floatingElements.add(elem);
          added = true;
        }
      } else if (local == 'wsp') {
        final elem = _buildFloatingWsp(
          child,
          xPt: xPt,
          yPt: yPt,
          widthPt: widthPt,
          heightPt: heightPt,
          behindDoc: behindDoc,
          zOrder: zOrder,
          altText: altText,
        );
        if (elem != null) {
          floatingElements.add(elem);
          added = true;
        }
      } else if (local == 'wgp') {
        final groupCount = _unpackFloatingGroup(
          child,
          xPt: xPt,
          yPt: yPt,
          widthPt: widthPt,
          heightPt: heightPt,
          behindDoc: behindDoc,
          baseZOrder: zOrder,
          parentRotDeg: 0.0,
          parentFlipH: false,
          parentFlipV: false,
        );
        if (groupCount > 0) added = true;
      }
    }

    if (!added) {
      final blip = _descendants(graphicData, 'blip').firstOrNull;
      final bytes = _resolveBlipBytes(blip);
      if (bytes != null) {
        floatingElements.add(
          WordFloatingElement(
            xPt: xPt,
            yPt: yPt,
            widthPt: widthPt,
            heightPt: heightPt,
            behindDoc: behindDoc,
            zOrder: zOrder,
            pageIndex: _activeFloatingPageIndex,
            imageBytes: bytes,
            altText: altText?.isEmpty == true ? null : altText,
          ),
        );
        added = true;
      }
    }

    return added;
  }

  double _resolveHorizontalOffsetPt(XmlElement? posH, double widthPt) {
    if (posH == null) return pageSettings.marginLeftPt;
    final rel = (_attr(posH, 'relativeFrom') ?? 'column').toLowerCase();
    final contentW = math.max(
      1.0,
      pageSettings.widthPt - pageSettings.marginLeftPt - pageSettings.marginRightPt,
    );
    final double baseX;
    final double refW;
    switch (rel) {
      case 'page':
        baseX = 0.0;
        refW = pageSettings.widthPt;
        break;
      case 'rightmargin':
        baseX = pageSettings.widthPt - pageSettings.marginRightPt;
        refW = pageSettings.marginRightPt;
        break;
      case 'leftmargin':
        baseX = 0.0;
        refW = pageSettings.marginLeftPt;
        break;
      default:
        baseX = pageSettings.marginLeftPt;
        refW = contentW;
        break;
    }

    final offsetEl = _child(posH, 'posOffset');
    if (offsetEl != null) {
      final emu = double.tryParse(offsetEl.innerText.trim());
      if (emu != null) return baseX + emu / 12700.0;
    }

    final alignEl = _child(posH, 'align');
    if (alignEl != null) {
      return switch (alignEl.innerText.trim().toLowerCase()) {
        'center' => baseX + (refW - widthPt) / 2.0,
        'right' || 'outside' => baseX + refW - widthPt,
        _ => baseX,
      };
    }

    return baseX;
  }

  double _resolveVerticalOffsetPt(XmlElement? posV, double heightPt) {
    if (posV == null) return estimatedYOnPagePt;
    final rel = (_attr(posV, 'relativeFrom') ?? 'paragraph').toLowerCase();
    final contentH = math.max(
      1.0,
      pageSettings.heightPt - pageSettings.marginTopPt - pageSettings.marginBottomPt,
    );
    final double baseY;
    final double refH;
    switch (rel) {
      case 'page':
        baseY = 0.0;
        refH = pageSettings.heightPt;
        break;
      case 'margin':
        baseY = pageSettings.marginTopPt;
        refH = contentH;
        break;
      case 'topmargin':
        baseY = 0.0;
        refH = pageSettings.marginTopPt;
        break;
      case 'bottommargin':
        baseY = pageSettings.heightPt - pageSettings.marginBottomPt;
        refH = pageSettings.marginBottomPt;
        break;
      default:
        // paragraph / line
        baseY = estimatedYOnPagePt;
        refH = contentH;
        break;
    }

    final offsetEl = _child(posV, 'posOffset');
    if (offsetEl != null) {
      final emu = double.tryParse(offsetEl.innerText.trim());
      if (emu != null) return baseY + emu / 12700.0;
    }

    final alignEl = _child(posV, 'align');
    if (alignEl != null) {
      return switch (alignEl.innerText.trim().toLowerCase()) {
        'center' => baseY + (refH - heightPt) / 2.0,
        'bottom' || 'outside' => baseY + refH - heightPt,
        _ => baseY,
      };
    }

    return baseY;
  }

  Uint8List? _resolveBlipBytes(XmlElement? blipEl) {
    if (blipEl == null) return null;
    final embedId = _attr(blipEl, 'embed') ?? _attr(blipEl, 'link');
    if (embedId == null || !mediaMap.containsKey(embedId)) return null;
    final imgFile = _findArchiveFile(archive, mediaMap[embedId]!);
    if (imgFile == null) return null;
    return Uint8List.fromList(imgFile.content as List<int>);
  }

  ({double rotDeg, bool flipH, bool flipV}) _parseXfrmTransform(XmlElement? spPr) {
    if (spPr == null) return (rotDeg: 0.0, flipH: false, flipV: false);
    final xfrm = _child(spPr, 'xfrm');
    if (xfrm == null) return (rotDeg: 0.0, flipH: false, flipV: false);
    final rotRaw = double.tryParse(_attr(xfrm, 'rot') ?? '');
    final rotDeg = rotRaw != null ? rotRaw / 60000.0 : 0.0;
    final flipH = _attr(xfrm, 'flipH') == '1' ||
        _attr(xfrm, 'flipH')?.toLowerCase() == 'true';
    final flipV = _attr(xfrm, 'flipV') == '1' ||
        _attr(xfrm, 'flipV')?.toLowerCase() == 'true';
    return (rotDeg: rotDeg, flipH: flipH, flipV: flipV);
  }

  ({
    String? shapeType,
    String? fillColorHex,
    String? strokeColorHex,
    double? strokeWidthPt,
    double rotDeg,
    bool flipH,
    bool flipV,
  }) _parseWspStyle(XmlElement wspOrPicEl) {
    final spPr = _child(wspOrPicEl, 'spPr');
    final xfrmInfo = _parseXfrmTransform(spPr);

    String? shapeType;
    String? fillColorHex;
    String? strokeColorHex;
    double? strokeWidthPt;

    if (spPr != null) {
      final prstGeom = _child(spPr, 'prstGeom');
      if (prstGeom != null) {
        shapeType = _attr(prstGeom, 'prst');
      }

      if (_child(spPr, 'noFill') == null) {
        final solidFill = _child(spPr, 'solidFill');
        if (solidFill != null) {
          fillColorHex = theme.resolveDrawingColorContainer(solidFill);
        }
      }

      final ln = _child(spPr, 'ln');
      if (ln != null) {
        if (_child(ln, 'noFill') == null) {
          final wEmu = double.tryParse(_attr(ln, 'w') ?? '');
          strokeWidthPt = wEmu != null ? math.max(0.5, wEmu / 12700.0) : 0.75;
          final lnFill = _child(ln, 'solidFill');
          if (lnFill != null) {
            strokeColorHex = theme.resolveDrawingColorContainer(lnFill);
          }
        } else {
          strokeWidthPt = 0.0;
        }
      }
    }

    // Fallback to <wps:style> fillRef / lnRef if spPr didn't explicitly declare fill/stroke.
    final styleEl = _child(wspOrPicEl, 'style');
    if (styleEl != null) {
      if (fillColorHex == null &&
          spPr != null &&
          _child(spPr, 'noFill') == null &&
          _child(spPr, 'solidFill') == null) {
        final fillRef = _child(styleEl, 'fillRef');
        if (fillRef != null && _attr(fillRef, 'idx') != '0') {
          fillColorHex = theme.resolveDrawingColorContainer(fillRef);
        }
      }
      if (strokeColorHex == null) {
        final ln = spPr != null ? _child(spPr, 'ln') : null;
        if (ln == null || _child(ln, 'noFill') == null) {
          final lnRef = _child(styleEl, 'lnRef');
          if (lnRef != null && _attr(lnRef, 'idx') != '0') {
            strokeColorHex = theme.resolveDrawingColorContainer(lnRef);
            strokeWidthPt ??= 0.75;
          }
        }
      }
    }

    return (
      shapeType: shapeType,
      fillColorHex: fillColorHex,
      strokeColorHex: strokeColorHex,
      strokeWidthPt: strokeWidthPt,
      rotDeg: xfrmInfo.rotDeg,
      flipH: xfrmInfo.flipH,
      flipV: xfrmInfo.flipV,
    );
  }

  List<WordBlock> _parseTxbxInShape(XmlElement wspEl) {
    final txbx = _child(wspEl, 'txbx');
    final txbxContent = txbx != null
        ? _child(txbx, 'txbxContent')
        : _descendants(wspEl, 'txbxContent').firstOrNull;
    if (txbxContent == null) return const [];
    final savedY = estimatedYOnPagePt;
    final parsed = parseContainerChildren(txbxContent);
    estimatedYOnPagePt = savedY;
    return parsed;
  }

  WordFloatingElement? _buildFloatingPic(
    XmlElement picEl, {
    required double xPt,
    required double yPt,
    required double widthPt,
    required double heightPt,
    required bool behindDoc,
    required int zOrder,
    String? altText,
  }) {
    final blip = _descendants(picEl, 'blip').firstOrNull;
    final bytes = _resolveBlipBytes(blip);
    if (bytes == null) return null;
    final style = _parseWspStyle(picEl);
    return WordFloatingElement(
      xPt: xPt,
      yPt: yPt,
      widthPt: widthPt,
      heightPt: heightPt,
      behindDoc: behindDoc,
      zOrder: zOrder,
      rotationDeg: style.rotDeg,
      flipH: style.flipH,
      flipV: style.flipV,
      pageIndex: _activeFloatingPageIndex,
      imageBytes: bytes,
      strokeColorHex: style.strokeColorHex,
      strokeWidthPt: style.strokeWidthPt,
      altText: altText?.isEmpty == true ? null : altText,
    );
  }

  WordFloatingElement? _buildFloatingWsp(
    XmlElement wspEl, {
    required double xPt,
    required double yPt,
    required double widthPt,
    required double heightPt,
    required bool behindDoc,
    required int zOrder,
    String? altText,
    double extraRotDeg = 0.0,
    bool extraFlipH = false,
    bool extraFlipV = false,
  }) {
    final style = _parseWspStyle(wspEl);
    final textBlocks = _parseTxbxInShape(wspEl);
    final blip = _descendants(wspEl, 'blip').firstOrNull;
    final bytes = _resolveBlipBytes(blip);

    if (textBlocks.isEmpty &&
        bytes == null &&
        style.fillColorHex == null &&
        style.strokeColorHex == null) {
      return null;
    }

    return WordFloatingElement(
      xPt: xPt,
      yPt: yPt,
      widthPt: widthPt,
      heightPt: heightPt,
      behindDoc: behindDoc,
      zOrder: zOrder,
      rotationDeg: style.rotDeg + extraRotDeg,
      flipH: style.flipH != extraFlipH,
      flipV: style.flipV != extraFlipV,
      pageIndex: _activeFloatingPageIndex,
      imageBytes: bytes,
      shapeType: style.shapeType ?? 'rect',
      fillColorHex: style.fillColorHex,
      strokeColorHex: style.strokeColorHex,
      strokeWidthPt: style.strokeWidthPt,
      textBlocks: textBlocks,
      altText: altText?.isEmpty == true ? null : altText,
    );
  }

  int _unpackFloatingGroup(
    XmlElement wgpEl, {
    required double xPt,
    required double yPt,
    required double widthPt,
    required double heightPt,
    required bool behindDoc,
    required int baseZOrder,
    required double parentRotDeg,
    required bool parentFlipH,
    required bool parentFlipV,
  }) {
    final grpSpPr = _child(wgpEl, 'grpSpPr');
    final grpXfrm = grpSpPr != null ? _child(grpSpPr, 'xfrm') : null;
    final grpInfo = _parseXfrmTransform(grpSpPr);

    var chOffX = 0.0;
    var chOffY = 0.0;
    var chExtW = widthPt;
    var chExtH = heightPt;
    if (grpXfrm != null) {
      final chOff = _child(grpXfrm, 'chOff');
      final chExt = _child(grpXfrm, 'chExt');
      if (chOff != null) {
        chOffX = (double.tryParse(_attr(chOff, 'x') ?? '') ?? 0.0) / 12700.0;
        chOffY = (double.tryParse(_attr(chOff, 'y') ?? '') ?? 0.0) / 12700.0;
      }
      if (chExt != null) {
        final cx = double.tryParse(_attr(chExt, 'cx') ?? '');
        final cy = double.tryParse(_attr(chExt, 'cy') ?? '');
        if (cx != null && cx > 0) chExtW = cx / 12700.0;
        if (cy != null && cy > 0) chExtH = cy / 12700.0;
      }
    }

    final sx = chExtW > 0 ? widthPt / chExtW : 1.0;
    final sy = chExtH > 0 ? heightPt / chExtH : 1.0;
    final combRot = parentRotDeg + grpInfo.rotDeg;
    final combFlipH = parentFlipH != grpInfo.flipH;
    final combFlipV = parentFlipV != grpInfo.flipV;

    var count = 0;
    for (final child in wgpEl.children.whereType<XmlElement>()) {
      final local = child.name.local;
      if (local != 'wsp' && local != 'pic' && local != 'wgp') continue;

      final spPr = local == 'wgp' ? _child(child, 'grpSpPr') : _child(child, 'spPr');
      final xfrm = spPr != null ? _child(spPr, 'xfrm') : null;
      final off = xfrm != null ? _child(xfrm, 'off') : null;
      final ext = xfrm != null ? _child(xfrm, 'ext') : null;

      final offXPt = (double.tryParse(off != null ? (_attr(off, 'x') ?? '') : '') ?? 0.0) / 12700.0;
      final offYPt = (double.tryParse(off != null ? (_attr(off, 'y') ?? '') : '') ?? 0.0) / 12700.0;
      final extWPt = (double.tryParse(ext != null ? (_attr(ext, 'cx') ?? '') : '') ?? 0.0) / 12700.0;
      final extHPt = (double.tryParse(ext != null ? (_attr(ext, 'cy') ?? '') : '') ?? 0.0) / 12700.0;

      final childX = xPt + (offXPt - chOffX) * sx;
      final childY = yPt + (offYPt - chOffY) * sy;
      final childW = extWPt * sx;
      final childH = extHPt * sy;

      if (local == 'pic') {
        final elem = _buildFloatingPic(
          child,
          xPt: childX,
          yPt: childY,
          widthPt: childW,
          heightPt: childH,
          behindDoc: behindDoc,
          zOrder: baseZOrder + count,
        );
        if (elem != null) {
          floatingElements.add(elem);
          count++;
        }
      } else if (local == 'wsp') {
        final elem = _buildFloatingWsp(
          child,
          xPt: childX,
          yPt: childY,
          widthPt: childW,
          heightPt: childH,
          behindDoc: behindDoc,
          zOrder: baseZOrder + count,
          extraRotDeg: combRot,
          extraFlipH: combFlipH,
          extraFlipV: combFlipV,
        );
        if (elem != null) {
          floatingElements.add(elem);
          count++;
        }
      } else if (local == 'wgp') {
        count += _unpackFloatingGroup(
          child,
          xPt: childX,
          yPt: childY,
          widthPt: childW,
          heightPt: childH,
          behindDoc: behindDoc,
          baseZOrder: baseZOrder + count,
          parentRotDeg: combRot,
          parentFlipH: combFlipH,
          parentFlipV: combFlipV,
        );
      }
    }
    return count;
  }

  ({bool floating, List<WordBlock> inlineBlocks}) _parsePict(
    XmlElement pictEl, {
    TextAlign? alignment,
  }) {
    final inlineBlocks = <WordBlock>[];
    var emittedFloating = false;

    for (final child in pictEl.children.whereType<XmlElement>()) {
      final local = child.name.local;
      if (local != 'shape' &&
          local != 'rect' &&
          local != 'roundrect' &&
          local != 'oval' &&
          local != 'line') {
        continue;
      }

      final styleStr = _attr(child, 'style') ?? '';
      final css = _parseCssStyleMap(styleStr);
      final isAbsolute = css['position']?.toLowerCase() == 'absolute';
      final widthPt = _parseCssLengthPt(css['width']);
      final heightPt = _parseCssLengthPt(css['height']);

      final imagedata = _child(child, 'imagedata') ??
          _descendants(child, 'imagedata').firstOrNull;
      Uint8List? imageBytes;
      String? altText;
      if (imagedata != null) {
        altText = _attr(imagedata, 'title');
        final rId = _attr(imagedata, 'id');
        if (rId != null && mediaMap.containsKey(rId)) {
          final imgFile = _findArchiveFile(archive, mediaMap[rId]!);
          if (imgFile != null) {
            imageBytes = Uint8List.fromList(imgFile.content as List<int>);
          }
        }
      }

      final textboxEl = _child(child, 'textbox');
      final txbxContent = textboxEl != null
          ? (_child(textboxEl, 'txbxContent') ??
              _descendants(textboxEl, 'txbxContent').firstOrNull)
          : null;
      var textBlocks = const <WordBlock>[];
      if (txbxContent != null) {
        final savedY = estimatedYOnPagePt;
        textBlocks = parseContainerChildren(txbxContent);
        estimatedYOnPagePt = savedY;
      }

      final filled = _attr(child, 'filled')?.toLowerCase();
      final stroked = _attr(child, 'stroked')?.toLowerCase();
      final fillHex = (filled == 'f' || filled == 'false')
          ? null
          : _parseVmlColor(_attr(child, 'fillcolor'));
      final strokeHex = (stroked == 'f' || stroked == 'false')
          ? null
          : (_parseVmlColor(_attr(child, 'strokecolor')) ??
              (textBlocks.isNotEmpty ? '000000' : null));
      final strokeW =
          _parseCssLengthPt(_attr(child, 'strokeweight') ?? '') ?? 0.75;

      final shapeType = switch (local) {
        'oval' => 'ellipse',
        'roundrect' => 'roundRect',
        'line' => 'line',
        _ => 'rect',
      };

      if (isAbsolute && (widthPt != null || heightPt != null)) {
        final w = widthPt ?? 120.0;
        final h = heightPt ?? 60.0;

        final hRel =
            (css['mso-position-horizontal-relative'] ?? 'text').toLowerCase();
        final vRel =
            (css['mso-position-vertical-relative'] ?? 'text').toLowerCase();
        final baseX = hRel == 'page' ? 0.0 : pageSettings.marginLeftPt;
        final baseY = vRel == 'page'
            ? 0.0
            : (vRel == 'margin' ? pageSettings.marginTopPt : estimatedYOnPagePt);

        var xPt = baseX +
            (_parseCssLengthPt(css['margin-left'] ?? css['left']) ?? 0.0);
        var yPt = baseY +
            (_parseCssLengthPt(css['margin-top'] ?? css['top']) ?? 0.0);

        final hAlign = css['mso-position-horizontal']?.toLowerCase();
        if (hAlign == 'center') {
          final refW = hRel == 'page'
              ? pageSettings.widthPt
              : (pageSettings.widthPt -
                  pageSettings.marginLeftPt -
                  pageSettings.marginRightPt);
          xPt = baseX + (refW - w) / 2.0;
        } else if (hAlign == 'right') {
          final refW = hRel == 'page'
              ? pageSettings.widthPt
              : (pageSettings.widthPt -
                  pageSettings.marginLeftPt -
                  pageSettings.marginRightPt);
          xPt = baseX + refW - w;
        }

        final vAlign = css['mso-position-vertical']?.toLowerCase();
        if (vAlign == 'center') {
          final refH = vRel == 'page'
              ? pageSettings.heightPt
              : (pageSettings.heightPt -
                  pageSettings.marginTopPt -
                  pageSettings.marginBottomPt);
          yPt = baseY + (refH - h) / 2.0;
        } else if (vAlign == 'bottom') {
          final refH = vRel == 'page'
              ? pageSettings.heightPt
              : (pageSettings.heightPt -
                  pageSettings.marginTopPt -
                  pageSettings.marginBottomPt);
          yPt = baseY + refH - h;
        }

        final zRaw = int.tryParse(css['z-index'] ?? '');
        final behind = zRaw != null ? zRaw < 0 : false;
        final rot = double.tryParse(css['rotation'] ?? '') ?? 0.0;
        final flipStr = (css['flip'] ?? '').toLowerCase();

        floatingElements.add(
          WordFloatingElement(
            xPt: xPt,
            yPt: yPt,
            widthPt: w,
            heightPt: h,
            behindDoc: behind,
            zOrder: zRaw ?? (_nextFallbackZ++),
            rotationDeg: rot,
            flipH: flipStr.contains('x'),
            flipV: flipStr.contains('y'),
            pageIndex: _activeFloatingPageIndex,
            imageBytes: imageBytes,
            shapeType: shapeType,
            fillColorHex: fillHex,
            strokeColorHex: strokeHex,
            strokeWidthPt: strokeW,
            textBlocks: textBlocks,
            altText: altText,
          ),
        );
        emittedFloating = true;
      } else if (textBlocks.isNotEmpty) {
        inlineBlocks.add(
          WordTextBoxBlock(
            blocks: textBlocks,
            widthPt: widthPt,
            heightPt: heightPt,
            fillColorHex: fillHex,
            strokeColorHex: strokeHex,
            strokeWidthPt: strokeW,
            shapeType: shapeType,
            alignment: alignment,
          ),
        );
      } else if (imageBytes != null) {
        inlineBlocks.add(
          WordImageBlock(
            bytes: imageBytes,
            altText: altText,
            widthPt: widthPt,
            heightPt: heightPt,
            alignment: alignment,
          ),
        );
      }
    }

    if (!emittedFloating && inlineBlocks.isEmpty) {
      // Final fallback for bare <v:imagedata> outside standard shape wrappers.
      for (final imgData in _descendants(pictEl, 'imagedata')) {
        final rId = _attr(imgData, 'id');
        if (rId != null && mediaMap.containsKey(rId)) {
          final imgFile = _findArchiveFile(archive, mediaMap[rId]!);
          if (imgFile != null) {
            inlineBlocks.add(
              WordImageBlock(
                bytes: Uint8List.fromList(imgFile.content as List<int>),
                altText: _attr(imgData, 'title'),
                alignment: alignment,
              ),
            );
          }
        }
      }
    }

    return (floating: emittedFloating, inlineBlocks: inlineBlocks);
  }

  static Map<String, String> _parseCssStyleMap(String style) {
    final map = <String, String>{};
    for (final part in style.split(';')) {
      final colon = part.indexOf(':');
      if (colon <= 0) continue;
      final k = part.substring(0, colon).trim().toLowerCase();
      final v = part.substring(colon + 1).trim();
      if (k.isNotEmpty && v.isNotEmpty) {
        map[k] = v;
      }
    }
    return map;
  }

  static double? _parseCssLengthPt(String? raw) {
    if (raw == null) return null;
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return null;
    if (s.endsWith('pt')) {
      return double.tryParse(s.substring(0, s.length - 2).trim());
    }
    if (s.endsWith('in')) {
      final v = double.tryParse(s.substring(0, s.length - 2).trim());
      return v != null ? v * 72.0 : null;
    }
    if (s.endsWith('cm')) {
      final v = double.tryParse(s.substring(0, s.length - 2).trim());
      return v != null ? v * 28.3464567 : null;
    }
    if (s.endsWith('mm')) {
      final v = double.tryParse(s.substring(0, s.length - 2).trim());
      return v != null ? v * 2.83464567 : null;
    }
    if (s.endsWith('px')) {
      final v = double.tryParse(s.substring(0, s.length - 2).trim());
      return v != null ? v * 0.75 : null;
    }
    if (s.endsWith('emu')) {
      final v = double.tryParse(s.substring(0, s.length - 3).trim());
      return v != null ? v / 12700.0 : null;
    }
    return double.tryParse(s);
  }

  static String? _parseVmlColor(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final clean = raw.split(' ').first.trim();
    final hex = _normalizeHexColor(clean);
    if (hex != null) return hex;
    return switch (clean.toLowerCase()) {
      'white' => 'FFFFFF',
      'black' => '000000',
      'red' => 'FF0000',
      'blue' => '0000FF',
      'navy' => '000080',
      'green' => '008000',
      'yellow' => 'FFFF00',
      'orange' => 'FFA500',
      'gray' || 'grey' => '808080',
      'silver' => 'C0C0C0',
      'maroon' => '800000',
      'purple' => '800080',
      'teal' => '008080',
      _ => null,
    };
  }

  WordTableBlock? _parseTable(XmlElement tblEl) {
    final tblPr = _child(tblEl, 'tblPr');
    String? tblStyleId;
    TextAlign? tblAlignment;
    double? tblWidthPt;
    double? tblWidthPercent;
    WordBorders? directTblBorders;
    ({double? top, double? bottom, double? left, double? right}) directCellMar =
        (top: null, bottom: null, left: null, right: null);
    bool lookFirstRow = true;
    bool lookHBand = true;

    if (tblPr != null) {
      final styleEl = _child(tblPr, 'tblStyle');
      tblStyleId = styleEl != null ? _attr(styleEl, 'val') : null;

      final jcEl = _child(tblPr, 'jc');
      tblAlignment = jcEl != null ? _parseJcValue(_attr(jcEl, 'val')) : null;

      final tblWEl = _child(tblPr, 'tblW');
      if (tblWEl != null) {
        final wVal = double.tryParse(_attr(tblWEl, 'w') ?? '');
        final wType = (_attr(tblWEl, 'type') ?? 'dxa').toLowerCase();
        if (wVal != null && wVal > 0) {
          if (wType == 'dxa') {
            tblWidthPt = wVal / 20.0;
          } else if (wType == 'pct') {
            tblWidthPercent = wVal / 50.0;
          }
        }
      }

      directTblBorders = _parseBorders(_child(tblPr, 'tblBorders'), theme);
      directCellMar = _parseCellMargins(_child(tblPr, 'tblCellMar'));

      final tblLookEl = _child(tblPr, 'tblLook');
      if (tblLookEl != null) {
        final firstRowAttr = _attr(tblLookEl, 'firstRow');
        if (firstRowAttr != null) {
          lookFirstRow = firstRowAttr == '1' || firstRowAttr.toLowerCase() == 'true';
        }
        final noHBandAttr = _attr(tblLookEl, 'noHBand');
        if (noHBandAttr != null) {
          lookHBand = noHBandAttr == '0' || noHBandAttr.toLowerCase() == 'false';
        }
      }
    }

    final resolvedStyle = styleSheet.resolveTableStyle(tblStyleId);
    final mergedBorders = directTblBorders != null
        ? directTblBorders.mergeOver(resolvedStyle.tblBorders)
        : resolvedStyle.tblBorders;

    final padTop = directCellMar.top ?? resolvedStyle.cellPadding.top;
    final padBottom = directCellMar.bottom ?? resolvedStyle.cellPadding.bottom;
    final padLeft = directCellMar.left ?? resolvedStyle.cellPadding.left;
    final padRight = directCellMar.right ?? resolvedStyle.cellPadding.right;

    List<double>? columnWidthsPt;
    final tblGrid = _child(tblEl, 'tblGrid');
    if (tblGrid != null) {
      final cols = <double>[];
      for (final colEl in _children(tblGrid, 'gridCol')) {
        final w = double.tryParse(_attr(colEl, 'w') ?? '');
        if (w != null && w > 0) {
          cols.add(w / 20.0);
        }
      }
      if (cols.isNotEmpty) {
        columnWidthsPt = cols;
      }
    }

    final tableRows = <List<String>>[];
    final parsedRows = <List<_MutableCell>>[];
    bool hasExplicitHeaderRow = false;

    final firstRowCond =
        lookFirstRow ? resolvedStyle.conditionals['firstRow'.toLowerCase()] : null;
    final band1HorzCond =
        lookHBand ? resolvedStyle.conditionals['band1Horz'.toLowerCase()] : null;
    if (firstRowCond != null) {
      hasExplicitHeaderRow = true;
    }

    final trElements = _children(tblEl, 'tr').toList();
    for (int rowIndex = 0; rowIndex < trElements.length; rowIndex++) {
      final tr = trElements[rowIndex];
      final trPr = _child(tr, 'trPr');
      final isTblHeader = trPr != null && _child(trPr, 'tblHeader') != null;
      if (isTblHeader) hasExplicitHeaderRow = true;

      _TblStyleConditional? rowCond;
      if (rowIndex == 0 && firstRowCond != null) {
        rowCond = firstRowCond;
      } else if (rowIndex > 0 && rowIndex.isOdd && band1HorzCond != null) {
        rowCond = band1HorzCond;
      }

      final effectiveRowRunOverride = rowCond != null
          ? rowCond.rPr.mergeOver(resolvedStyle.baseRPr)
          : resolvedStyle.baseRPr;

      final rowTextCells = <String>[];
      final rowMutableCells = <_MutableCell>[];
      var currentCol = 0;

      for (final tc in _children(tr, 'tc')) {
        final tcPrEl = _child(tc, 'tcPr');
        var colSpan = 1;
        var isVMergeContinue = false;
        double? cellWidthPt;

        if (tcPrEl != null) {
          final gsEl = _child(tcPrEl, 'gridSpan');
          if (gsEl != null) {
            colSpan = (int.tryParse(_attr(gsEl, 'val') ?? '') ?? 1).clamp(1, 64);
          }

          final vmEl = _child(tcPrEl, 'vMerge');
          if (vmEl != null) {
            final vmVal = _attr(vmEl, 'val')?.toLowerCase();
            if (vmVal == null || vmVal == 'continue') {
              isVMergeContinue = true;
            }
          }

          final tcWEl = _child(tcPrEl, 'tcW');
          if (tcWEl != null) {
            final wVal = double.tryParse(_attr(tcWEl, 'w') ?? '');
            final wType = (_attr(tcWEl, 'type') ?? 'dxa').toLowerCase();
            if (wVal != null && wVal > 0 && wType == 'dxa') {
              cellWidthPt = wVal / 20.0;
            }
          }
        }

        final directTcProps = _RawTcProps.parse(tcPrEl, theme);
        var mergedTcProps = resolvedStyle.baseTcProps;
        if (rowCond != null) {
          mergedTcProps = rowCond.tcProps.mergeOver(mergedTcProps);
        }
        mergedTcProps = directTcProps.mergeOver(mergedTcProps);

        final cellBlocks = parseContainerChildren(
          tc,
          tableRunOverride: effectiveRowRunOverride,
        );

        // Build clean plain text from cell paragraphs without breaking runs.
        final cellText = _extractPlainTextFromBlocks(cellBlocks);
        rowTextCells.add(cellText);

        TextAlign? cellAlign;
        for (final b in cellBlocks) {
          if (b is WordParagraph && b.alignment != null) {
            cellAlign = b.alignment;
            break;
          }
        }
        cellAlign ??= rowCond?.pPr.alignment;

        rowMutableCells.add(
          _MutableCell(
            colStart: currentCol,
            text: cellText,
            isHeader: isTblHeader || (rowIndex == 0 && firstRowCond != null),
            backgroundColorHex: mergedTcProps.backgroundColorHex,
            alignment: cellAlign,
            blocks: cellBlocks,
            colSpan: colSpan,
            isVerticalMergeContinue: isVMergeContinue,
            widthPt: cellWidthPt,
            borders: mergedTcProps.borders,
            verticalAlignment: mergedTcProps.verticalAlignment,
            paddingTopPt: mergedTcProps.paddingTopPt,
            paddingBottomPt: mergedTcProps.paddingBottomPt,
            paddingLeftPt: mergedTcProps.paddingLeftPt,
            paddingRightPt: mergedTcProps.paddingRightPt,
          ),
        );

        currentCol += colSpan;
      }

      if (rowTextCells.isNotEmpty) {
        tableRows.add(rowTextCells);
        parsedRows.add(rowMutableCells);
      }
    }

    if (tableRows.isEmpty) return null;

    // Resolve vertical merge rowSpan counts across rows.
    for (int r = 0; r < parsedRows.length; r++) {
      for (final cell in parsedRows[r]) {
        if (cell.isVerticalMergeContinue) continue;
        var span = 1;
        for (int rNext = r + 1; rNext < parsedRows.length; rNext++) {
          final match = parsedRows[rNext]
              .where((c) => c.colStart == cell.colStart)
              .firstOrNull;
          if (match != null && match.isVerticalMergeContinue) {
            span++;
          } else {
            break;
          }
        }
        cell.rowSpan = span;
      }
    }

    final richRows = parsedRows
        .map((row) => row.map((c) => c.toWordTableCell()).toList())
        .toList();

    return WordTableBlock(
      rows: tableRows,
      richCells: richRows,
      columnWidthsPt: columnWidthsPt,
      borders: mergedBorders,
      alignment: tblAlignment,
      widthPt: tblWidthPt,
      widthPercent: tblWidthPercent,
      hasExplicitHeaderRow: hasExplicitHeaderRow,
      defaultCellPaddingTopPt: padTop,
      defaultCellPaddingBottomPt: padBottom,
      defaultCellPaddingLeftPt: padLeft,
      defaultCellPaddingRightPt: padRight,
    );
  }

  static String _extractPlainTextFromBlocks(List<WordBlock> blocks) {
    final lines = <String>[];
    for (final b in blocks) {
      if (b is WordParagraph) {
        final t = b.fullText;
        if (t.isNotEmpty) lines.add(t);
      } else if (b is WordTableBlock) {
        for (final row in b.rows) {
          lines.add(row.join('\t'));
        }
      }
    }
    return lines.join('\n').trim();
  }
}

class _MutableCell {
  _MutableCell({
    required this.colStart,
    required this.text,
    required this.isHeader,
    required this.backgroundColorHex,
    required this.alignment,
    required this.blocks,
    required this.colSpan,
    required this.isVerticalMergeContinue,
    required this.widthPt,
    required this.borders,
    required this.verticalAlignment,
    required this.paddingTopPt,
    required this.paddingBottomPt,
    required this.paddingLeftPt,
    required this.paddingRightPt,
  });

  final int colStart;
  final String text;
  final bool isHeader;
  final String? backgroundColorHex;
  final TextAlign? alignment;
  final List<WordBlock> blocks;
  final int colSpan;
  int rowSpan = 1;
  final bool isVerticalMergeContinue;
  final double? widthPt;
  final WordBorders? borders;
  final String? verticalAlignment;
  final double? paddingTopPt;
  final double? paddingBottomPt;
  final double? paddingLeftPt;
  final double? paddingRightPt;

  WordTableCell toWordTableCell() {
    return WordTableCell(
      text: text,
      isHeader: isHeader,
      backgroundColorHex: backgroundColorHex,
      alignment: alignment,
      blocks: blocks,
      colSpan: colSpan,
      rowSpan: rowSpan,
      isVerticalMergeContinue: isVerticalMergeContinue,
      widthPt: widthPt,
      borders: borders,
      verticalAlignment: verticalAlignment,
      paddingTopPt: paddingTopPt,
      paddingBottomPt: paddingBottomPt,
      paddingLeftPt: paddingLeftPt,
      paddingRightPt: paddingRightPt,
    );
  }
}
