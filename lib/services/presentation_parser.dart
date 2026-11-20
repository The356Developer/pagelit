import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import 'encoding_utils.dart';

/// Single formatted text run within a slide paragraph.
class SlideTextSpan {
  const SlideTextSpan({
    required this.text,
    this.fontSize = 14.0,
    this.fontColor,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.fontFamily,
  });

  final String text;
  final double fontSize;
  final Color? fontColor;
  final bool bold;
  final bool italic;
  final bool underline;
  final String? fontFamily;
}

/// A paragraph in a slide text frame.
class SlideParagraph {
  const SlideParagraph({
    required this.spans,
    this.alignment = TextAlign.left,
    this.isBullet = false,
    this.bulletChar,
    this.spaceBefore = 0.0,
    this.spaceAfter = 0.0,
  });

  final List<SlideTextSpan> spans;
  final TextAlign alignment;
  final bool isBullet;
  final String? bulletChar;
  final double spaceBefore;
  final double spaceAfter;

  String get plainText => spans.map((s) => s.text).join();
}

/// Base class for all visual slide elements.
abstract class SlideElement {
  const SlideElement({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0.0,
    this.shapeId,
    this.groupShapeId,
    this.isBackgroundDecor = false,
  });

  /// Relative coordinates (0.0 to 1.0) normalized to the slide canvas.
  final double x;
  final double y;
  final double width;
  final double height;

  /// Rotation in degrees clockwise.
  final double rotation;

  /// OOXML `<p:cNvPr id="..."/>` identifier for animation targeting.
  final String? shapeId;

  /// Parent group shape identifier when inside `<p:grpSp>`.
  final String? groupShapeId;

  /// Whether this element is decorative background / edge chrome rather than foreground content.
  final bool isBackgroundDecor;
}

/// A shape or text box on the slide canvas.
class SlideShapeElement extends SlideElement {
  const SlideShapeElement({
    required super.x,
    required super.y,
    required super.width,
    required super.height,
    super.rotation = 0.0,
    super.shapeId,
    super.groupShapeId,
    super.isBackgroundDecor = false,
    this.fillColor,
    this.borderColor,
    this.borderWidth = 0.0,
    this.borderRadius = 0.0,
    this.isCircle = false,
    this.paragraphs = const [],
    this.verticalAlignment = Alignment.topLeft,
    this.isPlaceholder = false,
  });

  final Color? fillColor;
  final Color? borderColor;
  final double borderWidth;
  final double borderRadius;
  final bool isCircle;
  final List<SlideParagraph> paragraphs;
  final Alignment verticalAlignment;
  final bool isPlaceholder;

  String get plainText => paragraphs.map((p) => p.plainText).join('\n').trim();
}

/// An embedded picture positioned on the slide canvas.
class SlidePictureElement extends SlideElement {
  const SlidePictureElement({
    required super.x,
    required super.y,
    required super.width,
    required super.height,
    super.rotation = 0.0,
    super.shapeId,
    super.groupShapeId,
    super.isBackgroundDecor = false,
    required this.imageBytes,
    this.borderRadius = 0.0,
  });

  final Uint8List imageBytes;
  final double borderRadius;
}

/// Cell in a presentation table.
class SlideTableCell {
  const SlideTableCell({
    required this.paragraphs,
    this.fillColor,
    this.borderColor,
  });

  final List<SlideParagraph> paragraphs;
  final Color? fillColor;
  final Color? borderColor;

  String get plainText => paragraphs.map((p) => p.plainText).join('\n').trim();
}

/// A table positioned on the slide canvas.
class SlideTableElement extends SlideElement {
  const SlideTableElement({
    required super.x,
    required super.y,
    required super.width,
    required super.height,
    super.rotation = 0.0,
    super.shapeId,
    super.groupShapeId,
    super.isBackgroundDecor = false,
    required this.rows,
    required this.colWidthRatios,
  });

  final List<List<SlideTableCell>> rows;
  final List<double> colWidthRatios;
}

/// Type of transition when moving between slides.
enum SlideTransitionType {
  fade,
  pushLeft,
  pushRight,
  pushUp,
  pushDown,
  wipe,
  zoom,
  cover,
  uncover,
  split,
  cut,
  none,
}

/// Visual effect for an animated shape on a slide (`<p:timing>`).
enum SlideAnimationEffect {
  appear,
  fade,
  flyIn,
  floatIn,
  wipe,
  zoom,
  split,
  emphasis,
}

/// Entrance direction parsed from OOXML `presetSubtype`.
enum SlideAnimationDirection {
  fromBottom,
  fromLeft,
  fromRight,
  fromTop,
  center,
}

/// Trigger mode parsed from OOXML `nodeType`.
enum SlideAnimationTrigger {
  onClick,
  withPrevious,
  afterPrevious,
}

/// Single step in a slide's OOXML `<p:timing>` animation timeline.
class SlideAnimationStep {
  const SlideAnimationStep({
    required this.shapeId,
    required this.effect,
    this.direction = SlideAnimationDirection.center,
    this.trigger = SlideAnimationTrigger.onClick,
    this.durationMs = 420,
    this.delayMs = 0,
    this.clickGroup = 1,
    this.isEmphasis = false,
  });

  final String shapeId;
  final SlideAnimationEffect effect;
  final SlideAnimationDirection direction;
  final SlideAnimationTrigger trigger;
  final int durationMs;
  final int delayMs;

  /// `0` = auto-plays on slide entry; `>= 1` = plays on tap step `clickGroup`.
  final int clickGroup;
  final bool isEmphasis;
}

/// A complete presentation slide containing visual elements, extracted text, and media.
class PresentationSlide {
  const PresentationSlide({
    required this.slideNumber,
    required this.title,
    required this.bulletPoints,
    required this.images,
    this.elements = const [],
    this.backgroundColor,
    this.backgroundImage,
    this.transitionType = SlideTransitionType.fade,
    this.transitionDurationMs = 400,
    this.animations = const [],
  });

  final int slideNumber;
  final String title;
  final List<String> bulletPoints;
  final List<Uint8List> images;
  final List<SlideElement> elements;
  final Color? backgroundColor;
  final Uint8List? backgroundImage;
  final SlideTransitionType transitionType;
  final int transitionDurationMs;
  final List<SlideAnimationStep> animations;

  /// Number of interactive click steps (`clickGroup >= 1`) on this slide.
  int get animationClickStepCount {
    int maxGroup = 0;
    for (final step in animations) {
      if (step.clickGroup > maxGroup) {
        maxGroup = step.clickGroup;
      }
    }
    return maxGroup;
  }
}

/// An entire parsed presentation deck with canvas dimensions and slides.
class PresentationDeck {
  const PresentationDeck({
    required this.slides,
    this.slideWidthEmu = 12192000,
    this.slideHeightEmu = 6858000,
    this.themeColors = const {},
  });

  final List<PresentationSlide> slides;
  final int slideWidthEmu;
  final int slideHeightEmu;
  final Map<String, Color> themeColors;

  /// Aspect ratio of the presentation (e.g. 16:9 = ~1.778, 4:3 = ~1.333).
  double get aspectRatio =>
      slideHeightEmu > 0 ? (slideWidthEmu / slideHeightEmu) : (16 / 9);
}

/// Coordinate transformation context for nested group shapes (`p:grpSp`).
class _TransformContext {
  const _TransformContext({
    required this.offX,
    required this.offY,
    required this.extW,
    required this.extH,
    required this.chOffX,
    required this.chOffY,
    required this.chExtW,
    required this.chExtH,
  });

  final int offX;
  final int offY;
  final int extW;
  final int extH;
  final int chOffX;
  final int chOffY;
  final int chExtW;
  final int chExtH;

