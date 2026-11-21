import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../services/encoding_utils.dart';
import '../services/gallery_saver.dart';
import '../services/gemini_share_service.dart';
import '../services/reading_prefs.dart';
import '../services/word_parser.dart';

class WordViewerScreen extends StatefulWidget {
  const WordViewerScreen({
    super.key,
    required this.filePath,
    required this.title,
  });

  final String filePath;
  final String title;

  @override
  State<WordViewerScreen> createState() => _WordViewerScreenState();
}

class _WordViewerScreenState extends State<WordViewerScreen>
    with SingleTickerProviderStateMixin {
  static const double _ptToPx = 1.28;

  final GlobalKey _documentViewKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  final TransformationController _zoomController = TransformationController();
  final ValueNotifier<bool> _isZoomedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _panEnabledNotifier = ValueNotifier<bool>(false);
  late final ScrollPhysics _zoomLockPhysics =
      _ZoomLockScrollPhysics(_isZoomedNotifier);
  late final AnimationController _zoomAnimController;
  Animation<Matrix4>? _zoomAnimation;
  Offset _doubleTapPosition = Offset.zero;
  int _activePointers = 0;

  final Map<String, TapGestureRecognizer> _linkRecognizers = {};
  WordDocument? _doc;
  List<List<WordBlock>> _cachedPages = const [];
  List<List<WordFloatingElement>> _cachedBehindFloating = const [];
  List<List<WordFloatingElement>> _cachedFrontFloating = const [];
  bool _isLoading = true;
  bool _isSavingToGallery = false;
  String? _error;
  double _fontScale = 1.0;
  bool _isSearchOpen = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  bool get _hasDocumentContent {
    final doc = _doc;
    if (doc == null) return false;
    return doc.blocks.isNotEmpty ||
        doc.floatingElements.isNotEmpty ||
        doc.headerBlocks.isNotEmpty ||
        doc.footerBlocks.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _zoomAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        final anim = _zoomAnimation;
        if (anim != null) {
          _zoomController.value = anim.value;
        }
      });
    _zoomController.addListener(_onZoomChanged);
    _loadFile();
  }

  void _updatePanEnabled() {
    final next = _isZoomedNotifier.value || _activePointers >= 2;
    if (_panEnabledNotifier.value != next) {
      _panEnabledNotifier.value = next;
    }
  }

  void _onZoomChanged() {
    final scale = _zoomController.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.02;
    if (_isZoomedNotifier.value != zoomed) {
      _isZoomedNotifier.value = zoomed;
      _updatePanEnabled();
    }
  }

  void _handleDoubleTapZoom() {
    final begin = _zoomController.value.clone();
    final Matrix4 end;
    if (_zoomController.value.getMaxScaleOnAxis() > 1.04) {
      end = Matrix4.identity();
    } else {
      const double zoom = 2.2;
      final dx = -_doubleTapPosition.dx * (zoom - 1);
      final dy = -_doubleTapPosition.dy * (zoom - 1);
      end = Matrix4.identity()
        ..translateByDouble(dx, dy, 0.0, 1.0)
        ..scaleByDouble(zoom, zoom, 1.0, 1.0);
    }
    _zoomAnimation = Matrix4Tween(begin: begin, end: end).animate(
      CurvedAnimation(parent: _zoomAnimController, curve: Curves.easeOutCubic),
    );
    _zoomAnimController.forward(from: 0);
  }

  @override
  void dispose() {
    for (final rec in _linkRecognizers.values) {
      rec.dispose();
    }
    _linkRecognizers.clear();
    _zoomAnimController.dispose();
    _zoomController.removeListener(_onZoomChanged);
    _zoomController.dispose();
    _isZoomedNotifier.dispose();
    _panEnabledNotifier.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  TapGestureRecognizer _recognizerForUrl(String url) {
    return _linkRecognizers.putIfAbsent(url, () {
      return TapGestureRecognizer()..onTap = () => _openLink(url);
    });
  }

  Future<void> _openLink(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open link: $url')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid link URL: $url')),
        );
      }
    }
  }

  Future<void> _loadFile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final file = File(widget.filePath);
      final bytes = await file.readAsBytes();
      final doc = await WordParser.parse(bytes);
      final hasContent = doc.blocks.isNotEmpty ||
          doc.floatingElements.isNotEmpty ||
          doc.headerBlocks.isNotEmpty ||
          doc.footerBlocks.isNotEmpty;
      final List<List<WordBlock>> cachedPages;
      final List<List<WordFloatingElement>> cachedBehind;
      final List<List<WordFloatingElement>> cachedFront;
      if (hasContent) {
        cachedPages = _splitIntoPages(doc);
        cachedBehind = <List<WordFloatingElement>>[];
        cachedFront = <List<WordFloatingElement>>[];
        for (int pIdx = 0; pIdx < cachedPages.length; pIdx++) {
          final pageFloating = doc.floatingElements
              .where((e) => e.pageIndex == pIdx || e.pageIndex == -1)
              .toList()
            ..sort((a, b) => a.zOrder.compareTo(b.zOrder));
          cachedBehind.add(pageFloating.where((e) => e.behindDoc).toList());
          cachedFront.add(pageFloating.where((e) => !e.behindDoc).toList());
        }
      } else {
        cachedPages = const [];
        cachedBehind = const [];
        cachedFront = const [];
      }
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _cachedPages = cachedPages;
        _cachedBehindFloating = cachedBehind;
        _cachedFrontFloating = cachedFront;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _doc = null;
        _cachedPages = const [];
        _cachedBehindFloating = const [];
        _cachedFrontFloating = const [];
        _error = 'Could not load Word document: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _shareFile() async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(widget.filePath)],
        title: widget.title,
      ),
    );
  }

  Future<void> _saveViewToGallery() async {
    if (!_hasDocumentContent || _isSavingToGallery) return;
    final l10n = context.l10n;
    setState(() => _isSavingToGallery = true);
    final cleanTitle = EncodingUtils.cleanDisplayName(widget.title);
    try {
      await GallerySaver.saveBoundaryToGallery(
        context: context,
        boundaryKey: _documentViewKey,
        baseName: 'Pagelit_${cleanTitle}_doc',
        successMessage: l10n.documentViewSaved,
      );
    } finally {
      if (mounted) setState(() => _isSavingToGallery = false);
    }
  }

  Future<void> _askGemini() async {
    if (!_hasDocumentContent) return;
    final cleanTitle = EncodingUtils.cleanDisplayName(widget.title);
    await GeminiShareService.shareBoundaryToGemini(
      context: context,
      boundaryKey: _documentViewKey,
      pageTitle: cleanTitle,
      customPrompt:
          'Please summarize, explain the main points, and answer questions about this document excerpt.',
    );
  }

  void _openOutlineSheet() {
    if (_doc == null) return;
    final headings = <({int index, String text, int level})>[];

    void scanBlocksForHeadings(List<WordBlock> blocks, int fallbackIndex) {
      for (int i = 0; i < blocks.length; i++) {
        final block = blocks[i];
        if (block is WordParagraph &&
            block.headingLevel != null &&
            block.fullText.trim().isNotEmpty) {
          headings.add(
            (
              index: fallbackIndex >= 0 ? fallbackIndex : i,
              text: block.fullText.trim(),
              level: block.headingLevel!,
            ),
          );
        } else if (block is WordTextBoxBlock) {
          scanBlocksForHeadings(
            block.blocks,
            fallbackIndex >= 0 ? fallbackIndex : i,
          );
        }
      }
    }

    scanBlocksForHeadings(_doc!.blocks, -1);
    for (final fe in _doc!.floatingElements) {
      scanBlocksForHeadings(fe.textBlocks, 0);
    }

    if (headings.isEmpty) {
      for (int i = 0; i < _doc!.blocks.length; i++) {
        final block = _doc!.blocks[i];
        if (block is! WordParagraph || block.isBullet) continue;
        final text = block.fullText.trim();
        if (text.length < 2 || text.length > 90) continue;
        if (text.endsWith(',') || text.endsWith(';')) continue;
        final nonEmptySpans =
            block.spans.where((s) => s.text.trim().isNotEmpty).toList();
        if (nonEmptySpans.isEmpty) continue;
        final allBold = nonEmptySpans.every((s) => s.bold);
        final hasLargeFont =
            nonEmptySpans.any((s) => (s.fontSize ?? 0) >= 15.5);
        if (allBold || hasLargeFont) {
          headings.add((index: i, text: text, level: 1));
        }
      }
    }

    if (headings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.noTableOfContents)),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                context.l10n.tableOfContents,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: headings.length,
                itemBuilder: (context, idx) {
                  final h = headings[idx];
                  final indent = (h.level - 1) * 16.0;
                  return ListTile(
                    contentPadding: EdgeInsetsDirectional.only(
                      start: 20 + indent,
                      end: 20,
                    ),
                    leading: Icon(
                      h.level == 1
                          ? Icons.bookmark_rounded
                          : Icons.subdirectory_arrow_right_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(
                      h.text,
                      style: TextStyle(
                        fontWeight:
                            h.level == 1 ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      if (!_scrollController.hasClients) return;
                      final maxExtent =
                          _scrollController.position.maxScrollExtent;
                      final fraction =
                          h.index / math.max(1, _doc!.blocks.length - 1);
                      final target =
                          (fraction * maxExtent).clamp(0.0, maxExtent);
                      _scrollController.animateTo(
                        target,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _viewImage(Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
            IconButton.filled(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  static Color? _parseColor(String? hexStr) {
    if (hexStr == null ||
        hexStr.isEmpty ||
        hexStr.toLowerCase() == 'auto' ||
        hexStr.toLowerCase() == 'none') {
      return null;
    }
    final clean = hexStr.replaceAll('#', '');
    if (clean.length == 6) {
      final val = int.tryParse(clean, radix: 16);
      if (val != null) return Color(0xFF000000 | val);
    } else if (clean.length == 8) {
      final val = int.tryParse(clean, radix: 16);
      if (val != null) return Color(val);
    }
    return null;
  }

  static Color _adaptColorForComfort(Color c, ComfortMode comfort) {
    if (comfort != ComfortMode.dim && comfort != ComfortMode.inverted) {
      return c;
    }
    if (c.computeLuminance() < 0.28) {
      final hsl = HSLColor.fromColor(c);
      return hsl.withLightness(math.max(hsl.lightness, 0.72)).toColor();
    }
    return c;
  }

  static Color _shadingColorForComfort(Color c, ComfortMode comfort) {
    if (comfort == ComfortMode.dim || comfort == ComfortMode.inverted) {
      return c.withValues(alpha: 0.25);
    }
    return c;
  }

  Color? _getHighlightColor(String? nameOrHex) {
    if (nameOrHex == null ||
        nameOrHex.isEmpty ||
        nameOrHex.toLowerCase() == 'none') {
      return null;
    }
    final lower = nameOrHex.toLowerCase();
    switch (lower) {
      case 'yellow':
        return const Color(0xFFFFF275).withValues(alpha: 0.85);
      case 'green':
        return const Color(0xFF8CE99A).withValues(alpha: 0.85);
      case 'cyan':
        return const Color(0xFF66D9E8).withValues(alpha: 0.85);
      case 'magenta':
        return const Color(0xFFF783AC).withValues(alpha: 0.85);
      case 'blue':
        return const Color(0xFF74C0FC).withValues(alpha: 0.85);
      case 'red':
        return const Color(0xFFFF8787).withValues(alpha: 0.85);
      case 'darkblue':
        return const Color(0xFF1971C2).withValues(alpha: 0.35);
      case 'darkcyan':
        return const Color(0xFF0C8599).withValues(alpha: 0.35);
      case 'darkgreen':
        return const Color(0xFF2F9E44).withValues(alpha: 0.35);
      case 'darkmagenta':
        return const Color(0xFFA61E4D).withValues(alpha: 0.35);
      case 'darkred':
        return const Color(0xFFC92A2A).withValues(alpha: 0.35);
      case 'darkyellow':
        return const Color(0xFFF59F00).withValues(alpha: 0.45);
      case 'darkgray':
        return const Color(0xFF495057).withValues(alpha: 0.35);
      case 'lightgray':
        return const Color(0xFFCED4DA).withValues(alpha: 0.8);
      case 'black':
        return Colors.black26;
      default:
        final clean = lower.replaceAll('#', '');
        final hex = int.tryParse(clean, radix: 16);
        if (hex != null) return Color(0xFF000000 | hex);
        return const Color(0xFFFFF275);
    }
  }

  TextDecoration _resolveDecoration(bool underline, bool strikethrough) {
    if (underline && strikethrough) {
      return TextDecoration.combine(
        [TextDecoration.underline, TextDecoration.lineThrough],
      );
    }
    if (underline) return TextDecoration.underline;
    if (strikethrough) return TextDecoration.lineThrough;
    return TextDecoration.none;
  }

  ({String? fontFamily, List<String> fallback}) _resolveFontSpec(
    String? wordFont,
  ) {
    final candidate = (wordFont ?? _doc?.defaultFontFamily)?.trim();
    final lower = candidate?.toLowerCase() ?? '';
    const serifTokens = [
      'times',
      'georgia',
      'cambria',
      'garamond',
      'palatino',
      'century',
      'book antiqua',
      'baskerville',
      'caslon',
      'constantia',
      'didot',
      'bodoni',
      'charter',
      'rockwell',
    ];
    const monoTokens = [
      'consolas',
      'courier',
      'lucida console',
      'menlo',
      'monaco',
      'dejavu sans mono',
      'fira code',
      'jetbrains mono',
      'source code',
    ];

    if (serifTokens.any((token) => lower.contains(token))) {
      return (
        fontFamily: candidate,
        fallback: const ['Georgia', 'Times New Roman', 'Noto Serif', 'serif'],
      );
    }
    if (monoTokens.any((token) => lower.contains(token))) {
      return (
        fontFamily: candidate,
        fallback: const ['Consolas', 'Courier New', 'Roboto Mono', 'monospace'],
      );
    }
    return (
      fontFamily: (candidate != null && candidate.isNotEmpty)
          ? candidate
          : 'sans-serif',
      fallback: const [
        'Calibri',
        'Segoe UI',
        'Arial',
        'Roboto',
        'Noto Sans Arabic',
        'sans-serif',
      ],
    );
  }

  BorderSide _borderSideFromWord(
    WordBorder? border,
    ComfortMode comfort, {
    BorderSide fallback = BorderSide.none,
  }) {
    if (border == null) return fallback;
    if (!border.isVisible) return BorderSide.none;
    final raw = _parseColor(border.colorHex) ?? const Color(0xFF000000);
    final adapted = _adaptColorForComfort(raw, comfort);
    return BorderSide(
      color: adapted,
      width: (border.widthPt * _ptToPx).clamp(0.5, 6.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: LayoutBuilder(
          builder: (context, constraints) {
            final cleanTitle = EncodingUtils.cleanDisplayName(widget.title);
            if (constraints.maxWidth < 80) {
              return Text(
                cleanTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              );
            }
            return Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade700,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'DOCX',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    cleanTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          IconButton(
            tooltip: l10n.tableOfContents,
            icon: const Icon(Icons.format_list_bulleted_rounded),
            onPressed: _openOutlineSheet,
          ),
          IconButton(
            tooltip: l10n.search,
            icon: Icon(
              _isSearchOpen ? Icons.search_off_rounded : Icons.search_rounded,
            ),
            onPressed: () => setState(() {
              _isSearchOpen = !_isSearchOpen;
              if (!_isSearchOpen) {
                _searchQuery = '';
                _searchController.clear();
              }
            }),
          ),
          IconButton(
            tooltip: l10n.askGemini,
            icon: const Icon(Icons.auto_awesome_rounded),
            color: Theme.of(context).colorScheme.primary,
            onPressed: _hasDocumentContent ? _askGemini : null,
          ),
          PopupMenuButton<String>(
            tooltip: l10n.more,
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (val) {
              switch (val) {
                case 'text_minus':
                  setState(() {
                    if (_fontScale > 0.8) _fontScale -= 0.1;
                  });
                  break;
                case 'text_plus':
                  setState(() {
                    if (_fontScale < 1.8) _fontScale += 0.1;
                  });
                  break;
                case 'gallery':
                  if (!_isSavingToGallery && _hasDocumentContent) {
                    _saveViewToGallery();
                  }
                  break;
                case 'share':
                  _shareFile();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'text_minus',
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.text_decrease_rounded),
                  title: Text(l10n.smallerText),
                ),
              ),
              PopupMenuItem(
                value: 'text_plus',
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.text_increase_rounded),
                  title: Text(l10n.largerText),
                ),
              ),
              PopupMenuItem(
                value: 'gallery',
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.add_photo_alternate_rounded),
                  title: Text(l10n.saveWordViewToGallery),
                ),
              ),
              PopupMenuItem(
                value: 'share',
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.share_rounded),
                  title: Text(l10n.share),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isSearchOpen)
            Container(
              color: scheme.surface,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.searchWordHint,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () => setState(() {
                            _searchQuery = '';
                            _searchController.clear();
                          }),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: (val) =>
                    setState(() => _searchQuery = val.trim().toLowerCase()),
              ),
            ),
          Expanded(child: _buildBody(l10n)),
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: Colors.red,
              ),
              const SizedBox(height: 14),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _loadFile, child: Text(l10n.retry)),
            ],
          ),
        ),
      );
    }
    if (!_hasDocumentContent) {
      return Center(child: Text(l10n.wordDocumentEmpty));
    }

    final scheme = Theme.of(context).colorScheme;
    final page = _doc!.pageSettings;
    final pageWidthPx = (page.widthPt * _ptToPx).clamp(600.0, 900.0);

    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final imageCacheWidth = (dpr * pageWidthPx).round().clamp(256, 1800);

    final usePagedCanvas = _doc!.floatingElements.isNotEmpty ||
        page.pageBorders != null ||
        _doc!.headerBlocks.isNotEmpty ||
        _doc!.footerBlocks.isNotEmpty;

    return ValueListenableBuilder<ComfortMode>(
      valueListenable: ReadingPrefs.comfortMode,
      builder: (context, comfort, _) {
        final docPaperBg = _parseColor(page.backgroundColorHex) ?? Colors.white;
        late final Color bgColor;
        late final Color textColor;
        late final Color canvasColor;

        switch (comfort) {
          case ComfortMode.normal:
            bgColor = docPaperBg;
            textColor = bgColor.computeLuminance() < 0.35
                ? Colors.white
                : const Color(0xFF1A1A1A);
            canvasColor = scheme.surfaceContainerLow;
            break;
          case ComfortMode.sepia:
            bgColor = const Color(0xFFFBF0D9);
            textColor = const Color(0xFF3B2E1E);
            canvasColor = bgColor;
            break;
          case ComfortMode.dim:
            bgColor = const Color(0xFF1E1E1E);
            textColor = const Color(0xFFD4D4D4);
            canvasColor = bgColor;
            break;
          case ComfortMode.inverted:
            bgColor = const Color(0xFF121212);
            textColor = const Color(0xFFF0F0F0);
            canvasColor = bgColor;
            break;
        }

        return RepaintBoundary(
          key: _documentViewKey,
          child: Container(
            color: canvasColor,
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (usePagedCanvas) {
                  return _buildPagedCanvas(
                    constraints: constraints,
                    page: page,
                    bgColor: bgColor,
                    textColor: textColor,
                    scheme: scheme,
                    comfort: comfort,
                    imageCacheWidth: imageCacheWidth,
                  );
                }

                final availableW =
                    (constraints.maxWidth - 20).clamp(240.0, pageWidthPx);
                final widthRatio = (availableW / pageWidthPx).clamp(0.35, 1.0);
                final padLeft =
                    (page.marginLeftPt * _ptToPx * widthRatio).clamp(16.0, 96.0);
                final padRight =
                    (page.marginRightPt * _ptToPx * widthRatio).clamp(16.0, 96.0);
                final padTop =
                    (page.marginTopPt * _ptToPx * widthRatio).clamp(20.0, 96.0);
                final padBottom =
                    (page.marginBottomPt * _ptToPx * widthRatio).clamp(28.0, 110.0);
                final contentWidth =
                    math.max(120.0, availableW - padLeft - padRight);

                return _wrapWithSmoothZoom(
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: pageWidthPx),
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: 0.45),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: Builder(
                          builder: (context) {
                            return ListView.builder(
                              controller: _scrollController,
                              physics: _zoomLockPhysics,
                              cacheExtent: 600,
                              padding: EdgeInsets.fromLTRB(
                                padLeft,
                                padTop,
                                padRight,
                                padBottom,
                              ),
                              itemCount: _doc!.blocks.length,
                              itemBuilder: (context, index) {
                                final block = _doc!.blocks[index];
                                return _buildBlock(
                                  block,
                                  textColor,
                                  scheme,
                                  comfort,
                                  imageCacheWidth,
                                  contentWidth,
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  List<List<WordBlock>> _splitIntoPages(WordDocument doc) {
    final pages = <List<WordBlock>>[];
    var current = <WordBlock>[];

    for (final block in doc.blocks) {
      if (block is WordPageBreakBlock) {
        pages.add(current);
        current = <WordBlock>[];
      } else if (block is WordParagraph && block.pageBreakBefore) {
        if (current.isNotEmpty) {
          pages.add(current);
          current = <WordBlock>[];
        }
        current.add(block);
      } else {
        current.add(block);
      }
    }
    if (current.isNotEmpty || pages.isEmpty) {
      pages.add(current);
    }

    var maxPageIdx = pages.length - 1;
    for (final fe in doc.floatingElements) {
      if (fe.pageIndex > maxPageIdx) {
        maxPageIdx = fe.pageIndex;
      }
    }
    while (pages.length <= maxPageIdx) {
      pages.add(<WordBlock>[]);
    }
    return pages;
  }

  Widget _buildPagedCanvas({
    required BoxConstraints constraints,
    required WordPageSettings page,
    required Color bgColor,
    required Color textColor,
    required ColorScheme scheme,
    required ComfortMode comfort,
    required int imageCacheWidth,
  }) {
    final pageRenderWidth = (constraints.maxWidth - 20).clamp(240.0, 900.0);
    final pageScale = pageRenderWidth / math.max(1.0, page.widthPt);
    final pageMinHeight = page.heightPt * pageScale;
    final ptScale = pageScale * _fontScale;

    final pages =
        _cachedPages.isNotEmpty ? _cachedPages : _splitIntoPages(_doc!);
    final marginLeft = page.marginLeftPt * pageScale;
    final marginRight = page.marginRightPt * pageScale;
    final marginTop = page.marginTopPt * pageScale;
    final marginBottom = page.marginBottomPt * pageScale;
    final contentWidth =
        math.max(40.0, pageRenderWidth - marginLeft - marginRight);

    final hasPageBorders =
        page.pageBorders != null && page.pageBorders!.hasAny;

    return _wrapWithSmoothZoom(
      Builder(
        builder: (context) {
          return ListView.builder(
            controller: _scrollController,
            physics: _zoomLockPhysics,
            padding: const EdgeInsets.symmetric(vertical: 8),
            cacheExtent: 900,
            itemCount: pages.length,
            itemBuilder: (context, pIdx) {
              final pageFlowBlocks = pages[pIdx];
              final List<WordFloatingElement> behindElements;
              final List<WordFloatingElement> frontElements;
              if (pIdx < _cachedBehindFloating.length &&
                  pIdx < _cachedFrontFloating.length) {
                behindElements = _cachedBehindFloating[pIdx];
                frontElements = _cachedFrontFloating[pIdx];
              } else {
                final pageFloating = _doc!.floatingElements
                    .where((e) => e.pageIndex == pIdx || e.pageIndex == -1)
                    .toList()
                  ..sort((a, b) => a.zOrder.compareTo(b.zOrder));
                behindElements =
                    pageFloating.where((e) => e.behindDoc).toList();
                frontElements =
                    pageFloating.where((e) => !e.behindDoc).toList();
              }

              return Center(
                child: Container(
                  width: pageRenderWidth,
                  margin:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.45),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      for (final fe in behindElements)
                        _buildFloatingElement(
                          fe,
                          pageScale: pageScale,
                          ptScale: ptScale,
                          textColor: textColor,
                          scheme: scheme,
                          comfort: comfort,
                          imageCacheWidth: imageCacheWidth,
                        ),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: pageRenderWidth,
                          minHeight: pageMinHeight,
                        ),
                        child: Container(
                          decoration: hasPageBorders
                              ? BoxDecoration(
                                  border: Border(
                                    top: _borderSideFromWord(
                                        page.pageBorders?.top, comfort),
                                    bottom: _borderSideFromWord(
                                        page.pageBorders?.bottom, comfort),
                                    left: _borderSideFromWord(
                                        page.pageBorders?.left, comfort),
                                    right: _borderSideFromWord(
                                        page.pageBorders?.right, comfort),
                                  ),
                                )
                              : null,
                          padding: EdgeInsets.fromLTRB(
                            marginLeft,
                            marginTop,
                            marginRight,
                            marginBottom,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_doc!.headerBlocks.isNotEmpty)
                                Padding(
                                  padding:
                                      EdgeInsets.only(bottom: 8 * pageScale),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (final hb in _doc!.headerBlocks)
                                        _buildBlock(
                                          hb,
                                          textColor,
                                          scheme,
                                          comfort,
                                          imageCacheWidth,
                                          contentWidth,
                                          inTableCell: true,
                                          ptScaleOverride: ptScale,
                                        ),
                                    ],
                                  ),
                                ),
                              for (final block in pageFlowBlocks)
                                _buildBlock(
                                  block,
                                  textColor,
                                  scheme,
                                  comfort,
                                  imageCacheWidth,
                                  contentWidth,
                                  ptScaleOverride: ptScale,
                                ),
                              if (_doc!.footerBlocks.isNotEmpty)
                                Padding(
                                  padding: EdgeInsets.only(top: 10 * pageScale),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (final fb in _doc!.footerBlocks)
                                        _buildBlock(
                                          fb,
                                          textColor,
                                          scheme,
                                          comfort,
                                          imageCacheWidth,
                                          contentWidth,
                                          inTableCell: true,
                                          ptScaleOverride: ptScale,
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      for (final fe in frontElements)
                        _buildFloatingElement(
                          fe,
                          pageScale: pageScale,
                          ptScale: ptScale,
                          textColor: textColor,
                          scheme: scheme,
                          comfort: comfort,
                          imageCacheWidth: imageCacheWidth,
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _wrapWithSmoothZoom(Widget scrollableChild) {
    return Listener(
      onPointerDown: (_) {
        _activePointers++;
        _updatePanEnabled();
      },
      onPointerUp: (_) {
        if (_activePointers > 0) _activePointers--;
        _updatePanEnabled();
      },
      onPointerCancel: (_) {
        if (_activePointers > 0) _activePointers--;
        _updatePanEnabled();
      },
      child: GestureDetector(
        onDoubleTapDown: (details) => _doubleTapPosition = details.localPosition,
        onDoubleTap: _handleDoubleTapZoom,
        child: ValueListenableBuilder<bool>(
          valueListenable: _panEnabledNotifier,
          child: scrollableChild,
          builder: (context, panEnabled, child) {
            return InteractiveViewer(
              transformationController: _zoomController,
              panEnabled: panEnabled,
              minScale: 1.0,
              maxScale: 4.0,
              onInteractionStart: (_) {
                if (_zoomAnimController.isAnimating) {
                  _zoomAnimController.stop();
                }
              },
              child: RepaintBoundary(child: child!),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFloatingElement(
    WordFloatingElement elem, {
    required double pageScale,
    required double ptScale,
    required Color textColor,
    required ColorScheme scheme,
    required ComfortMode comfort,
    required int imageCacheWidth,
  }) {
    final wPx = math.max(1.0, elem.widthPt * pageScale);
    final hPx = math.max(1.0, elem.heightPt * pageScale);
    final rawFill = _parseColor(elem.fillColorHex);
    final fillColor =
        rawFill != null ? _shadingColorForComfort(rawFill, comfort) : null;
    final rawStroke = _parseColor(elem.strokeColorHex);
    final strokeColor =
        rawStroke != null ? _adaptColorForComfort(rawStroke, comfort) : null;
    final strokePx = elem.strokeWidthPt != null
        ? (elem.strokeWidthPt! * pageScale).clamp(0.5, 8.0)
        : 0.75;

    Widget content = Stack(
      fit: StackFit.expand,
      children: [
        if (fillColor != null || strokeColor != null)
          CustomPaint(
            painter: _WordShapePainter(
              shapeType: elem.shapeType ?? 'rect',
              fillColor: fillColor,
              strokeColor: strokeColor,
              strokeWidthPx: strokePx,
            ),
          ),
        if (elem.imageBytes != null)
          GestureDetector(
            onTap: () => _viewImage(elem.imageBytes!),
            child: Image.memory(
              elem.imageBytes!,
              fit: BoxFit.fill,
              cacheWidth: imageCacheWidth,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        if (elem.textBlocks.isNotEmpty)
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: (6.0 * pageScale).clamp(2.0, 14.0),
              vertical: (4.0 * pageScale).clamp(2.0, 12.0),
            ),
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final tb in elem.textBlocks)
                    _buildBlock(
                      tb,
                      textColor,
                      scheme,
                      comfort,
                      imageCacheWidth,
                      math.max(12.0, wPx - (12.0 * pageScale).clamp(4.0, 28.0)),
                      inTableCell: true,
                      ptScaleOverride: ptScale,
                    ),
                ],
              ),
            ),
          ),
      ],
    );

    if (elem.flipH || elem.flipV) {
      content = Transform.flip(
        flipX: elem.flipH,
        flipY: elem.flipV,
        child: content,
      );
    }
    if (elem.rotationDeg.abs() > 0.01) {
      content = Transform.rotate(
        angle: elem.rotationDeg * math.pi / 180.0,
        child: content,
      );
    }

    return Positioned(
      left: elem.xPt * pageScale,
      top: elem.yPt * pageScale,
      width: wPx,
      height: hPx,
      child: content,
    );
  }

  Widget _buildTextBox(
    WordTextBoxBlock block,
    Color textColor,
    ColorScheme scheme,
    ComfortMode comfort,
    int imageCacheWidth,
    double availableWidth,
    double ptScale,
  ) {
    final wPx = block.widthPt != null
        ? math.min(availableWidth, math.max(40.0, block.widthPt! * ptScale))
        : availableWidth;
    final rawFill = _parseColor(block.fillColorHex);
    final fillColor =
        rawFill != null ? _shadingColorForComfort(rawFill, comfort) : null;
    final rawStroke = _parseColor(block.strokeColorHex);
    final strokeColor =
        rawStroke != null ? _adaptColorForComfort(rawStroke, comfort) : null;
    final strokePx = block.strokeWidthPt != null
        ? (block.strokeWidthPt! * ptScale).clamp(0.5, 6.0)
        : 0.75;

    final align = switch (block.alignment) {
      TextAlign.center => Alignment.center,
      TextAlign.right => Alignment.centerRight,
      _ => Alignment.centerLeft,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Align(
        alignment: align,
        child: CustomPaint(
          painter: (fillColor != null || strokeColor != null)
              ? _WordShapePainter(
                  shapeType: block.shapeType ?? 'rect',
                  fillColor: fillColor,
                  strokeColor: strokeColor,
                  strokeWidthPx: strokePx,
                )
              : null,
          child: Container(
            width: wPx,
            constraints: block.heightPt != null
                ? BoxConstraints(minHeight: block.heightPt! * ptScale)
                : null,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final childBlock in block.blocks)
                  _buildBlock(
                    childBlock,
                    textColor,
                    scheme,
                    comfort,
                    imageCacheWidth,
                    math.max(20.0, wPx - 20.0),
                    inTableCell: true,
                    ptScaleOverride: ptScale,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPageBreakDivider(ColorScheme scheme, ComfortMode comfort) {
    final lineColor = comfort == ComfortMode.normal
        ? const Color(0xFFD6D6D6)
        : scheme.outlineVariant.withValues(alpha: 0.5);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          Expanded(child: Divider(height: 1, thickness: 1, color: lineColor)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Icon(
              Icons.horizontal_rule_rounded,
              size: 14,
              color: lineColor,
            ),
          ),
          Expanded(child: Divider(height: 1, thickness: 1, color: lineColor)),
        ],
      ),
    );
  }

  Widget _buildBlock(
    WordBlock block,
    Color textColor,
    ColorScheme scheme,
    ComfortMode comfort,
    int imageCacheWidth,
    double availableWidth, {
    bool inTableCell = false,
    double? ptScaleOverride,
  }) {
    final ptScale = ptScaleOverride ?? (_ptToPx * _fontScale);

    if (block is WordPageBreakBlock) {
      return _buildPageBreakDivider(scheme, comfort);
    }

    if (block is WordParagraph) {
      final paraWidget = _buildParagraph(
        block,
        textColor,
        scheme,
        comfort,
        inTableCell: inTableCell,
        ptScale: ptScale,
      );
      if (block.pageBreakBefore && !inTableCell && ptScaleOverride == null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildPageBreakDivider(scheme, comfort),
            paraWidget,
          ],
        );
      }
      return paraWidget;
    }

    if (block is WordTableBlock) {
      return _buildTable(
        block,
        textColor,
        scheme,
        comfort,
        imageCacheWidth,
        availableWidth,
        ptScale: ptScale,
      );
    }

    if (block is WordImageBlock) {
      return _buildImage(
        block,
        imageCacheWidth,
        availableWidth,
        inTableCell: inTableCell,
        ptScale: ptScale,
      );
    }

    if (block is WordTextBoxBlock) {
      return _buildTextBox(
        block,
        textColor,
        scheme,
        comfort,
        imageCacheWidth,
        availableWidth,
        ptScale,
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildParagraph(
    WordParagraph block,
    Color textColor,
    ColorScheme scheme,
    ComfortMode comfort, {
    required bool inTableCell,
    required double ptScale,
  }) {
    final isHeading = block.headingLevel != null;
    final align = block.alignment ?? TextAlign.start;
    final textDirection = block.isRightToLeft ? TextDirection.rtl : null;

    final double defaultBodyPt =
        block.defaultFontSize ?? _doc?.defaultFontSizePt ?? 11.0;
    final double headingFallbackPt = switch (block.headingLevel) {
      1 => 18.0,
      2 => 15.0,
      3 => 13.0,
      _ => 12.0,
    };
    final double fallbackFontSizePt =
        isHeading ? headingFallbackPt : defaultBodyPt;

    final double spaceBeforePt = block.spaceBeforePt ??
        (inTableCell ? 0.0 : (isHeading ? (block.headingLevel == 1 ? 14.0 : 10.0) : 0.0));
    final double spaceAfterPt = block.spaceAfterPt ??
        (inTableCell ? 2.0 : (isHeading ? 4.0 : 6.0));
    final double spaceBeforePx = spaceBeforePt * ptScale;
    final double spaceAfterPx = spaceAfterPt * ptScale;

    final hasBorders = block.borders != null && block.borders!.hasAny;
    final bgColor = _parseColor(block.backgroundColorHex);

    if (block.isEmptySpacer) {
      if (hasBorders || bgColor != null) {
        return Container(
          margin: EdgeInsets.only(top: spaceBeforePx, bottom: spaceAfterPx),
          padding: EdgeInsets.symmetric(
            vertical: hasBorders ? 2.4 * ptScale : 4.8 * ptScale,
          ),
          decoration: BoxDecoration(
            color: bgColor != null
                ? _shadingColorForComfort(bgColor, comfort)
                : null,
            border: hasBorders
                ? Border(
                    top: _borderSideFromWord(block.borders?.top, comfort),
                    bottom: _borderSideFromWord(block.borders?.bottom, comfort),
                    left: _borderSideFromWord(block.borders?.left, comfort),
                    right: _borderSideFromWord(block.borders?.right, comfort),
                  )
                : null,
          ),
          child: const SizedBox(width: double.infinity, height: 1),
        );
      }

      final lineMult = block.lineSpacingMultiplier ?? 1.15;
      final spacerHeight =
          (fallbackFontSizePt * ptScale * lineMult) +
              spaceBeforePx +
              spaceAfterPx;
      return SizedBox(height: spacerHeight.clamp(4.0, 48.0));
    }

    final hasListMarker = block.isBullet ||
        (block.listMarker != null && block.listMarker!.isNotEmpty);

    final double startIndentPt = block.indent ??
        (hasListMarker ? (block.listLevel + 1) * 18.0 : 0.0);
    final double endIndentPt = block.indentRight ?? 0.0;
    final double firstLinePt = block.firstLineIndent ?? 0.0;

    final double effectiveStartPx = hasListMarker
        ? (firstLinePt < 0
                ? math.max(0.0, startIndentPt + firstLinePt)
                : math.max(0.0, startIndentPt - 18.0)) *
            ptScale
        : math.max(0.0, startIndentPt + (firstLinePt < 0 ? firstLinePt : 0.0)) *
            ptScale;
    final double effectiveEndPx = math.max(0.0, endIndentPt) * ptScale;

    final bool shouldFallbackHeadingBold = isHeading &&
        _doc?.defaultFontSizePt == null &&
        block.defaultFontSize == null &&
        block.spans.every((s) => !s.bold && s.fontSize == null);

    InlineSpan buildSpan(WordSpan span) {
      final isMatch = _searchQuery.isNotEmpty &&
          EncodingUtils.searchMatches(span.text, _searchQuery);
      final rawSpanColor = _parseColor(span.colorHex);
      final Color spanColor = rawSpanColor != null
          ? _adaptColorForComfort(rawSpanColor, comfort)
          : textColor;

      final isLink = span.linkUrl != null;
      final effectiveColor = isMatch
          ? Colors.black
          : (isLink
              ? (rawSpanColor != null
                  ? spanColor
                  : _adaptColorForComfort(const Color(0xFF0563C1), comfort))
              : spanColor);

      final effectiveDecoration = _resolveDecoration(
        span.underline || isLink,
        span.strikethrough,
      );

      final rawShading = _parseColor(span.shadingColorHex);
      final Color? effectiveBg = isMatch
          ? Colors.yellow
          : (_getHighlightColor(span.highlightHex) ??
              (rawShading != null
                  ? _shadingColorForComfort(rawShading, comfort)
                  : null));

      final double fontSizePt = span.fontSize ?? fallbackFontSizePt;
      final double effectiveFontSizePx = fontSizePt * ptScale;

      final double lineHeight;
      if (block.lineSpacingExactPt != null && fontSizePt > 0) {
        lineHeight = (block.lineSpacingExactPt! / fontSizePt).clamp(1.0, 4.0);
      } else if (block.lineSpacingMultiplier != null) {
        lineHeight = block.lineSpacingMultiplier!.clamp(0.95, 4.0);
      } else {
        lineHeight = 1.15;
      }

      final fontSpec = _resolveFontSpec(span.fontFamily);
      final fontWeight = (span.bold || shouldFallbackHeadingBold)
          ? FontWeight.bold
          : FontWeight.normal;
      final displayText = span.allCaps ? span.text.toUpperCase() : span.text;

      final style = TextStyle(
        fontSize: effectiveFontSizePx,
        height: lineHeight,
        fontWeight: fontWeight,
        fontStyle: span.italic ? FontStyle.italic : FontStyle.normal,
        decoration: effectiveDecoration,
        decorationColor: effectiveColor,
        color: effectiveColor,
        backgroundColor: effectiveBg,
        fontFamily: fontSpec.fontFamily,
        fontFamilyFallback: fontSpec.fallback,
        fontFeatures:
            span.smallCaps ? const [FontFeature.enable('smcp')] : null,
        letterSpacing: span.letterSpacingPt != null
            ? span.letterSpacingPt! * ptScale
            : null,
      );

      if (span.isSuperscript || span.isSubscript) {
        final scaledSize = effectiveFontSizePx * 0.68;
        final dy = span.isSuperscript
            ? -effectiveFontSizePx * 0.28
            : effectiveFontSizePx * 0.20;
        Widget scriptWidget = Transform.translate(
          offset: Offset(0, dy),
          child: Text(
            displayText,
            style: style.copyWith(fontSize: scaledSize, height: 1.0),
          ),
        );
        if (isLink) {
          scriptWidget = GestureDetector(
            onTap: () => _openLink(span.linkUrl!),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: scriptWidget,
            ),
          );
        }
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: scriptWidget,
        );
      }

      return TextSpan(
        text: displayText,
        recognizer: isLink ? _recognizerForUrl(span.linkUrl!) : null,
        mouseCursor:
            isLink ? SystemMouseCursors.click : SystemMouseCursors.text,
        style: style,
      );
    }

    final inlineChildren = <InlineSpan>[
      if (!hasListMarker && firstLinePt > 0)
        WidgetSpan(
          child: SizedBox(width: firstLinePt * ptScale),
        ),
      ...block.spans.map(buildSpan),
    ];

    Widget textContent = SelectableText.rich(
      TextSpan(children: inlineChildren),
      textAlign: align,
      textDirection: textDirection,
    );

    if (hasListMarker) {
      final firstSpan = block.spans.firstOrNull;
      final markerPt = firstSpan?.fontSize ?? fallbackFontSizePt;
      final markerPx = markerPt * ptScale;
      final rawMarkerColor = _parseColor(firstSpan?.colorHex);
      final markerColor = rawMarkerColor != null
          ? _adaptColorForComfort(rawMarkerColor, comfort)
          : textColor;
      final markerFontSpec = _resolveFontSpec(firstSpan?.fontFamily);
      final markerGapPx = firstLinePt < 0
          ? math.max(10.0, (-firstLinePt) * ptScale)
          : 14.0 * ptScale;
      final markerText = block.listMarker ?? '•';

      textContent = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        textDirection: textDirection,
        children: [
          SizedBox(
            width: math.max(markerGapPx, markerText.length * markerPx * 0.55),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 4),
              child: Text(
                markerText,
                style: TextStyle(
                  fontSize: markerPx,
                  height: block.lineSpacingMultiplier?.clamp(0.95, 4.0) ?? 1.15,
                  color: markerColor,
                  fontWeight:
                      (firstSpan?.bold ?? false) ? FontWeight.bold : FontWeight.normal,
                  fontFamily: markerFontSpec.fontFamily,
                  fontFamilyFallback: markerFontSpec.fallback,
                ),
              ),
            ),
          ),
          Expanded(child: textContent),
        ],
      );
    }

    Widget paragraphWidget = Padding(
      padding: EdgeInsetsDirectional.only(
        start: effectiveStartPx.clamp(0.0, 220.0),
        end: effectiveEndPx.clamp(0.0, 160.0),
        top: spaceBeforePx,
        bottom: spaceAfterPx,
      ),
      child: textContent,
    );

    if (bgColor != null || hasBorders) {
      paragraphWidget = Container(
        margin: EdgeInsets.only(
          top: hasBorders ? 2 : 0,
          bottom: hasBorders ? 2 : 0,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: (bgColor != null ||
                  (block.borders?.left?.isVisible ?? false) ||
                  (block.borders?.right?.isVisible ?? false))
              ? 8
              : 0,
          vertical: (bgColor != null ||
                  (block.borders?.top?.isVisible ?? false) ||
                  (block.borders?.bottom?.isVisible ?? false))
              ? 4
              : 0,
        ),
        decoration: BoxDecoration(
          color:
              bgColor != null ? _shadingColorForComfort(bgColor, comfort) : null,
          border: hasBorders
              ? Border(
                  top: _borderSideFromWord(block.borders?.top, comfort),
                  bottom: _borderSideFromWord(block.borders?.bottom, comfort),
                  left: _borderSideFromWord(block.borders?.left, comfort),
                  right: _borderSideFromWord(block.borders?.right, comfort),
                )
              : null,
        ),
        child: paragraphWidget,
      );
    }

    return paragraphWidget;
  }

  Widget _buildImage(
    WordImageBlock block,
    int imageCacheWidth,
    double availableWidth, {
    required bool inTableCell,
    required double ptScale,
  }) {
    double? wPx =
        block.widthPt != null ? block.widthPt! * ptScale : null;
    double? hPx =
        block.heightPt != null ? block.heightPt! * ptScale : null;

    if (wPx != null && wPx > availableWidth) {
      final ratio = availableWidth / wPx;
      wPx = availableWidth;
      if (hPx != null) hPx *= ratio;
    }

    final align = switch (block.alignment) {
      TextAlign.center => Alignment.center,
      TextAlign.right => Alignment.centerRight,
      _ => Alignment.centerLeft,
    };

    return Padding(
      padding: EdgeInsets.symmetric(vertical: inTableCell ? 4 : 8),
      child: Align(
        alignment: align,
        child: GestureDetector(
          onTap: () => _viewImage(block.bytes),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Image.memory(
              block.bytes,
              width: wPx,
              height: hPx,
              fit: BoxFit.contain,
              cacheWidth: imageCacheWidth,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTable(
    WordTableBlock block,
    Color textColor,
    ColorScheme scheme,
    ComfortMode comfort,
    int imageCacheWidth,
    double availableWidth, {
    double? ptScale,
  }) {
    final effPtScale = ptScale ?? (_ptToPx * _fontScale);
    final rawRichRows = block.richCells ??
        block.rows
            .map(
              (r) => r
                  .map((text) => WordTableCell(text: text))
                  .toList(),
            )
            .toList();

    if (rawRichRows.isEmpty) return const SizedBox.shrink();

    final numRows = rawRichRows.length;
    var numCols = block.columnWidthsPt?.length ?? 0;
    for (final row in rawRichRows) {
      var rowSpanSum = 0;
      for (final cell in row) {
        rowSpanSum += cell.colSpan;
      }
      if (rowSpanSum > numCols) numCols = rowSpanSum;
    }
    if (numCols == 0) return const SizedBox.shrink();

    // Place cells onto an occupancy grid to support colSpan and rowSpan cleanly.
    final occupied = List.generate(numRows, (_) => List.filled(numCols, false));
    final placedCells = <_PlacedTableCell>[];
    var anyCellHasBorders = false;

    for (int r = 0; r < numRows; r++) {
      var cIdx = 0;
      for (final cell in rawRichRows[r]) {
        while (cIdx < numCols && occupied[r][cIdx]) {
          cIdx++;
        }
        if (cIdx >= numCols) break;

        if (cell.borders != null) {
          anyCellHasBorders = true;
        }

        final effColSpan = math.min(cell.colSpan, numCols - cIdx);
        final effRowSpan = math.min(cell.rowSpan, numRows - r);

        if (cell.isVerticalMergeContinue) {
          for (int cc = cIdx; cc < cIdx + effColSpan; cc++) {
            occupied[r][cc] = true;
          }
          cIdx += effColSpan;
          continue;
        }

        for (int rr = r; rr < r + effRowSpan; rr++) {
          for (int cc = cIdx; cc < cIdx + effColSpan; cc++) {
            occupied[rr][cc] = true;
          }
        }

        placedCells.add(
          _PlacedTableCell(
            row: r,
            col: cIdx,
            rowSpan: effRowSpan,
            colSpan: effColSpan,
            cell: cell,
          ),
        );
        cIdx += effColSpan;
      }
    }

    if (placedCells.isEmpty) return const SizedBox.shrink();

    // Compute finite pixel column widths.
    final List<double> rawColWidthsPx;
    if (block.columnWidthsPt != null && block.columnWidthsPt!.length >= numCols) {
      rawColWidthsPx = [
        for (int c = 0; c < numCols; c++)
          math.max(24.0, block.columnWidthsPt![c] * effPtScale),
      ];
    } else {
      final firstRowWidths = List<double?>.filled(numCols, null);
      for (final p in placedCells) {
        if (p.row == 0 && p.colSpan == 1 && p.cell.widthPt != null) {
          firstRowWidths[p.col] = p.cell.widthPt! * effPtScale;
        }
      }
      final fallbackColW =
          math.max(48.0, availableWidth / math.max(1, numCols));
      rawColWidthsPx = [
        for (int c = 0; c < numCols; c++)
          math.max(24.0, firstRowWidths[c] ?? fallbackColW),
      ];
    }

    final totalRawWidth = rawColWidthsPx.fold<double>(0.0, (a, b) => a + b);
    final minReadableTotal = numCols * 44.0;
    final double totalTableWidth;
    if (block.widthPercent != null && block.widthPercent! > 0) {
      final target = availableWidth *
          (block.widthPercent!.clamp(10.0, 100.0) / 100.0);
      totalTableWidth = math.max(target, minReadableTotal);
    } else if (block.widthPt != null && block.widthPt! > 0) {
      final explicitPx = block.widthPt! * effPtScale;
      if (explicitPx <= availableWidth) {
        totalTableWidth = explicitPx;
      } else if (minReadableTotal <= availableWidth) {
        totalTableWidth = availableWidth;
      } else {
        totalTableWidth = math.max(explicitPx, minReadableTotal);
      }
    } else if (totalRawWidth <= availableWidth) {
      totalTableWidth = totalRawWidth;
    } else if (minReadableTotal <= availableWidth) {
      totalTableWidth = availableWidth;
    } else {
      totalTableWidth = math.max(totalRawWidth, minReadableTotal);
    }

    final widthScale =
        totalRawWidth > 0 ? (totalTableWidth / totalRawWidth) : 1.0;
    final colWidthsPx = rawColWidthsPx.map((w) => w * widthScale).toList();

    final hasDeclaredBorders = block.borders != null || anyCellHasBorders;
    final fallbackEdge = BorderSide(
      color: _adaptColorForComfort(const Color(0xFFD0D0D0), comfort),
      width: 0.6,
    );

    final tableChildren = <Widget>[];
    for (final placed in placedCells) {
      final cell = placed.cell;
      var spanWidthPx = 0.0;
      for (int c = placed.col; c < placed.col + placed.colSpan; c++) {
        spanWidthPx += colWidthsPx[c];
      }

      final BorderSide topSide;
      final BorderSide bottomSide;
      final BorderSide leftSide;
      final BorderSide rightSide;

      if (!hasDeclaredBorders) {
        topSide = placed.row == 0 ? fallbackEdge : BorderSide.none;
        bottomSide = fallbackEdge;
        leftSide = placed.col == 0 ? fallbackEdge : BorderSide.none;
        rightSide = fallbackEdge;
      } else {
        final cBorders = cell.borders;
        final tBorders = block.borders;
        topSide = cBorders?.top != null
            ? _borderSideFromWord(cBorders!.top, comfort)
            : (placed.row == 0
                ? _borderSideFromWord(tBorders?.top, comfort)
                : BorderSide.none);
        bottomSide = cBorders?.bottom != null
            ? _borderSideFromWord(cBorders!.bottom, comfort)
            : _borderSideFromWord(
                placed.row + placed.rowSpan == numRows
                    ? tBorders?.bottom
                    : tBorders?.insideH,
                comfort,
              );
        leftSide = cBorders?.left != null
            ? _borderSideFromWord(cBorders!.left, comfort)
            : (placed.col == 0
                ? _borderSideFromWord(tBorders?.left, comfort)
                : BorderSide.none);
        rightSide = cBorders?.right != null
            ? _borderSideFromWord(cBorders!.right, comfort)
            : _borderSideFromWord(
                placed.col + placed.colSpan == numCols
                    ? tBorders?.right
                    : tBorders?.insideV,
                comfort,
              );
      }

      final padTop =
          (cell.paddingTopPt ?? block.defaultCellPaddingTopPt ?? 3.0) *
              effPtScale;
      final padBottom =
          (cell.paddingBottomPt ?? block.defaultCellPaddingBottomPt ?? 3.0) *
              effPtScale;
      final padLeft =
          (cell.paddingLeftPt ?? block.defaultCellPaddingLeftPt ?? 5.4) *
              effPtScale;
      final padRight =
          (cell.paddingRightPt ?? block.defaultCellPaddingRightPt ?? 5.4) *
              effPtScale;

      final cellContentWidth =
          math.max(20.0, spanWidthPx - padLeft - padRight);
      final rawCellBg = _parseColor(cell.backgroundColorHex);
      final cellBg =
          rawCellBg != null ? _shadingColorForComfort(rawCellBg, comfort) : null;

      final vAlign = switch (cell.verticalAlignment) {
        'center' => Alignment.centerLeft,
        'bottom' => Alignment.bottomLeft,
        _ => Alignment.topLeft,
      };

      Widget cellInner;
      if (cell.blocks.isNotEmpty) {
        cellInner = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final childBlock in cell.blocks)
              _buildBlock(
                childBlock,
                textColor,
                scheme,
                comfort,
                imageCacheWidth,
                cellContentWidth,
                inTableCell: true,
                ptScaleOverride: ptScale,
              ),
          ],
        );
      } else {
        cellInner = SelectableText(
          cell.text,
          textAlign: cell.alignment ?? TextAlign.start,
          style: TextStyle(
            fontSize: (_doc?.defaultFontSizePt ?? 11.0) * effPtScale,
            fontWeight: cell.isHeader ? FontWeight.bold : FontWeight.normal,
            color: textColor,
          ),
        );
      }

      tableChildren.add(
        _WordGridCellData(
          row: placed.row,
          col: placed.col,
          rowSpan: placed.rowSpan,
          colSpan: placed.colSpan,
          child: Container(
            decoration: BoxDecoration(
              color: cellBg,
              border: Border(
                top: topSide,
                bottom: bottomSide,
                left: leftSide,
                right: rightSide,
              ),
            ),
            padding: EdgeInsets.fromLTRB(padLeft, padTop, padRight, padBottom),
            alignment: vAlign,
            child: cellInner,
          ),
        ),
      );
    }

    final tableAlign = switch (block.alignment) {
      TextAlign.center => Alignment.center,
      TextAlign.right => Alignment.centerRight,
      _ => Alignment.centerLeft,
    };

    Widget gridWidget = _WordGridTable(
      numRows: numRows,
      colWidths: colWidthsPx,
      children: tableChildren,
    );

    if (totalTableWidth > availableWidth + 0.5) {
      gridWidget = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: gridWidget,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Align(
        alignment: tableAlign,
        child: gridWidget,
      ),
    );
  }
}

class _PlacedTableCell {
  const _PlacedTableCell({
    required this.row,
    required this.col,
    required this.rowSpan,
    required this.colSpan,
    required this.cell,
  });

  final int row;
  final int col;
  final int rowSpan;
  final int colSpan;
  final WordTableCell cell;
}

class _WordGridCellParentData extends ContainerBoxParentData<RenderBox> {
  int row = 0;
  int col = 0;
  int rowSpan = 1;
  int colSpan = 1;
}

class _WordGridCellData extends ParentDataWidget<_WordGridCellParentData> {
  const _WordGridCellData({
    required this.row,
    required this.col,
    required this.rowSpan,
    required this.colSpan,
    required super.child,
  });

  final int row;
  final int col;
  final int rowSpan;
  final int colSpan;

  @override
  void applyParentData(RenderObject renderObject) {
    final parentData = renderObject.parentData! as _WordGridCellParentData;
    var needsLayout = false;
    if (parentData.row != row) {
      parentData.row = row;
      needsLayout = true;
    }
    if (parentData.col != col) {
      parentData.col = col;
      needsLayout = true;
    }
    if (parentData.rowSpan != rowSpan) {
      parentData.rowSpan = rowSpan;
      needsLayout = true;
    }
    if (parentData.colSpan != colSpan) {
      parentData.colSpan = colSpan;
      needsLayout = true;
    }
    if (needsLayout) {
      renderObject.parent?.markNeedsLayout();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => _WordGridTable;
}

class _WordGridTable extends MultiChildRenderObjectWidget {
  const _WordGridTable({
    required this.numRows,
    required this.colWidths,
    required super.children,
  });

  final int numRows;
  final List<double> colWidths;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderWordGridTable(numRows: numRows, colWidths: colWidths);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderWordGridTable renderObject,
  ) {
    renderObject
      ..numRows = numRows
      ..colWidths = colWidths;
  }
}

class _RenderWordGridTable extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _WordGridCellParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _WordGridCellParentData> {
  _RenderWordGridTable({
    required int numRows,
    required List<double> colWidths,
  })  : _numRows = numRows,
        _colWidths = colWidths;

  int _numRows;
  int get numRows => _numRows;
  set numRows(int value) {
    if (_numRows == value) return;
    _numRows = value;
    markNeedsLayout();
  }

  List<double> _colWidths;
  List<double> get colWidths => _colWidths;
  set colWidths(List<double> value) {
    _colWidths = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _WordGridCellParentData) {
      child.parentData = _WordGridCellParentData();
    }
  }

  double _spanWidth(int col, int colSpan) {
    var sum = 0.0;
    final end = math.min(_colWidths.length, col + colSpan);
    for (int c = col; c < end; c++) {
      sum += _colWidths[c];
    }
    return sum;
  }

  @override
  void performLayout() {
    final totalWidth = _colWidths.fold<double>(0.0, (a, b) => a + b);
    final rowHeights = List<double>.filled(_numRows, 0.0);

    // Pass 1: measure every child at its exact span width.
    final children = <RenderBox>[];
    RenderBox? child = firstChild;
    while (child != null) {
      final pd = child.parentData! as _WordGridCellParentData;
      final w = _spanWidth(pd.col, pd.colSpan);
      child.layout(
        BoxConstraints(minWidth: w, maxWidth: w),
        parentUsesSize: true,
      );
      children.add(child);
      if (pd.rowSpan == 1 && pd.row < _numRows) {
        rowHeights[pd.row] = math.max(rowHeights[pd.row], child.size.height);
      }
      child = pd.nextSibling;
    }

    // Pass 2: expand spanned rows if any rowSpan > 1 cell is taller than its rows.
    for (final c in children) {
      final pd = c.parentData! as _WordGridCellParentData;
      if (pd.rowSpan <= 1) continue;
      final endRow = math.min(_numRows, pd.row + pd.rowSpan);
      var spanH = 0.0;
      for (int r = pd.row; r < endRow; r++) {
        spanH += rowHeights[r];
      }
      if (c.size.height > spanH && endRow > pd.row) {
        final extraPerRow = (c.size.height - spanH) / (endRow - pd.row);
        for (int r = pd.row; r < endRow; r++) {
          rowHeights[r] += extraPerRow;
        }
      }
    }

    // Compute row and column offsets.
    final colOffsets = List<double>.filled(_colWidths.length + 1, 0.0);
    for (int c = 0; c < _colWidths.length; c++) {
      colOffsets[c + 1] = colOffsets[c] + _colWidths[c];
    }

    final rowOffsets = List<double>.filled(_numRows + 1, 0.0);
    for (int r = 0; r < _numRows; r++) {
      rowOffsets[r + 1] = rowOffsets[r] + rowHeights[r];
    }

    // Pass 3: tighten any cell shorter than its final spanned row height, then position.
    for (final c in children) {
      final pd = c.parentData! as _WordGridCellParentData;
      final w = _spanWidth(pd.col, pd.colSpan);
      final endRow = math.min(_numRows, pd.row + pd.rowSpan);
      var targetH = 0.0;
      for (int r = pd.row; r < endRow; r++) {
        targetH += rowHeights[r];
      }
      if ((c.size.height - targetH).abs() > 0.25) {
        c.layout(
          BoxConstraints.tightFor(width: w, height: targetH),
          parentUsesSize: true,
        );
      }
      pd.offset = Offset(colOffsets[pd.col], rowOffsets[pd.row]);
    }

    size = constraints.constrain(Size(totalWidth, rowOffsets[_numRows]));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }
}

class _WordShapePainter extends CustomPainter {
  const _WordShapePainter({
    required this.shapeType,
    this.fillColor,
    this.strokeColor,
    this.strokeWidthPx = 1.0,
  });

  final String shapeType;
  final Color? fillColor;
  final Color? strokeColor;
  final double strokeWidthPx;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 && h <= 0) return;

    final lower = shapeType.toLowerCase();
    final Path path;

    if (lower == 'line' || lower == 'straightconnector1') {
      path = Path();
      if (h <= 2.0) {
        path.moveTo(0, h / 2);
        path.lineTo(w, h / 2);
      } else if (w <= 2.0) {
        path.moveTo(w / 2, 0);
        path.lineTo(w / 2, h);
      } else {
        path.moveTo(0, 0);
        path.lineTo(w, h);
      }
      if (strokeColor != null && strokeWidthPx > 0) {
        canvas.drawPath(
          path,
          Paint()
            ..color = strokeColor!
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidthPx,
        );
      }
      return;
    }

    if (lower == 'ellipse') {
      path = Path()..addOval(Rect.fromLTWH(0, 0, w, h));
    } else if (lower == 'roundrect') {
      final r = math.min(w, h) * 0.14;
      path = Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(0, 0, w, h),
            Radius.circular(r),
          ),
        );
    } else if (lower == 'octagon' ||
        lower == 'snip2samerect' ||
        lower == 'snip1rect' ||
        lower == 'snip2diagrect' ||
        lower == 'sniproundrect') {
      final chamfer = math.min(w, h) * (lower == 'octagon' ? 0.18 : 0.12);
      path = Path()
        ..moveTo(chamfer, 0)
        ..lineTo(w - chamfer, 0)
        ..lineTo(w, chamfer)
        ..lineTo(w, h - chamfer)
        ..lineTo(w - chamfer, h)
        ..lineTo(chamfer, h)
        ..lineTo(0, h - chamfer)
        ..lineTo(0, chamfer)
        ..close();
    } else {
      path = Path()..addRect(Rect.fromLTWH(0, 0, w, h));
    }

    if (fillColor != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color = fillColor!
          ..style = PaintingStyle.fill,
      );
    }
    if (strokeColor != null && strokeWidthPx > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..color = strokeColor!
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidthPx,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WordShapePainter oldDelegate) {
    return oldDelegate.shapeType != shapeType ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.strokeColor != strokeColor ||
        oldDelegate.strokeWidthPx != strokeWidthPx;
  }
}

/// Scroll physics that lock user scrolling while the page is pinch-zoomed,
/// reading the zoom state live so the list never has to be rebuilt mid-pinch.
class _ZoomLockScrollPhysics extends ScrollPhysics {
  const _ZoomLockScrollPhysics(this.locked, {super.parent});

  final ValueListenable<bool> locked;

  @override
  _ZoomLockScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _ZoomLockScrollPhysics(locked, parent: buildParent(ancestor));

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) =>
      !locked.value && super.shouldAcceptUserOffset(position);
}