  int transformX(int x) {
    if (chExtW == 0) return offX + x;
    return (offX + ((x - chOffX) * extW / chExtW)).round();
  }

  int transformY(int y) {
    if (chExtH == 0) return offY + y;
    return (offY + ((y - chOffY) * extH / chExtH)).round();
  }

  int transformW(int w) {
    if (chExtW == 0) return w;
    return (w * extW / chExtW).round();
  }

  int transformH(int h) {
    if (chExtH == 0) return h;
    return (h * extH / chExtH).round();
  }
}

class _PlaceholderTemplate {
  const _PlaceholderTemplate({
    this.rect,
    this.rotation = 0.0,
    this.fillColor,
    this.borderColor,
    this.borderWidth = 0.0,
    this.defaultFontSize,
    this.defaultFontColor,
    this.defaultBold,
  });

  final Rect? rect;
  final double rotation;
  final Color? fillColor;
  final Color? borderColor;
  final double borderWidth;
  final double? defaultFontSize;
  final Color? defaultFontColor;
  final bool? defaultBold;
}

class _LayoutTemplate {
  const _LayoutTemplate({
    this.backgroundColor,
    this.backgroundImage,
    this.byTypeAndIdx = const {},
    this.byType = const {},
  });

  final Color? backgroundColor;
  final Uint8List? backgroundImage;
  final Map<String, _PlaceholderTemplate> byTypeAndIdx;
  final Map<String, _PlaceholderTemplate> byType;

  _PlaceholderTemplate? lookup(String? type, String? idx) {
    if (type != null && idx != null) {
      final exact = byTypeAndIdx['$type#$idx'];
      if (exact != null) return exact;
    }
    if (type != null) {
      final byT = byType[type];
      if (byT != null) return byT;
      if (type == 'ctrTitle') return byType['title'];
      if (type == 'title') return byType['ctrTitle'];
      if (type == 'obj') return byType['body'];
      if (type == 'body') return byType['obj'];
    }
    return null;
  }
}

/// Comprehensive parser for PowerPoint (.pptx) presentations.
/// Extracts high-fidelity visual layout (geometry, shapes, styling, fonts, images),
/// slide transitions, and `<p:timing>` animations, while preserving text / bullets
/// for outline and search.
class PresentationParser {
  const PresentationParser._();

  static const int _defaultSlideWidthEmu = 12192000; // 13.33 inches (16:9 widescreen)
  static const int _defaultSlideHeightEmu = 6858000; // 7.5 inches
  static const int _isolateThresholdBytes = 32 * 1024;

  static Future<PresentationDeck> parse(Uint8List bytes) async {
    if (!kIsWeb && bytes.length >= _isolateThresholdBytes) {
      return compute(parseSync, bytes);
    }
    return parseSync(bytes);
  }

  static PresentationDeck parseSync(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    // 1. Read slide dimensions from presentation.xml
    int slideWidthEmu = _defaultSlideWidthEmu;
    int slideHeightEmu = _defaultSlideHeightEmu;

    final presFile = archive.findFile('ppt/presentation.xml');
    if (presFile != null) {
      try {
        final content = EncodingUtils.decodeDocumentBytes(presFile.content as List<int>);
        final doc = XmlDocument.parse(content);
        final sldSz = doc.findAllElements('p:sldSz').firstOrNull ??
            doc.findAllElements('sldSz').firstOrNull;
        if (sldSz != null) {
          final cx = int.tryParse(sldSz.getAttribute('cx') ?? '');
          final cy = int.tryParse(sldSz.getAttribute('cy') ?? '');
          if (cx != null && cx > 0) slideWidthEmu = cx;
          if (cy != null && cy > 0) slideHeightEmu = cy;
        }
      } catch (_) {
        // Fall back to 16:9 standard
      }
    }

    // 2. Read Theme colors from ppt/theme/theme1.xml
    final themeColors = <String, Color>{
      'dk1': const Color(0xFF000000),
      'lt1': const Color(0xFFFFFFFF),
      'dk2': const Color(0xFF1F497D),
      'lt2': const Color(0xFFEEECE1),
      'accent1': const Color(0xFF4F81BD),
      'accent2': const Color(0xFFC0504D),
      'accent3': const Color(0xFF9BBB59),
      'accent4': const Color(0xFF8064A2),
      'accent5': const Color(0xFF4BACC6),
      'accent6': const Color(0xFFF79646),
      'hlink': const Color(0xFF0000FF),
      'folHlink': const Color(0xFF800080),
    };

    final themeFile = archive.findFile('ppt/theme/theme1.xml') ??
        archive.files.where((f) => f.name.startsWith('ppt/theme/theme') && f.name.endsWith('.xml')).firstOrNull;
    if (themeFile != null) {
      try {
        final content = EncodingUtils.decodeDocumentBytes(themeFile.content as List<int>);
        final doc = XmlDocument.parse(content);
        final clrScheme = doc.findAllElements('a:clrScheme').firstOrNull ??
            doc.findAllElements('clrScheme').firstOrNull;
        if (clrScheme != null) {
          for (final child in clrScheme.children.whereType<XmlElement>()) {
            final key = child.name.local;
            final color = _parseRawColor(child, themeColors);
            if (color != null) {
              themeColors[key] = color;
            }
          }
        }
      } catch (_) {}
    }

    // 3. Read slide order from presentation.xml.rels and presentation.xml
    final presRelsFile = archive.findFile('ppt/_rels/presentation.xml.rels');
    final slidePathsMap = <String, String>{};
    if (presRelsFile != null) {
      try {
        final content = EncodingUtils.decodeDocumentBytes(presRelsFile.content as List<int>);
        final doc = XmlDocument.parse(content);
        for (final rel in doc.findAllElements('Relationship')) {
          final id = rel.getAttribute('Id');
          final target = rel.getAttribute('Target');
          if (id != null && target != null && target.contains('slide')) {
            final normalized = _normalizePptTarget('ppt/', target);
            slidePathsMap[id] = normalized;
          }
        }
      } catch (_) {}
    }

    final slidePaths = <String>[];
    if (presFile != null) {
      try {
        final content = EncodingUtils.decodeDocumentBytes(presFile.content as List<int>);
        final doc = XmlDocument.parse(content);
        for (final sldId in doc.findAllElements('p:sldId')) {
          final rId = sldId.getAttribute('r:id');
          if (rId != null && slidePathsMap.containsKey(rId)) {
            slidePaths.add(slidePathsMap[rId]!);
          }
        }
      } catch (_) {}
    }

    // Fallback: list slide files in archive
    if (slidePaths.isEmpty) {
      for (final file in archive.files) {
        if (file.name.startsWith('ppt/slides/slide') && file.name.endsWith('.xml') && !file.name.contains('_rels')) {
          slidePaths.add(file.name);
        }
      }
      slidePaths.sort();
    }

    final mediaCache = <String, Uint8List>{};
    final masterCache = <String, _LayoutTemplate>{};
    final layoutCache = <String, _LayoutTemplate>{};
    final parsedSlides = <PresentationSlide>[];

    for (int i = 0; i < slidePaths.length; i++) {
      final path = slidePaths[i];
      final slideFile = archive.findFile(path);
      if (slideFile == null) continue;

      // Map slide-specific relationships (media, slide layouts)
      final relsPath = _relsPathFor(path);
      final slideRelsFile = archive.findFile(relsPath);
      final mediaMap = <String, String>{};
      String? layoutPath;

      if (slideRelsFile != null) {
        try {
          final relsXml = EncodingUtils.decodeDocumentBytes(slideRelsFile.content as List<int>);
          final relsDoc = XmlDocument.parse(relsXml);
          for (final rel in relsDoc.findAllElements('Relationship')) {
            final id = rel.getAttribute('Id');
            final target = rel.getAttribute('Target');
            final type = rel.getAttribute('Type') ?? '';
            if (id == null || target == null) continue;

            if (type.contains('slideLayout') || target.contains('slideLayout')) {
              layoutPath = _normalizePptTarget(_dirOf(path), target);
            } else if (target.contains('media/')) {
              mediaMap[id] = _normalizePptTarget(_dirOf(path), target);
            }
          }
        } catch (_) {}
      }

      // Load and cache slideLayout (+ its parent slideMaster) template
      final _LayoutTemplate? layoutTemplate = layoutPath != null
          ? _loadLayoutTemplate(
              layoutPath: layoutPath,
              archive: archive,
              themeColors: themeColors,
              slideWidthEmu: slideWidthEmu,
              slideHeightEmu: slideHeightEmu,
              mediaCache: mediaCache,
              masterCache: masterCache,
              layoutCache: layoutCache,
            )
          : null;

      // Parse slide XML
      final slideXml = EncodingUtils.decodeDocumentBytes(slideFile.content as List<int>);
      final slideDoc = XmlDocument.parse(slideXml);

      // Slide background (slide -> layout -> master)
      final (slideBgColor, slideBgImage) = _parseBackground(
        doc: slideDoc,
        archive: archive,
        mediaMap: mediaMap,
        mediaCache: mediaCache,
        themeColors: themeColors,
      );
      final Color? slideBackgroundColor = slideBgColor ?? layoutTemplate?.backgroundColor;
      final Uint8List? slideBackgroundImage = slideBgImage ?? layoutTemplate?.backgroundImage;

      final visualElements = <SlideElement>[];
      final allImages = <Uint8List>[];

      // Parse Shape Tree (p:spTree)
      final spTree = slideDoc.findAllElements('p:spTree').firstOrNull ??
          slideDoc.findAllElements('spTree').firstOrNull;

      if (spTree != null) {
        _parseShapeContainer(
          container: spTree,
          archive: archive,
          mediaMap: mediaMap,
          mediaCache: mediaCache,
          themeColors: themeColors,
          slideWidthEmu: slideWidthEmu,
          slideHeightEmu: slideHeightEmu,
          elementsOut: visualElements,
          imagesOut: allImages,
          layoutTemplate: layoutTemplate,
        );
      }

      // Extract titles and bullets for backward compatibility and outline mode
      String title = '';
      final bulletPoints = <String>[];

      for (final sp in slideDoc.findAllElements('p:sp')) {
        final isTitle = sp.findAllElements('p:ph').any((ph) {
          final type = ph.getAttribute('type');
          return type == 'title' || type == 'ctrTitle';
        });

        final paragraphs = sp.findAllElements('a:p');
        for (final p in paragraphs) {
          final text = p.findAllElements('a:t').map((e) => e.innerText).join().trim();
          if (text.isEmpty) continue;

          if (isTitle && title.isEmpty) {
            title = text;
          } else {
            bulletPoints.add(text);
          }
        }
      }

      if (title.isEmpty && bulletPoints.isNotEmpty) {
        title = bulletPoints.removeAt(0);
      }
      if (title.isEmpty) {
        title = 'Slide ${i + 1}';
      }

      final transitionType = _parseTransition(slideDoc);
      final transitionDurationMs = _parseTransitionDuration(slideDoc);
      final animations = _parseTiming(slideDoc);

      parsedSlides.add(
        PresentationSlide(
          slideNumber: i + 1,
          title: title,
          bulletPoints: bulletPoints,
          images: allImages,
          elements: visualElements,
          backgroundColor: slideBackgroundColor,
          backgroundImage: slideBackgroundImage,
          transitionType: transitionType,
          transitionDurationMs: transitionDurationMs,
          animations: animations,
        ),
      );
    }

    return PresentationDeck(
      slides: parsedSlides,
      slideWidthEmu: slideWidthEmu,
      slideHeightEmu: slideHeightEmu,
      themeColors: themeColors,
    );
  }

  static String _dirOf(String path) {
    final idx = path.lastIndexOf('/');
    return idx >= 0 ? path.substring(0, idx + 1) : '';
  }

  static String _relsPathFor(String xmlPath) {
    final dir = _dirOf(xmlPath);
    final fileName = xmlPath.substring(dir.length);
    return '${dir}_rels/$fileName.rels';
  }

  static String _normalizePptTarget(String baseDir, String target) {
    if (target.startsWith('/')) {
      return target.substring(1);
    }
    final combined = '$baseDir$target';
    final parts = combined.split('/');
    final resolved = <String>[];
    for (final part in parts) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (resolved.isNotEmpty) resolved.removeLast();
      } else {
        resolved.add(part);
      }
    }
    return resolved.join('/');
  }

  static Uint8List? _loadMediaBytes(
    Archive archive,
    String path,
    Map<String, Uint8List> mediaCache,
  ) {
    final cached = mediaCache[path];
    if (cached != null) return cached;

    var file = archive.findFile(path);
    if (file == null) {
      final fileName = path.split('/').last;
      file = archive.findFile('ppt/media/$fileName');
    }
    if (file == null) return null;

    final bytes = Uint8List.fromList(file.content as List<int>);
    mediaCache[path] = bytes;
    return bytes;
  }

  static (Color?, Uint8List?) _parseBackground({
    required XmlDocument doc,
    required Archive archive,
    required Map<String, String> mediaMap,
    required Map<String, Uint8List> mediaCache,
    required Map<String, Color> themeColors,
  }) {
    Color? bgColor;
    Uint8List? bgImage;
    final bgElem =
        doc.findAllElements('p:bg').firstOrNull ?? doc.findAllElements('bg').firstOrNull;
    if (bgElem != null) {
      bgColor = _parseColorFromParent(bgElem, themeColors);
      if (bgColor == null) {
        final bgRef = bgElem.findAllElements('p:bgRef').firstOrNull ??
            bgElem.findAllElements('bgRef').firstOrNull;
        if (bgRef != null) {
          bgColor = _parseRawColor(bgRef, themeColors);
        }
      }
      final blip = bgElem.findAllElements('a:blip').firstOrNull ??
          bgElem.findAllElements('blip').firstOrNull;
      if (blip != null) {
        final rEmbed = blip.getAttribute('r:embed');
        if (rEmbed != null && mediaMap.containsKey(rEmbed)) {
          bgImage = _loadMediaBytes(archive, mediaMap[rEmbed]!, mediaCache);
        }
      }
    }
    return (bgColor, bgImage);
  }

  static Map<String, String> _readRelsMediaAndMaster(
    Archive archive,
    String xmlPath, {
    required void Function(String masterPath) onMasterFound,
  }) {
    final mediaMap = <String, String>{};
    final relsFile = archive.findFile(_relsPathFor(xmlPath));
    if (relsFile == null) return mediaMap;

    try {
      final relsXml = EncodingUtils.decodeDocumentBytes(relsFile.content as List<int>);
      final relsDoc = XmlDocument.parse(relsXml);
      final baseDir = _dirOf(xmlPath);
      for (final rel in relsDoc.findAllElements('Relationship')) {
        final id = rel.getAttribute('Id');
        final target = rel.getAttribute('Target');
        final type = rel.getAttribute('Type') ?? '';
        if (id == null || target == null) continue;
        if (type.contains('slideMaster') || target.contains('slideMaster')) {
          onMasterFound(_normalizePptTarget(baseDir, target));
        } else if (target.contains('media/')) {
          mediaMap[id] = _normalizePptTarget(baseDir, target);
        }
      }
    } catch (_) {}
    return mediaMap;
  }

  static _LayoutTemplate? _loadLayoutTemplate({
    required String layoutPath,
    required Archive archive,
    required Map<String, Color> themeColors,
    required int slideWidthEmu,
    required int slideHeightEmu,
    required Map<String, Uint8List> mediaCache,
    required Map<String, _LayoutTemplate> masterCache,
    required Map<String, _LayoutTemplate> layoutCache,
  }) {
    final existing = layoutCache[layoutPath];
    if (existing != null) return existing;

    final layoutFile = archive.findFile(layoutPath);
    if (layoutFile == null) return null;

    String? masterPath;
    final layoutMediaMap = _readRelsMediaAndMaster(
      archive,
      layoutPath,
      onMasterFound: (p) => masterPath = p,
    );

    _LayoutTemplate? masterTemplate;
    if (masterPath != null) {
      masterTemplate = masterCache[masterPath];
      if (masterTemplate == null) {
        final masterFile = archive.findFile(masterPath!);
        if (masterFile != null) {
          try {
            final masterMediaMap = _readRelsMediaAndMaster(
              archive,
              masterPath!,
              onMasterFound: (_) {},
            );
            final masterDoc = XmlDocument.parse(
              EncodingUtils.decodeDocumentBytes(masterFile.content as List<int>),
            );
            masterTemplate = _parseTemplateDoc(
              doc: masterDoc,
              archive: archive,
              mediaMap: masterMediaMap,
              mediaCache: mediaCache,
              themeColors: themeColors,
              slideWidthEmu: slideWidthEmu,
              slideHeightEmu: slideHeightEmu,
            );
            masterCache[masterPath!] = masterTemplate;
          } catch (_) {}
        }
      }
    }

    try {
      final layoutDoc = XmlDocument.parse(
        EncodingUtils.decodeDocumentBytes(layoutFile.content as List<int>),
      );
      final parsedLayout = _parseTemplateDoc(
        doc: layoutDoc,
        archive: archive,
        mediaMap: layoutMediaMap,
        mediaCache: mediaCache,
        themeColors: themeColors,
        slideWidthEmu: slideWidthEmu,
        slideHeightEmu: slideHeightEmu,
        parent: masterTemplate,
      );
      layoutCache[layoutPath] = parsedLayout;
      return parsedLayout;
    } catch (_) {
      return masterTemplate;
    }
  }

  static _LayoutTemplate _parseTemplateDoc({
    required XmlDocument doc,
    required Archive archive,
    required Map<String, String> mediaMap,
    required Map<String, Uint8List> mediaCache,
    required Map<String, Color> themeColors,
    required int slideWidthEmu,
    required int slideHeightEmu,
    _LayoutTemplate? parent,
  }) {
    final (bgColor, bgImage) = _parseBackground(
      doc: doc,
      archive: archive,
      mediaMap: mediaMap,
      mediaCache: mediaCache,
      themeColors: themeColors,
    );

    final byTypeAndIdx = <String, _PlaceholderTemplate>{
      ...?parent?.byTypeAndIdx,
    };
    final byType = <String, _PlaceholderTemplate>{
      ...?parent?.byType,
    };

    for (final sp in doc.findAllElements('p:sp')) {
      final ph = sp.findAllElements('p:ph').firstOrNull ??
          sp.findAllElements('ph').firstOrNull;
      if (ph == null) continue;

      final phType = ph.getAttribute('type') ?? 'body';
      final phIdx = ph.getAttribute('idx');

      final spPr = sp.findAllElements('p:spPr').firstOrNull ??
          sp.findAllElements('spPr').firstOrNull;
      final xfrm = _parseTransform(
        spPr: spPr,
        slideWidthEmu: slideWidthEmu,
        slideHeightEmu: slideHeightEmu,
      );

      Color? fillColor;
      Color? borderColor;
      double borderWidth = 0.0;
      if (spPr != null) {
        fillColor = _parseColorFromParent(spPr, themeColors);
        final ln = spPr.findAllElements('a:ln').firstOrNull ??
            spPr.findAllElements('ln').firstOrNull;
        if (ln != null) {
          borderColor = _parseColorFromParent(ln, themeColors);
          final wAttr = ln.getAttribute('w');
          if (wAttr != null) {
            final emuW = int.tryParse(wAttr) ?? 0;
            borderWidth = (emuW / 12700.0).clamp(0.5, 12.0);
          } else if (borderColor != null) {
            borderWidth = 1.0;
          }
        }
      }

      double? defaultFontSize;
      Color? defaultFontColor;
      bool? defaultBold;
      final defRPr = sp.findAllElements('a:defRPr').firstOrNull ??
          sp.findAllElements('defRPr').firstOrNull;
      if (defRPr != null) {
        final sz = defRPr.getAttribute('sz');
        if (sz != null) {
          final szInt = int.tryParse(sz);
          if (szInt != null && szInt > 0) defaultFontSize = szInt / 100.0;
        }
        final b = defRPr.getAttribute('b');
        if (b != null) defaultBold = b == '1' || b == 'true';
        defaultFontColor = _parseColorFromParent(defRPr, themeColors);
      }

      final inherited = parent?.lookup(phType, phIdx);
      final tpl = _PlaceholderTemplate(
        rect: xfrm?.$1 ?? inherited?.rect,
        rotation: xfrm?.$2 ?? inherited?.rotation ?? 0.0,
        fillColor: fillColor ?? inherited?.fillColor,
        borderColor: borderColor ?? inherited?.borderColor,
        borderWidth: borderWidth > 0 ? borderWidth : (inherited?.borderWidth ?? 0.0),
        defaultFontSize: defaultFontSize ?? inherited?.defaultFontSize,
        defaultFontColor: defaultFontColor ?? inherited?.defaultFontColor,
        defaultBold: defaultBold ?? inherited?.defaultBold,
      );

      if (phIdx != null) {
        byTypeAndIdx['$phType#$phIdx'] = tpl;
      }
      byType[phType] = tpl;
    }

    return _LayoutTemplate(
      backgroundColor: bgColor ?? parent?.backgroundColor,
      backgroundImage: bgImage ?? parent?.backgroundImage,
      byTypeAndIdx: byTypeAndIdx,
      byType: byType,
    );
  }

  static String? _extractShapeId(XmlElement element, String nvContainerTag) {
    final nv = element.findElements(nvContainerTag).firstOrNull ??
        element.findElements(nvContainerTag.replaceFirst('p:', '')).firstOrNull;
    final cNvPr = nv?.findElements('p:cNvPr').firstOrNull ??
        nv?.findElements('cNvPr').firstOrNull ??
        element.findAllElements('p:cNvPr').firstOrNull ??
        element.findAllElements('cNvPr').firstOrNull;
    return cNvPr?.getAttribute('id');
  }

  /// Parses all children of a container (spTree or grpSp) in z-order.
  static void _parseShapeContainer({
    required XmlElement container,
    required Archive archive,
    required Map<String, String> mediaMap,
    required Map<String, Uint8List> mediaCache,
    required Map<String, Color> themeColors,
    required int slideWidthEmu,
    required int slideHeightEmu,
    required List<SlideElement> elementsOut,
    required List<Uint8List> imagesOut,
    _LayoutTemplate? layoutTemplate,
    _TransformContext? transformContext,
    String? groupShapeId,
    int? fallbackIndex,
  }) {
    int autoFlowIndex = fallbackIndex ?? 0;

    for (final child in container.children.whereType<XmlElement>()) {
      final name = child.name.local;

      if (name == 'pic') {
        // ------------------ PICTURE ------------------
        final shapeId = _extractShapeId(child, 'p:nvPicPr');
        final xfrm = _parseTransform(
          spPr: child.findAllElements('p:spPr').firstOrNull ?? child.findAllElements('spPr').firstOrNull,
          slideWidthEmu: slideWidthEmu,
          slideHeightEmu: slideHeightEmu,
          transformContext: transformContext,
        );

        final blip = child.findAllElements('a:blip').firstOrNull ?? child.findAllElements('blip').firstOrNull;
        Uint8List? imgBytes;
        if (blip != null) {
          final rEmbed = blip.getAttribute('r:embed');
          if (rEmbed != null && mediaMap.containsKey(rEmbed)) {
            imgBytes = _loadMediaBytes(archive, mediaMap[rEmbed]!, mediaCache);
            if (imgBytes != null) {
              imagesOut.add(imgBytes);
            }
          }
        }

        if (imgBytes != null) {
          final rect = xfrm?.$1 ??
              _fallbackRectForIndex(autoFlowIndex++, isImage: true);
          final rot = xfrm?.$2 ?? 0.0;

          elementsOut.add(
            SlidePictureElement(
              x: rect.left,
              y: rect.top,
              width: rect.width,
              height: rect.height,
              rotation: rot,
              shapeId: shapeId,
              groupShapeId: groupShapeId,
              imageBytes: imgBytes,
            ),
          );
        }
      } else if (name == 'sp') {
        // ------------------ SHAPE / TEXT ------------------
        final shapeId = _extractShapeId(child, 'p:nvSpPr');
        final spPr = child.findAllElements('p:spPr').firstOrNull ?? child.findAllElements('spPr').firstOrNull;
        final txBody = child.findAllElements('p:txBody').firstOrNull ?? child.findAllElements('txBody').firstOrNull;

        final ph = child.findAllElements('p:ph').firstOrNull ??
            child.findAllElements('ph').firstOrNull;
        final isPlaceholder = ph != null;
        final phType = ph?.getAttribute('type') ?? (isPlaceholder ? 'body' : null);
        final phIdx = ph?.getAttribute('idx');
        final phTemplate = isPlaceholder ? layoutTemplate?.lookup(phType, phIdx) : null;

        final isTitle = phType == 'title' || phType == 'ctrTitle';

        final xfrm = _parseTransform(
          spPr: spPr,
          slideWidthEmu: slideWidthEmu,
          slideHeightEmu: slideHeightEmu,
          transformContext: transformContext,
        );

        Color? fillColor;
        Color? borderColor;
        double borderWidth = 0.0;
        double borderRadius = 0.0;
        bool isCircle = false;

        if (spPr != null) {
          fillColor = _parseColorFromParent(spPr, themeColors);
          final ln = spPr.findAllElements('a:ln').firstOrNull ?? spPr.findAllElements('ln').firstOrNull;
          if (ln != null) {
            borderColor = _parseColorFromParent(ln, themeColors);
            final wAttr = ln.getAttribute('w');
            if (wAttr != null) {
              final emuW = int.tryParse(wAttr) ?? 0;
              borderWidth = (emuW / 12700.0).clamp(0.5, 12.0);
            } else if (borderColor != null) {
              borderWidth = 1.0;
            }
          }

          final prstGeom = spPr.findAllElements('a:prstGeom').firstOrNull ??
              spPr.findAllElements('prstGeom').firstOrNull;
          if (prstGeom != null) {
            final prst = prstGeom.getAttribute('prst');
            if (prst == 'roundRect') {
              borderRadius = 8.0;
            } else if (prst == 'ellipse') {
              isCircle = true;
            }
          }
        }

        fillColor ??= phTemplate?.fillColor;
        if (borderColor == null && phTemplate?.borderColor != null) {
          borderColor = phTemplate!.borderColor;
          borderWidth = phTemplate.borderWidth;
        }

        // Parse paragraphs
        final paragraphs = <SlideParagraph>[];
        Alignment verticalAlignment = Alignment.topLeft;

        if (txBody != null) {
          final bodyPr = txBody.findAllElements('a:bodyPr').firstOrNull ??
              txBody.findAllElements('bodyPr').firstOrNull;
          if (bodyPr != null) {
            final anchor = bodyPr.getAttribute('anchor');
            if (anchor == 'ctr') {
              verticalAlignment = Alignment.centerLeft;
            } else if (anchor == 'b') {
              verticalAlignment = Alignment.bottomLeft;
            }
          }

          for (final p in txBody.findAllElements('a:p')) {
            final pPr = p.findAllElements('a:pPr').firstOrNull ?? p.findAllElements('pPr').firstOrNull;
            TextAlign alignment = TextAlign.left;
            bool isBullet = false;
            String? bulletChar;

            if (pPr != null) {
              final algn = pPr.getAttribute('algn');
              if (algn == 'ctr') {
                alignment = TextAlign.center;
              } else if (algn == 'r') {
                alignment = TextAlign.right;
              } else if (algn == 'just') {
                alignment = TextAlign.justify;
              }

              final buChar = pPr.findAllElements('a:buChar').firstOrNull ??
                  pPr.findAllElements('buChar').firstOrNull;
              if (buChar != null) {
                isBullet = true;
                bulletChar = buChar.getAttribute('char') ?? '•';
              } else if (pPr.findAllElements('a:buNone').isEmpty && pPr.getAttribute('lvl') != null) {
                isBullet = true;
                bulletChar = '•';
              }
            }

            final spans = <SlideTextSpan>[];
            for (final childNode in p.children) {
              if (childNode is! XmlElement) continue;
              final nodeName = childNode.name.local;

              if (nodeName == 'r') {
                final rPr = childNode.findAllElements('a:rPr').firstOrNull ??
                    childNode.findAllElements('rPr').firstOrNull;
                final t = childNode.findAllElements('a:t').firstOrNull ??
                    childNode.findAllElements('t').firstOrNull;
                final text = t?.innerText ?? '';
                if (text.isEmpty) continue;

                double fontSize = phTemplate?.defaultFontSize ?? (isTitle ? 28.0 : 16.0);
                bool bold = phTemplate?.defaultBold ?? isTitle;
                bool italic = false;
                bool underline = false;
                Color? fontColor = phTemplate?.defaultFontColor;
                String? fontFamily;

                if (rPr != null) {
                  final sz = rPr.getAttribute('sz');
                  if (sz != null) {
                    final szInt = int.tryParse(sz);
                    if (szInt != null && szInt > 0) {
                      fontSize = szInt / 100.0;
                    }
                  }

                  final b = rPr.getAttribute('b');
                  if (b != null) bold = b == '1' || b == 'true';

                  final i = rPr.getAttribute('i');
                  if (i != null) italic = i == '1' || i == 'true';

                  final u = rPr.getAttribute('u');
                  if (u != null && u != 'none') underline = true;

                  fontColor = _parseColorFromParent(rPr, themeColors) ?? fontColor;

                  final latin = rPr.findAllElements('a:latin').firstOrNull ??
                      rPr.findAllElements('latin').firstOrNull;
                  if (latin != null) {
                    fontFamily = latin.getAttribute('typeface');
                  }
                }

                spans.add(
                  SlideTextSpan(
                    text: text,
                    fontSize: fontSize,
                    fontColor: fontColor,
                    bold: bold,
                    italic: italic,
                    underline: underline,
                    fontFamily: fontFamily,
                  ),
                );
              } else if (nodeName == 'br') {
                spans.add(const SlideTextSpan(text: '\n'));
              }
            }

            if (spans.isNotEmpty) {
              paragraphs.add(
                SlideParagraph(
                  spans: spans,
                  alignment: alignment,
                  isBullet: isBullet,
                  bulletChar: bulletChar,
                ),
              );
            }
          }
        }

        // Only add if there is visual presence (text or background fill or border)
        final hasText = paragraphs.any((p) => p.plainText.trim().isNotEmpty);
        final hasVisualBox = fillColor != null || borderColor != null;

        if (hasText || hasVisualBox) {
          final rect = xfrm?.$1 ??
              phTemplate?.rect ??
              (isTitle
                  ? const Rect.fromLTWH(0.08, 0.08, 0.84, 0.16)
                  : _fallbackRectForIndex(autoFlowIndex++));
          final rot = xfrm?.$2 ?? phTemplate?.rotation ?? 0.0;

          final isBgDecor = !hasText &&
              ((rect.width * rect.height >= 0.60) ||
                  (rect.width >= 0.90 && rect.height <= 0.08) ||
                  (rect.height >= 0.90 && rect.width <= 0.08));

          elementsOut.add(
            SlideShapeElement(
              x: rect.left,
              y: rect.top,
              width: rect.width,
              height: rect.height,
              rotation: rot,
              shapeId: shapeId,
              groupShapeId: groupShapeId,
              isBackgroundDecor: isBgDecor,
              fillColor: fillColor,
              borderColor: borderColor,
              borderWidth: borderWidth,
              borderRadius: borderRadius,
              isCircle: isCircle,
              paragraphs: paragraphs,
              verticalAlignment: verticalAlignment,
              isPlaceholder: isPlaceholder,
            ),
          );
        }
      } else if (name == 'graphicFrame') {
        // ------------------ TABLE / GRAPHIC ------------------
        final shapeId = _extractShapeId(child, 'p:nvGraphicFramePr');
        final xfrm = _parseTransform(
          spPr: child.findAllElements('p:spPr').firstOrNull ?? child.findAllElements('spPr').firstOrNull ?? child,
          slideWidthEmu: slideWidthEmu,
          slideHeightEmu: slideHeightEmu,
          transformContext: transformContext,
        );

        final tbl = child.findAllElements('a:tbl').firstOrNull ?? child.findAllElements('tbl').firstOrNull;
        if (tbl != null) {
          final colWidthRatios = <double>[];
          final tblGrid = tbl.findAllElements('a:tblGrid').firstOrNull ?? tbl.findAllElements('tblGrid').firstOrNull;
          if (tblGrid != null) {
            for (final col in tblGrid.findAllElements('a:gridCol')) {
              final w = int.tryParse(col.getAttribute('w') ?? '') ?? 1;
              colWidthRatios.add(w.toDouble());
            }
          }

          final rows = <List<SlideTableCell>>[];
          for (final tr in tbl.findAllElements('a:tr')) {
            final rowCells = <SlideTableCell>[];
            for (final tc in tr.findAllElements('a:tc')) {
              final tcPr = tc.findAllElements('a:tcPr').firstOrNull ?? tc.findAllElements('tcPr').firstOrNull;
              Color? cellFill;
              if (tcPr != null) {
                cellFill = _parseColorFromParent(tcPr, themeColors);
              }

              final cellParagraphs = <SlideParagraph>[];
              for (final p in tc.findAllElements('a:p')) {
                final spans = <SlideTextSpan>[];
                for (final r in p.findAllElements('a:r')) {
                  final t = r.findAllElements('a:t').firstOrNull?.innerText ?? '';
                  if (t.isNotEmpty) {
                    spans.add(SlideTextSpan(text: t, fontSize: 13.0));
                  }
                }
                if (spans.isNotEmpty) {
                  cellParagraphs.add(SlideParagraph(spans: spans));
                }
              }
              rowCells.add(SlideTableCell(paragraphs: cellParagraphs, fillColor: cellFill));
            }
            if (rowCells.isNotEmpty) rows.add(rowCells);
          }

          if (rows.isNotEmpty) {
            final rect = xfrm?.$1 ?? _fallbackRectForIndex(autoFlowIndex++);
            elementsOut.add(
              SlideTableElement(
                x: rect.left,
                y: rect.top,
                width: rect.width,
                height: rect.height,
                rotation: xfrm?.$2 ?? 0.0,
                shapeId: shapeId,
                groupShapeId: groupShapeId,
                rows: rows,
                colWidthRatios: colWidthRatios,
              ),
            );
          }
        }
      } else if (name == 'grpSp') {
        // ------------------ GROUP SHAPES ------------------
        final grpId = _extractShapeId(child, 'p:nvGrpSpPr') ?? groupShapeId;
        final grpSpPr = child.findAllElements('p:grpSpPr').firstOrNull ?? child.findAllElements('grpSpPr').firstOrNull;
        _TransformContext? groupContext;

        if (grpSpPr != null) {
          final xfrm = grpSpPr.findAllElements('a:xfrm').firstOrNull ?? grpSpPr.findAllElements('xfrm').firstOrNull;
          if (xfrm != null) {
            final off = xfrm.findAllElements('a:off').firstOrNull ?? xfrm.findAllElements('off').firstOrNull;
            final ext = xfrm.findAllElements('a:ext').firstOrNull ?? xfrm.findAllElements('ext').firstOrNull;
            final chOff = xfrm.findAllElements('a:chOff').firstOrNull ?? xfrm.findAllElements('chOff').firstOrNull;
            final chExt = xfrm.findAllElements('a:chExt').firstOrNull ?? xfrm.findAllElements('chExt').firstOrNull;

            if (off != null && ext != null && chOff != null && chExt != null) {
              int offX = int.tryParse(off.getAttribute('x') ?? '0') ?? 0;
              int offY = int.tryParse(off.getAttribute('y') ?? '0') ?? 0;
              int extW = int.tryParse(ext.getAttribute('cx') ?? '0') ?? 0;
              int extH = int.tryParse(ext.getAttribute('cy') ?? '0') ?? 0;
              final chOffX = int.tryParse(chOff.getAttribute('x') ?? '0') ?? 0;
              final chOffY = int.tryParse(chOff.getAttribute('y') ?? '0') ?? 0;
              final chExtW = int.tryParse(chExt.getAttribute('cx') ?? '0') ?? 0;
              final chExtH = int.tryParse(chExt.getAttribute('cy') ?? '0') ?? 0;

              if (transformContext != null) {
                offX = transformContext.transformX(offX);
                offY = transformContext.transformY(offY);
                extW = transformContext.transformW(extW);
                extH = transformContext.transformH(extH);
              }

              groupContext = _TransformContext(
                offX: offX,
                offY: offY,
                extW: extW,
                extH: extH,
                chOffX: chOffX,
                chOffY: chOffY,
                chExtW: chExtW,
                chExtH: chExtH,
              );
            }
          }
        }

        // Recurse into group children
        _parseShapeContainer(
          container: child,
          archive: archive,
          mediaMap: mediaMap,
          mediaCache: mediaCache,
          themeColors: themeColors,
          slideWidthEmu: slideWidthEmu,
          slideHeightEmu: slideHeightEmu,
          elementsOut: elementsOut,
          imagesOut: imagesOut,
          layoutTemplate: layoutTemplate,
          transformContext: groupContext ?? transformContext,
          groupShapeId: grpId,
          fallbackIndex: autoFlowIndex,
        );
      }
    }
  }

  /// Parses 2D position, dimensions, and rotation from `<a:xfrm>`.
  static (Rect, double)? _parseTransform({
    required XmlElement? spPr,
    required int slideWidthEmu,
    required int slideHeightEmu,
    _TransformContext? transformContext,
  }) {
    if (spPr == null) return null;
    final xfrm = spPr.findAllElements('a:xfrm').firstOrNull ?? spPr.findAllElements('xfrm').firstOrNull;
    if (xfrm == null) return null;

    final off = xfrm.findAllElements('a:off').firstOrNull ?? xfrm.findAllElements('off').firstOrNull;
    final ext = xfrm.findAllElements('a:ext').firstOrNull ?? xfrm.findAllElements('ext').firstOrNull;
    if (off == null || ext == null) return null;

    int x = int.tryParse(off.getAttribute('x') ?? '') ?? 0;
    int y = int.tryParse(off.getAttribute('y') ?? '') ?? 0;
    int w = int.tryParse(ext.getAttribute('cx') ?? '') ?? 0;
    int h = int.tryParse(ext.getAttribute('cy') ?? '') ?? 0;

    if (w <= 0 || h <= 0) return null;

    if (transformContext != null) {
      x = transformContext.transformX(x);
      y = transformContext.transformY(y);
      w = transformContext.transformW(w);
      h = transformContext.transformH(h);
    }

    double rot = 0.0;
    final rotAttr = xfrm.getAttribute('rot');
    if (rotAttr != null) {
      final rotInt = int.tryParse(rotAttr);
      if (rotInt != null) {
        rot = rotInt / 60000.0; // 60,000ths of a degree
      }
    }

    final normX = (x / slideWidthEmu).clamp(-0.5, 2.0);
    final normY = (y / slideHeightEmu).clamp(-0.5, 2.0);
    final normW = (w / slideWidthEmu).clamp(0.01, 2.0);
    final normH = (h / slideHeightEmu).clamp(0.01, 2.0);

    return (Rect.fromLTWH(normX, normY, normW, normH), rot);
  }

  /// Fallback rectangle for shapes or images that lack explicit `<a:xfrm>`.
  static Rect _fallbackRectForIndex(int index, {bool isImage = false}) {
    final top = 0.28 + (index * 0.14);
    if (isImage) {
      return Rect.fromLTWH(0.55, top.clamp(0.1, 0.7), 0.38, 0.25);
    }
    return Rect.fromLTWH(0.08, top.clamp(0.1, 0.85), 0.84, 0.12);
  }

  /// Extracts color from a parent element (`solidFill`, `gradFill`, etc.).
  static Color? _parseColorFromParent(XmlElement parent, Map<String, Color> themeColors) {
    final solidFill = parent.findAllElements('a:solidFill').firstOrNull ??
        parent.findAllElements('solidFill').firstOrNull;
    if (solidFill != null) {
      return _parseRawColor(solidFill, themeColors);
    }

    final gradFill = parent.findAllElements('a:gradFill').firstOrNull ??
        parent.findAllElements('gradFill').firstOrNull;
    if (gradFill != null) {
      final firstStop = gradFill.findAllElements('a:gs').firstOrNull ??
          gradFill.findAllElements('gs').firstOrNull;
      if (firstStop != null) {
        return _parseRawColor(firstStop, themeColors);
      }
    }

    return null;
  }

  /// Resolves raw color elements (`srgbClr`, `schemeClr`, `sysClr`, `prstClr`).
  static Color? _parseRawColor(XmlElement container, Map<String, Color> themeColors) {
    // 1. Exact RGB Hex
    final srgb = container.findAllElements('a:srgbClr').firstOrNull ??
        container.findAllElements('srgbClr').firstOrNull;
    if (srgb != null) {
      final val = srgb.getAttribute('val');
      if (val != null) {
        final hex = int.tryParse(val, radix: 16);
        if (hex != null) {
          return _applyModifiers(Color(0xFF000000 | hex), srgb);
        }
      }
    }

    // 2. Scheme color lookup
    final scheme = container.findAllElements('a:schemeClr').firstOrNull ??
        container.findAllElements('schemeClr').firstOrNull;
    if (scheme != null) {
      final val = scheme.getAttribute('val');
      if (val != null) {
        Color? base = themeColors[val];
        if (base == null) {
          if (val == 'tx1') base = themeColors['dk1'];
          if (val == 'tx2') base = themeColors['dk2'];
          if (val == 'bg1') base = themeColors['lt1'];
          if (val == 'bg2') base = themeColors['lt2'];
        }
        if (base != null) {
          return _applyModifiers(base, scheme);
        }
      }
    }

    // 3. System color
    final sys = container.findAllElements('a:sysClr').firstOrNull ??
        container.findAllElements('sysClr').firstOrNull;
    if (sys != null) {
      final lastClr = sys.getAttribute('lastClr');
      if (lastClr != null) {
        final hex = int.tryParse(lastClr, radix: 16);
        if (hex != null) {
          return Color(0xFF000000 | hex);
        }
      }
    }

    // 4. Preset color
    final prst = container.findAllElements('a:prstClr').firstOrNull ??
        container.findAllElements('prstClr').firstOrNull;
    if (prst != null) {
      final val = prst.getAttribute('val')?.toLowerCase();
      return _presetColors[val];
    }

    return null;
  }

  /// Applies alpha, luminance modifiers, and tints.
  static Color _applyModifiers(Color base, XmlElement colorElem) {
    double alpha = base.a;
    final alphaElem = colorElem.findAllElements('a:alpha').firstOrNull ??
        colorElem.findAllElements('alpha').firstOrNull;
    if (alphaElem != null) {
      final val = int.tryParse(alphaElem.getAttribute('val') ?? '');
      if (val != null) alpha = (val / 100000.0).clamp(0.0, 1.0);
    }

    final lumMod = int.tryParse(colorElem.findAllElements('a:lumMod').firstOrNull?.getAttribute('val') ??
        colorElem.findAllElements('lumMod').firstOrNull?.getAttribute('val') ?? '');
    final lumOff = int.tryParse(colorElem.findAllElements('a:lumOff').firstOrNull?.getAttribute('val') ??
        colorElem.findAllElements('lumOff').firstOrNull?.getAttribute('val') ?? '');

    if (lumMod != null || lumOff != null) {
      final hsl = HSLColor.fromColor(base);
      double l = hsl.lightness;
      if (lumMod != null) l = l * (lumMod / 100000.0);
      if (lumOff != null) l = l + (lumOff / 100000.0);
      return hsl.withLightness(l.clamp(0.0, 1.0)).toColor().withValues(alpha: alpha);
    }

    return base.withValues(alpha: alpha);
  }

  /// Extracts slide-to-slide transition from `<p:transition>`.
  static SlideTransitionType _parseTransition(XmlDocument slideDoc) {
    final transitions = slideDoc.findAllElements('p:transition').isNotEmpty
        ? slideDoc.findAllElements('p:transition')
        : slideDoc.findAllElements('transition');
    if (transitions.isEmpty) return SlideTransitionType.none;

    final transitionElem = transitions.first;
    bool hasTag(String localName) =>
        transitionElem.findAllElements('p:$localName').isNotEmpty ||
        transitionElem.findAllElements(localName).isNotEmpty;

    final push = transitionElem.findAllElements('p:push').firstOrNull ??
        transitionElem.findAllElements('push').firstOrNull;
    if (push != null) {
      final dir = push.getAttribute('dir');
      if (dir == 'l') return SlideTransitionType.pushLeft;
      if (dir == 'r') return SlideTransitionType.pushRight;
      if (dir == 'u') return SlideTransitionType.pushUp;
      if (dir == 'd') return SlideTransitionType.pushDown;
      return SlideTransitionType.pushLeft;
    }

    if (hasTag('cover')) return SlideTransitionType.cover;
    if (hasTag('pull')) return SlideTransitionType.uncover;
    if (hasTag('split')) return SlideTransitionType.split;
    if (hasTag('cut')) return SlideTransitionType.cut;
    if (hasTag('wipe') || hasTag('blinds')) return SlideTransitionType.wipe;
    if (hasTag('zoom')) return SlideTransitionType.zoom;
    if (hasTag('fade') || hasTag('dissolve') || hasTag('morph')) {
      return SlideTransitionType.fade;
    }
    return SlideTransitionType.fade;
  }

  /// Parses transition duration in milliseconds.
  static int _parseTransitionDuration(XmlDocument slideDoc) {
    final transitionElem = slideDoc.findAllElements('p:transition').firstOrNull ??
        slideDoc.findAllElements('transition').firstOrNull;
    if (transitionElem == null) return 400;
    final dur = transitionElem.getAttribute('dur');
    if (dur != null) {
      final durInt = int.tryParse(dur);
      if (durInt != null && durInt > 0) return durInt.clamp(150, 2000);
    }
    final spd = transitionElem.getAttribute('spd');
    if (spd == 'slow') return 600;
    if (spd == 'fast') return 250;
    return 400;
  }

  /// Extracts OOXML `<p:timing>` entrance and emphasis animations.
  static List<SlideAnimationStep> _parseTiming(XmlDocument slideDoc) {
    final timing = slideDoc.findAllElements('p:timing').firstOrNull ??
        slideDoc.findAllElements('timing').firstOrNull;
    if (timing == null) return const [];

    // Prefer mainSeq if present so interactive triggers don't pollute tap timeline.
    XmlElement root = timing;
    for (final cTn in timing.findAllElements('p:cTn')) {
      if (cTn.getAttribute('nodeType') == 'mainSeq') {
        root = cTn;
        break;
      }
    }
    if (identical(root, timing)) {
      for (final cTn in timing.findAllElements('cTn')) {
        if (cTn.getAttribute('nodeType') == 'mainSeq') {
          root = cTn;
          break;
        }
      }
    }

    final steps = <SlideAnimationStep>[];
    final seenPairs = <String>{};
    int clickGroup = 0;
    bool currentGroupHasSteps = false;

    void walk(
      XmlElement node,
      SlideAnimationTrigger inheritedTrigger,
      int inheritedDelay,
    ) {
      for (final child in node.children.whereType<XmlElement>()) {
        final local = child.name.local;
        if (local == 'cTn') {
          final nodeType = child.getAttribute('nodeType');
          SlideAnimationTrigger trigger = inheritedTrigger;

          if (nodeType == 'clickEffect') {
            if (clickGroup == 0 || currentGroupHasSteps) {
              clickGroup++;
              currentGroupHasSteps = false;
            }
            trigger = SlideAnimationTrigger.onClick;
          } else if (nodeType == 'withEffect') {
            trigger = SlideAnimationTrigger.withPrevious;
          } else if (nodeType == 'afterEffect') {
            trigger = SlideAnimationTrigger.afterPrevious;
          }

          final delayFromCond = _extractStartDelayMs(child) ?? inheritedDelay;
          final presetClass = child.getAttribute('presetClass');

          if (presetClass == 'exit') {
            // Skip exit animations so elements aren't hidden prior to reveal.
            continue;
          }

          if (presetClass == 'entr' || presetClass == 'emph') {
            final isEmphasis = presetClass == 'emph';
            final presetId = child.getAttribute('presetID');
            final subtype = child.getAttribute('presetSubtype');

            final effect = isEmphasis
                ? SlideAnimationEffect.emphasis
                : _mapPresetIdToEffect(presetId);
            final direction = _mapSubtypeToDirection(subtype);
            final durMs = _extractAnimationDurationMs(child, effect);
            final effectiveDelay =
                trigger == SlideAnimationTrigger.afterPrevious &&
                        delayFromCond == 0
                    ? 180
                    : delayFromCond;

            final targetIds = <String>{};
            for (final spTgt in child.findAllElements('p:spTgt')) {
              final spid = spTgt.getAttribute('spid');
              if (spid != null && spid.isNotEmpty) targetIds.add(spid);
            }
            for (final spTgt in child.findAllElements('spTgt')) {
              final spid = spTgt.getAttribute('spid');
              if (spid != null && spid.isNotEmpty) targetIds.add(spid);
            }

            for (final spid in targetIds) {
              final dedupKey = '$spid#$clickGroup';
              if (!seenPairs.add(dedupKey)) continue;
              steps.add(
                SlideAnimationStep(
                  shapeId: spid,
                  effect: effect,
                  direction: direction,
                  trigger: trigger,
                  durationMs: durMs,
                  delayMs: effectiveDelay,
                  clickGroup: clickGroup,
                  isEmphasis: isEmphasis,
                ),
              );
              currentGroupHasSteps = true;
            }
            continue;
          }

          walk(child, trigger, delayFromCond);
        } else {
          walk(child, inheritedTrigger, inheritedDelay);
        }
      }
    }

    walk(root, SlideAnimationTrigger.withPrevious, 0);
    return steps;
  }

  static int? _extractStartDelayMs(XmlElement cTn) {
    final stCondLst = cTn.findElements('p:stCondLst').firstOrNull ??
        cTn.findElements('stCondLst').firstOrNull;
    if (stCondLst == null) return null;
    for (final cond in stCondLst.children.whereType<XmlElement>()) {
      if (cond.name.local != 'cond') continue;
      final delayAttr = cond.getAttribute('delay');
      if (delayAttr != null && delayAttr != 'indefinite') {
        final ms = int.tryParse(delayAttr);
        if (ms != null && ms >= 0) return ms.clamp(0, 3000);
      }
    }
    return null;
  }

  static int _extractAnimationDurationMs(
    XmlElement cTn,
    SlideAnimationEffect effect,
  ) {
    final directDur = int.tryParse(cTn.getAttribute('dur') ?? '');
    if (directDur != null && directDur > 1) {
      return directDur.clamp(120, 2000);
    }
    for (final childCtn in cTn.findAllElements('p:cTn')) {
      final d = int.tryParse(childCtn.getAttribute('dur') ?? '');
      if (d != null && d > 1) return d.clamp(120, 2000);
    }
    for (final childCtn in cTn.findAllElements('cTn')) {
      final d = int.tryParse(childCtn.getAttribute('dur') ?? '');
      if (d != null && d > 1) return d.clamp(120, 2000);
    }
    return effect == SlideAnimationEffect.appear ? 80 : 420;
  }

  static SlideAnimationEffect _mapPresetIdToEffect(String? presetId) {
    return switch (presetId) {
      '1' => SlideAnimationEffect.appear,
      '2' => SlideAnimationEffect.flyIn,
      '10' => SlideAnimationEffect.fade,
      '16' => SlideAnimationEffect.split,
      '22' => SlideAnimationEffect.wipe,
      '23' || '37' || '53' => SlideAnimationEffect.zoom,
      '42' => SlideAnimationEffect.floatIn,
      _ => SlideAnimationEffect.fade,
    };
  }

  static SlideAnimationDirection _mapSubtypeToDirection(String? subtype) {
    return switch (subtype) {
      '4' => SlideAnimationDirection.fromBottom,
      '8' => SlideAnimationDirection.fromLeft,
      '2' => SlideAnimationDirection.fromRight,
      '1' => SlideAnimationDirection.fromTop,
      _ => SlideAnimationDirection.center,
    };
  }

  static const Map<String, Color> _presetColors = {
    'white': Color(0xFFFFFFFF),
    'black': Color(0xFF000000),
    'red': Color(0xFFFF0000),
    'green': Color(0xFF008000),
    'blue': Color(0xFF0000FF),
    'yellow': Color(0xFFFFFF00),
    'gray': Color(0xFF808080),
    'grey': Color(0xFF808080),
    'orange': Color(0xFFFFA500),
    'purple': Color(0xFF800080),
  };
}
