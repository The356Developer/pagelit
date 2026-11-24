import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/app_localizations.dart';
import '../services/device_pdfs.dart';
import '../services/display/display_service.dart';
import '../services/encoding_utils.dart';
import '../services/gallery_saver.dart';
import '../services/gemini_share_service.dart';
import '../services/hand_tracking/hand_tracking_service.dart';
import '../services/presentation_parser.dart';
import '../services/session/session_models.dart';
import '../services/slide_image_precacher.dart';
import '../widgets/page_scrubber.dart';
import 'presenter_view_screen.dart';

enum PresentationViewMode {
  slides,
  outline,
}

class PresentationViewerScreen extends StatefulWidget {
  const PresentationViewerScreen({
    super.key,
    required this.filePath,
    required this.title,
  });

  final String filePath;
  final String title;

  @override
  State<PresentationViewerScreen> createState() => _PresentationViewerScreenState();
}

class _PresentationViewerScreenState extends State<PresentationViewerScreen> {
  final Map<int, GlobalKey> _slideKeys = {};
  PresentationDeck? _deck;
  bool _isLoading = true;
  bool _isSavingToGallery = false;
  String? _error;
  int _currentSlideIndex = 0;
  final PageController _pageController = PageController();
  final ValueNotifier<bool> _isZoomedNotifier = ValueNotifier<bool>(false);
  int _resetZoomTrigger = 0;
  int _replayTrigger = 0;
  bool _enableAnimations = true;

  PresentationViewMode _viewMode = PresentationViewMode.slides;
  bool _isSearchOpen = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  double _fontScale = 1.0;
  bool _fillContainer = true;
  bool _showDesktopSlideStrip = true;

  GlobalKey _keyForSlide(int index) =>
      _slideKeys.putIfAbsent(index, GlobalKey.new);

  @override
  void dispose() {
    _isZoomedNotifier.dispose();
    _pageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  void _resetZoom() {
    _isZoomedNotifier.value = false;
    setState(() {
      _resetZoomTrigger++;
    });
  }

  void _replayAnimations() {
    if (!_enableAnimations) {
      setState(() => _enableAnimations = true);
    }
    setState(() => _replayTrigger++);
  }

  Future<void> _loadFile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final file = File(widget.filePath);
      final bytes = await file.readAsBytes();
      if (DevicePdfLibrary.isLegacyOleBinary(bytes)) {
        if (!mounted) return;
        setState(() {
          _error =
              'Legacy PowerPoint 97–2003 (.ppt) binary files are not supported directly. Please re-save as .pptx or PDF.';
          _isLoading = false;
        });
        return;
      }
      final deck = await PresentationParser.parse(bytes);
      if (!mounted) return;
      setState(() {
        _deck = deck;
        _isLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _deck != null) {
          SlideImagePrecacher.precacheAround(
            context,
            _deck!,
            _currentSlideIndex,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load presentation: $e';
        _isLoading = false;
      });
    }
  }

  bool get _isDesktop =>
      !Platform.environment.containsKey('FLUTTER_TEST') &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  Future<void> _startSlideshow({
    bool forcePresenterView = false,
    bool fromBeginning = false,
  }) async {
    if (_deck == null || _deck!.slides.isEmpty) return;
    final startIdx = fromBeginning ? 0 : _currentSlideIndex;

    if (_isDesktop) {
      final displays = await DisplayService.instance.getDisplays();
      if (!mounted) return;
      if (forcePresenterView || displays.length >= 2) {
        final lastIdx = await PresenterViewScreen.push(
          context,
          deck: _deck!,
          filePath: widget.filePath,
          title: widget.title,
          initialSlideIndex: startIdx,
          enableAnimations: _enableAnimations,
          autoLaunchProjector: displays.length >= 2,
        );
        if (mounted &&
            lastIdx != null &&
            _pageController.hasClients &&
            lastIdx != _currentSlideIndex) {
          _pageController.jumpToPage(lastIdx);
        }
        return;
      }
    }

    if (!mounted) return;
    final lastIdx = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (_) => PresentationSlideshowScreen(
          deck: _deck!,
          filePath: widget.filePath,
          initialSlideIndex: startIdx,
          title: widget.title,
          enableAnimations: _enableAnimations,
        ),
      ),
    );
    if (mounted &&
        lastIdx != null &&
        _pageController.hasClients &&
        lastIdx != _currentSlideIndex) {
      _pageController.jumpToPage(lastIdx);
    }
  }

  Future<void> _shareFile() async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(widget.filePath)],
        title: EncodingUtils.cleanDisplayName(widget.title),
      ),
    );
  }

  Future<void> _saveSlideToGallery() async {
    if (_deck == null || _deck!.slides.isEmpty || _isSavingToGallery) return;
    final key = _slideKeys[_currentSlideIndex];
    if (key == null) return;
    final l10n = context.l10n;
    setState(() => _isSavingToGallery = true);
    final cleanTitle = EncodingUtils.cleanDisplayName(widget.title);
    final slideNum = _currentSlideIndex + 1;
    try {
      await GallerySaver.saveBoundaryToGallery(
        context: context,
        boundaryKey: key,
        baseName: 'Pagelit_${cleanTitle}_slide_$slideNum',
        successMessage: l10n.slideSaved(slideNum),
      );
    } finally {
      if (mounted) setState(() => _isSavingToGallery = false);
    }
  }

  Future<void> _askGemini() async {
    if (_deck == null || _deck!.slides.isEmpty) return;
    final key = _slideKeys[_currentSlideIndex];
    if (key == null) return;
    final cleanTitle = EncodingUtils.cleanDisplayName(widget.title);
    final slideNum = _currentSlideIndex + 1;
    await GeminiShareService.shareBoundaryToGemini(
      context: context,
      boundaryKey: key,
      pageTitle: '$cleanTitle (Slide $slideNum)',
      customPrompt: 'Please summarize, explain the key points, and provide insights for this presentation slide.',
    );
  }

  void _openSlideOverview() {
    if (_deck == null || _deck!.slides.isEmpty) return;
    final l10n = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l10n.allSlidesCount(_deck!.slides.length),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${_deck!.aspectRatio > 1.5 ? "16:9" : "4:3"} • ${_deck!.slides.length} slides',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: GridView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 1.35,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: _deck!.slides.length,
                      itemBuilder: (context, idx) {
                        final slide = _deck!.slides[idx];
                        final isCurrent = idx == _currentSlideIndex;
                        final hasSearchMatch = _searchQuery.isNotEmpty &&
                            (EncodingUtils.searchMatches(slide.title, _searchQuery) ||
                                slide.bulletPoints.any((b) => EncodingUtils.searchMatches(b, _searchQuery)) ||
                                slide.elements.any((e) =>
                                    e is SlideShapeElement && EncodingUtils.searchMatches(e.plainText, _searchQuery)));
                        final scheme = Theme.of(context).colorScheme;

                        return InkWell(
                          onTap: () {
                            Navigator.of(context).pop();
                            _pageController.jumpToPage(idx);
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? scheme.primaryContainer
                                  : hasSearchMatch
                                      ? Colors.amber.withValues(alpha: 0.25)
                                      : scheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isCurrent
                                    ? scheme.primary
                                    : hasSearchMatch
                                        ? Colors.orange
                                        : scheme.outlineVariant,
                                width: isCurrent || hasSearchMatch ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        l10n.slideNumber(slide.slideNumber),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isCurrent ? scheme.onPrimaryContainer : scheme.outline,
                                        ),
                                      ),
                                      if (hasSearchMatch)
                                        const Icon(Icons.search_rounded, size: 12, color: Colors.orange),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Container(
                                    color: slide.backgroundColor ?? Colors.white,
                                    padding: const EdgeInsets.all(6),
                                    child: slide.elements.isNotEmpty
                                        ? FittedBox(
                                            fit: BoxFit.contain,
                                            child: SizedBox(
                                              width: 320,
                                              height: 320 / _deck!.aspectRatio,
                                              child: SlideCanvasView(
                                                slide: slide,
                                                aspectRatio: _deck!.aspectRatio,
                                                themeColors: _deck!.themeColors,
                                                fontScale: 0.9,
                                                searchQuery: '',
                                                enableAnimations: false,
                                                isThumbnail: true,
                                              ),
                                            ),
                                          )
                                        : Center(
                                            child: Text(
                                              EncodingUtils.cleanDisplayName(slide.title),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: scheme.onSurface,
                                              ),
                                            ),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _viewImage(Uint8List imageBytes) {
    final l10n = context.l10n;
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(imageBytes, fit: BoxFit.contain),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton.filledTonal(
                  tooltip: l10n.saveImageToGallery,
                  icon: const Icon(Icons.download_rounded),
                  onPressed: () async {
                    final cleanTitle = EncodingUtils.cleanDisplayName(widget.title);
                    await GallerySaver.saveBytesToGallery(
                      context: dialogCtx,
                      imageBytes: imageBytes,
                      name: 'Pagelit_${cleanTitle}_img_${DateTime.now().millisecondsSinceEpoch}',
                      successMessage: l10n.imageSavedToGallery,
                    );
                  },
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _highlightedText(String text, TextStyle baseStyle, ColorScheme scheme) {
    if (_searchQuery.isEmpty || !EncodingUtils.searchMatches(text, _searchQuery)) {
      return SelectableText(text, style: baseStyle);
    }

    final cleanQuery = EncodingUtils.removeDiacritics(_searchQuery.toLowerCase());
    final cleanText = EncodingUtils.removeDiacritics(text.toLowerCase());
    final spans = <TextSpan>[];
    int start = 0;

    while (start < text.length) {
      final index = cleanText.indexOf(cleanQuery, start);
      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      final matchEnd = index + cleanQuery.length;
      spans.add(TextSpan(
        text: text.substring(index, matchEnd),
        style: const TextStyle(
          backgroundColor: Colors.yellow,
          color: Colors.black,
          fontWeight: FontWeight.bold,
        ),
      ));
      start = matchEnd;
    }

    return SelectableText.rich(
      TextSpan(style: baseStyle, children: spans),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final cleanTitle = EncodingUtils.cleanDisplayName(widget.title);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () {
          if (_deck != null && _currentSlideIndex < _deck!.slides.length - 1) {
            _pageController.nextPage(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
            );
          }
        },
        const SingleActivator(LogicalKeyboardKey.pageDown): () {
          if (_deck != null && _currentSlideIndex < _deck!.slides.length - 1) {
            _pageController.nextPage(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
            );
          }
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
          if (_currentSlideIndex > 0) {
            _pageController.previousPage(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
            );
          }
        },
        const SingleActivator(LogicalKeyboardKey.pageUp): () {
          if (_currentSlideIndex > 0) {
            _pageController.previousPage(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
            );
          }
        },
        const SingleActivator(LogicalKeyboardKey.f5): () {
          if (_deck != null && _deck!.slides.isNotEmpty) {
            _startSlideshow(fromBeginning: true);
          }
        },
        const SingleActivator(LogicalKeyboardKey.f5, shift: true): () {
          if (_deck != null && _deck!.slides.isNotEmpty) {
            _startSlideshow();
          }
        },
        const SingleActivator(LogicalKeyboardKey.f5, alt: true): () {
          if (_deck != null && _deck!.slides.isNotEmpty) {
            _startSlideshow(forcePresenterView: true);
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: LayoutBuilder(
          builder: (context, constraints) {
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
                    color: Colors.deepOrange.shade700,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'PPTX',
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
          // Play Fullscreen Presentation Slideshow (auto-uses Dual-Screen Presenter Mode when 2+ displays connected)
          if (_deck != null && _deck!.slides.isNotEmpty)
            IconButton(
              tooltip: '${l10n.playSlideshow} (F5 / Shift+F5)',
              icon: const Icon(Icons.play_circle_fill_rounded, size: 26),
              color: scheme.primary,
              onPressed: _startSlideshow,
            ),
          if (_isDesktop && _deck != null && _deck!.slides.isNotEmpty)
            IconButton(
              tooltip: 'Presenter View & 2–3m Hand Control (Alt+F5)',
              icon: const Icon(Icons.co_present_rounded, size: 22),
              onPressed: () => _startSlideshow(forcePresenterView: true),
            ),
          if (_deck != null && _deck!.slides.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 4),
              child: ActionChip(
                avatar: const Icon(Icons.grid_view_rounded, size: 16),
                label: Text('${_currentSlideIndex + 1} / ${_deck!.slides.length}'),
                onPressed: _openSlideOverview,
              ),
            ),
          // View Mode Switcher: Visual Slides vs. Outline
          IconButton(
            tooltip: _viewMode == PresentationViewMode.slides
                ? l10n.slideOutlineMode
                : l10n.slidePresentationMode,
            icon: Icon(
              _viewMode == PresentationViewMode.slides
                  ? Icons.format_list_bulleted_rounded
                  : Icons.slideshow_rounded,
            ),
            onPressed: () {
              setState(() {
                _viewMode = _viewMode == PresentationViewMode.slides
                    ? PresentationViewMode.outline
                    : PresentationViewMode.slides;
              });
            },
          ),
          IconButton(
            tooltip: l10n.search,
            icon: Icon(_isSearchOpen ? Icons.search_off_rounded : Icons.search_rounded),
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
            onPressed: _deck == null || _deck!.slides.isEmpty ? null : _askGemini,
          ),
          PopupMenuButton<String>(
            tooltip: l10n.more,
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (val) {
              switch (val) {
                case 'slideshow':
                  _startSlideshow();
                  break;
                case 'replay':
                  _replayAnimations();
                  break;
                case 'mode_toggle':
                  setState(() {
                    _viewMode = _viewMode == PresentationViewMode.slides
                        ? PresentationViewMode.outline
                        : PresentationViewMode.slides;
                  });
                  break;
                case 'animations_toggle':
                  setState(() => _enableAnimations = !_enableAnimations);
                  break;
                case 'reset_zoom':
                  _resetZoom();
                  break;
                case 'aspect':
                  setState(() => _fillContainer = !_fillContainer);
                  break;
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
                  if (!_isSavingToGallery && _deck != null && _deck!.slides.isNotEmpty) {
                    _saveSlideToGallery();
                  }
                  break;
                case 'share':
                  _shareFile();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'slideshow',
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.play_arrow_rounded),
                  title: Text(l10n.playSlideshow),
                ),
              ),
              if (_viewMode == PresentationViewMode.slides)
                PopupMenuItem(
                  value: 'replay',
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.replay_rounded),
                    title: Text(l10n.replayAnimation),
                  ),
                ),
              PopupMenuItem(
                value: 'mode_toggle',
                child: ListTile(
                  dense: true,
                  leading: Icon(_viewMode == PresentationViewMode.slides
                      ? Icons.format_list_bulleted_rounded
                      : Icons.slideshow_rounded),
                  title: Text(_viewMode == PresentationViewMode.slides
                      ? l10n.slideOutlineMode
                      : l10n.slidePresentationMode),
                ),
              ),
              PopupMenuItem(
                value: 'animations_toggle',
                child: ListTile(
                  dense: true,
                  leading: Icon(_enableAnimations ? Icons.animation_rounded : Icons.motion_photos_off_rounded),
                  title: Text(l10n.slideAnimations),
                  trailing: Icon(_enableAnimations ? Icons.check_rounded : null, size: 18),
                ),
              ),
              if (_viewMode == PresentationViewMode.slides)
                PopupMenuItem(
                  value: 'reset_zoom',
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.zoom_out_map_rounded),
                    title: Text(l10n.resetZoom),
                  ),
                ),
              PopupMenuItem(
                value: 'aspect',
                child: ListTile(
                  dense: true,
                  leading: Icon(_fillContainer ? Icons.aspect_ratio_rounded : Icons.fullscreen_rounded),
                  title: Text(_fillContainer ? l10n.aspectRatioMode : l10n.expandedBigContainer),
                ),
              ),
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
                  title: Text(l10n.saveSlideToGallery),
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
                  hintText: l10n.searchPresentationHint,
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
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
              ),
            ),
          Expanded(child: _buildBody(l10n)),
          if (_deck != null && _deck!.slides.length > 1)
            _buildBottomControls(l10n)
          else
            const SafeArea(top: false, child: SizedBox(height: 8)),
        ],
      ),
    ),
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
              const Icon(Icons.error_outline_rounded, size: 48, color: Colors.red),
              const SizedBox(height: 14),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _loadFile, child: Text(l10n.retry)),
            ],
          ),
        ),
      );
    }
    if (_deck == null || _deck!.slides.isEmpty) {
      return Center(child: Text(l10n.presentationHasNoSlides));
    }

    final isWide = MediaQuery.sizeOf(context).width >= 960;

    return Row(
      children: [
        if (isWide && _showDesktopSlideStrip)
          Container(
            width: 210,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              border: Border(
                right: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
                  child: Row(
                    children: [
                      Text(
                        'SLIDES (${_deck!.slides.length})',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              letterSpacing: 0.8,
                            ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.chevron_left_rounded, size: 18),
                        tooltip: 'Hide slide strip',
                        onPressed: () =>
                            setState(() => _showDesktopSlideStrip = false),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    itemCount: _deck!.slides.length,
                    itemBuilder: (context, idx) {
                      final s = _deck!.slides[idx];
                      final selected = idx == _currentSlideIndex;
                      final scheme = Theme.of(context).colorScheme;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Material(
                          color: selected
                              ? scheme.primaryContainer
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => _pageController.animateToPage(
                              idx,
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    '${idx + 1}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: selected
                                              ? scheme.primary
                                              : scheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      s.title.isNotEmpty
                                          ? s.title
                                          : 'Slide ${idx + 1}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            fontWeight: selected
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ValueListenableBuilder<bool>(
            valueListenable: _isZoomedNotifier,
            builder: (context, isZoomed, _) {
              return PageView.builder(
                controller: _pageController,
                physics: isZoomed
                    ? const NeverScrollableScrollPhysics()
                    : const BouncingScrollPhysics(),
                itemCount: _deck!.slides.length,
                onPageChanged: (idx) {
                  _isZoomedNotifier.value = false;
                  setState(() {
                    _currentSlideIndex = idx;
                    _resetZoomTrigger++;
                  });
                  if (_deck != null) {
                    SlideImagePrecacher.precacheAround(context, _deck!, idx);
                  }
                },
                itemBuilder: (context, index) {
                  final slide = _deck!.slides[index];
                  final isCurrent = index == _currentSlideIndex;

                  final cardWidget = _viewMode == PresentationViewMode.slides
                      ? _buildSlidePresentationCard(
                          slide,
                          isCurrent: isCurrent,
                          l10n: l10n,
                        )
                      : _buildSlideOutlineCard(slide, l10n);

                  return RepaintBoundary(
                    key: _keyForSlide(index),
                    child: cardWidget,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// Authentic visual presentation slide view with exact layout, smooth animations, and pinch/double-tap zoom.
  Widget _buildSlidePresentationCard(
    PresentationSlide slide, {
    required bool isCurrent,
    required AppLocalizations l10n,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final totalSlides = _deck?.slides.length ?? 0;
    final aspectRatio = _deck?.aspectRatio ?? (16 / 9);

    return Stack(
      alignment: Alignment.center,
      children: [
        _ZoomableSlidePage(
          resetZoomTrigger: _resetZoomTrigger,
          onZoomChanged: (zoomed) {
            if (isCurrent && zoomed != _isZoomedNotifier.value) {
              _isZoomedNotifier.value = zoomed;
            }
          },
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: slide.backgroundColor ?? Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: AspectRatio(
                  aspectRatio: aspectRatio,
                  child: SlideCanvasView(
                    key: ValueKey('slide_canvas_${slide.slideNumber}'),
                    slide: slide,
                    aspectRatio: aspectRatio,
                    themeColors: _deck?.themeColors ?? const {},
                    searchQuery: _searchQuery,
                    fontScale: _fontScale,
                    enableAnimations: _enableAnimations && isCurrent,
                    replayTrigger: isCurrent ? _replayTrigger : 0,
                    onImageTap: _viewImage,
                  ),
                ),
              ),
            ),
          ),
        ),
        // Floating Reset Zoom Button when zoomed in
        if (isCurrent)
          ValueListenableBuilder<bool>(
            valueListenable: _isZoomedNotifier,
            builder: (context, isZoomed, child) {
              if (!isZoomed) return const SizedBox.shrink();
              return child!;
            },
            child: Positioned(
              top: 16,
              right: 20,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(20),
                color: scheme.primaryContainer,
                child: InkWell(
                  onTap: _resetZoom,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.zoom_out_map_rounded, size: 16, color: scheme.onPrimaryContainer),
                        const SizedBox(width: 6),
                        Text(
                          l10n.resetZoom,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        // Bottom Slide Overlay Banner (Title + Slide Number)
        Positioned(
          bottom: 12,
          left: 20,
          right: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    EncodingUtils.cleanDisplayName(slide.title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${slide.slideNumber} / $totalSlides',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Outline / note cards view for text-focused reading and copying.
  Widget _buildSlideOutlineCard(PresentationSlide slide, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final cleanSlideTitle = EncodingUtils.cleanDisplayName(slide.title);
    final totalSlides = _deck?.slides.length ?? 0;
    final densityScale = slide.bulletPoints.length > 6
        ? 0.88
        : (slide.bulletPoints.length > 4 ? 0.94 : 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [scheme.primary, scheme.tertiary],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _highlightedText(
                      cleanSlideTitle,
                      TextStyle(
                        fontSize: 20 * _fontScale,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.2,
                        color: scheme.onSurface,
                      ),
                      scheme,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      totalSlides > 0
                          ? '${slide.slideNumber} / $totalSlides'
                          : l10n.slideNumber(slide.slideNumber),
                      style: TextStyle(
                        fontSize: 11 * _fontScale,
                        fontWeight: FontWeight.bold,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final point in slide.bulletPoints) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsetsDirectional.only(end: 10, top: 3),
                              child: Icon(
                                Icons.arrow_right_rounded,
                                size: 22,
                                color: scheme.primary,
                              ),
                            ),
                            Expanded(
                              child: _highlightedText(
                                point,
                                TextStyle(
                                  fontSize: 14.5 * _fontScale * densityScale,
                                  height: 1.55,
                                  color: scheme.onSurface,
                                ),
                                scheme,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (slide.bulletPoints.isEmpty && slide.images.isEmpty && slide.elements.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 36),
                        child: Center(
                          child: Text(
                            l10n.slideTitleOnly,
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: scheme.outline,
                              fontSize: 13 * _fontScale,
                            ),
                          ),
                        ),
                      ),
                    if (slide.images.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: slide.images.map((img) {
                          return InkWell(
                            onTap: () => _viewImage(img),
                            borderRadius: BorderRadius.circular(12),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                                  ),
                                ),
                                child: Stack(
                                  alignment: Alignment.bottomRight,
                                  children: [
                                    Image.memory(
                                      img,
                                      height: _fillContainer ? 200 : 130,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                                    ),
                                    Container(
                                      margin: const EdgeInsets.all(8),
                                      padding: const EdgeInsets.all(5),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.65),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.zoom_in_rounded,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls(AppLocalizations l10n) {
    final total = _deck!.slides.length;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
        child: PageScrubber(
          currentPage: _currentSlideIndex + 1,
          totalPages: total,
          labelBuilder: (p) => l10n.slideXOfY(p, total),
          subtitleBuilder: (p) =>
              EncodingUtils.cleanDisplayName(_deck!.slides[p - 1].title),
          onPageSelected: (p) {
            final target = (p - 1).clamp(0, total - 1);
            if (_pageController.hasClients) {
              _pageController.jumpToPage(target);
            }
          },
        ),
      ),
    );
  }
}

/// Self-contained pinch-to-zoom & double-tap zoom container per slide.
class _ZoomableSlidePage extends StatefulWidget {
  const _ZoomableSlidePage({
    required this.child,
    required this.resetZoomTrigger,
    required this.onZoomChanged,
  });

  final Widget child;
  final int resetZoomTrigger;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomableSlidePage> createState() => _ZoomableSlidePageState();
}

class _ZoomableSlidePageState extends State<_ZoomableSlidePage>
    with SingleTickerProviderStateMixin {
  final TransformationController _controller = TransformationController();
  final ValueNotifier<bool> _panEnabledNotifier = ValueNotifier<bool>(false);
  late final AnimationController _animController;
  Animation<Matrix4>? _zoomAnimation;
  Offset _doubleTapPosition = Offset.zero;
  bool _wasZoomed = false;
  int _activePointers = 0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        final anim = _zoomAnimation;
        if (anim != null) {
          _controller.value = anim.value;
        }
      });
    _controller.addListener(_handleScaleChanged);
  }

  @override
  void didUpdateWidget(covariant _ZoomableSlidePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetZoomTrigger != widget.resetZoomTrigger && _wasZoomed) {
      _animController.stop();
      _controller.value = Matrix4.identity();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _controller.removeListener(_handleScaleChanged);
    _controller.dispose();
    _panEnabledNotifier.dispose();
    super.dispose();
  }

  void _updatePanEnabled() {
    final next = _wasZoomed || _activePointers >= 2;
    if (_panEnabledNotifier.value != next) {
      _panEnabledNotifier.value = next;
    }
  }

  void _handleScaleChanged() {
    final zoomed = _controller.value.getMaxScaleOnAxis() > 1.04;
    if (zoomed != _wasZoomed) {
      _wasZoomed = zoomed;
      _updatePanEnabled();
      widget.onZoomChanged(zoomed);
    }
  }

  void _handleDoubleTap() {
    final begin = _controller.value.clone();
    final Matrix4 end;
    if (_controller.value.getMaxScaleOnAxis() > 1.04) {
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
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final cachedChild = RepaintBoundary(child: widget.child);
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
        onDoubleTap: _handleDoubleTap,
        child: ValueListenableBuilder<bool>(
          valueListenable: _panEnabledNotifier,
          child: cachedChild,
          builder: (context, panEnabled, child) {
            return InteractiveViewer(
              transformationController: _controller,
              panEnabled: panEnabled,
              minScale: 1.0,
              maxScale: 5.0,
              clipBehavior: Clip.none,
              onInteractionStart: (_) {
                if (_animController.isAnimating) {
                  _animController.stop();
                }
              },
              child: child!,
            );
          },
        ),
      ),
    );
  }
}

/// Renders an authentic PowerPoint presentation slide canvas with full layout fidelity,
/// single-controller animations (`<p:timing>` + foreground fallback), and image caching.
class SlideCanvasView extends StatefulWidget {
  const SlideCanvasView({
    super.key,
    required this.slide,
    required this.aspectRatio,
    required this.themeColors,
    this.searchQuery = '',
    this.fontScale = 1.0,
    this.enableAnimations = true,
    this.isThumbnail = false,
    this.revealedStep,
    this.replayTrigger = 0,
    this.entranceDelay = Duration.zero,
    this.onImageTap,
  });

  final PresentationSlide slide;
  final double aspectRatio;
  final Map<String, Color> themeColors;
  final String searchQuery;
  final double fontScale;
  final bool enableAnimations;
  final bool isThumbnail;
  final int? revealedStep;
  final int replayTrigger;
  final Duration entranceDelay;
  final void Function(Uint8List bytes)? onImageTap;

  @override
  State<SlideCanvasView> createState() => _SlideCanvasViewState();
}

class _SlideCanvasViewState extends State<SlideCanvasView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _delayTimer;
  bool _initialized = false;
  late Map<String, List<SlideAnimationStep>> _stepsByShape;
  late List<int> _foregroundIndexMap;
  late int _foregroundCount;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _indexSlideData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _startEntranceAnimation();
    }
  }

  @override
  void didUpdateWidget(covariant SlideCanvasView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final slideChanged = oldWidget.slide.slideNumber != widget.slide.slideNumber ||
        !identical(oldWidget.slide, widget.slide);
    if (slideChanged) {
      _indexSlideData();
    }

    final shouldRestart = slideChanged ||
        oldWidget.revealedStep != widget.revealedStep ||
        oldWidget.replayTrigger != widget.replayTrigger ||
        oldWidget.enableAnimations != widget.enableAnimations ||
        oldWidget.isThumbnail != widget.isThumbnail;

    if (shouldRestart) {
      _startEntranceAnimation();
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _indexSlideData() {
    final map = <String, List<SlideAnimationStep>>{};
    for (final step in widget.slide.animations) {
      map.putIfAbsent(step.shapeId, () => []).add(step);
    }
    _stepsByShape = map;

    int fg = 0;
    _foregroundIndexMap = [
      for (final el in widget.slide.elements)
        el.isBackgroundDecor ? -1 : fg++,
    ];
    _foregroundCount = fg;
  }

  bool get _animationsActive {
    final disableSystem = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return widget.enableAnimations && !widget.isThumbnail && !disableSystem;
  }

  void _startEntranceAnimation() {
    _delayTimer?.cancel();

    if (!_animationsActive) {
      _controller.value = 1.0;
      return;
    }

    if (widget.slide.animations.isNotEmpty && widget.revealedStep != null) {
      int maxMs = 420;
      for (final step in widget.slide.animations) {
        if (step.clickGroup == widget.revealedStep) {
          final end = step.delayMs + step.durationMs;
          if (end > maxMs) maxMs = end;
        }
      }
      _controller.duration = Duration(milliseconds: maxMs.clamp(120, 2400));
    } else {
      _controller.duration = const Duration(milliseconds: 480);
    }

    if (widget.entranceDelay > Duration.zero) {
      _controller.value = 0.0;
      _delayTimer = Timer(widget.entranceDelay, () {
        if (mounted) _controller.forward(from: 0.0);
      });
    } else {
      _controller.forward(from: 0.0);
    }
  }

  List<SlideAnimationStep>? _stepsForElement(SlideElement elem) {
    if (elem.shapeId != null) {
      final direct = _stepsByShape[elem.shapeId!];
      if (direct != null && direct.isNotEmpty) return direct;
    }
    if (elem.groupShapeId != null) {
      final grp = _stepsByShape[elem.groupShapeId!];
      if (grp != null && grp.isNotEmpty) return grp;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasW = constraints.maxWidth;
        final canvasH = constraints.maxHeight;

        const referenceWidth = 960.0;
        final scale = (canvasW / referenceWidth) * widget.fontScale;
        final bgCacheW = widget.isThumbnail
            ? 360
            : (canvasW * dpr).round().clamp(128, 1600);

        return Container(
          width: canvasW,
          height: canvasH,
          color: widget.slide.backgroundColor ?? Colors.white,
          child: Stack(
            clipBehavior: Clip.antiAlias,
            children: [
              if (widget.slide.backgroundImage != null)
                Positioned.fill(
                  child: Image.memory(
                    widget.slide.backgroundImage!,
                    fit: BoxFit.cover,
                    cacheWidth: bgCacheW,
                    gaplessPlayback: true,
                    filterQuality: widget.isThumbnail
                        ? FilterQuality.low
                        : FilterQuality.medium,
                  ),
                ),

              for (int i = 0; i < widget.slide.elements.length; i++)
                _buildSlideElement(
                  context,
                  widget.slide.elements[i],
                  canvasW,
                  canvasH,
                  scale,
                  dpr,
                  i,
                ),

              if (widget.slide.elements.isEmpty)
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.all(24 * scale),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.slide.title,
                          style: TextStyle(
                            fontSize: 24 * scale,
                            fontWeight: FontWeight.bold,
                            color: widget.themeColors['dk1'] ?? Colors.black87,
                          ),
                        ),
                        SizedBox(height: 16 * scale),
                        for (final point in widget.slide.bulletPoints)
                          Padding(
                            padding: EdgeInsets.only(bottom: 8 * scale),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('• ', style: TextStyle(fontSize: 16 * scale)),
                                Expanded(
                                  child: Text(
                                    point,
                                    style: TextStyle(fontSize: 16 * scale),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSlideElement(
    BuildContext context,
    SlideElement elem,
    double canvasW,
    double canvasH,
    double scale,
    double dpr,
    int index,
  ) {
    final left = elem.x * canvasW;
    final top = elem.y * canvasH;
    final width = elem.width * canvasW;
    final height = elem.height * canvasH;

    if (width <= 0 || height <= 0) return const SizedBox.shrink();

    Widget innerContent;

    if (elem is SlidePictureElement) {
      final cacheW = widget.isThumbnail
          ? 360
          : (width * dpr).round().clamp(128, 1600);
      innerContent = Transform.rotate(
        angle: elem.rotation * (pi / 180.0),
        alignment: Alignment.center,
        child: GestureDetector(
          onTap: () => widget.onImageTap?.call(elem.imageBytes),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(elem.borderRadius * scale),
            child: Image.memory(
              elem.imageBytes,
              fit: BoxFit.contain,
              cacheWidth: cacheW,
              gaplessPlayback: true,
              filterQuality:
                  widget.isThumbnail ? FilterQuality.low : FilterQuality.medium,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
      );
    } else if (elem is SlideShapeElement) {
      final padH = (width * 0.03).clamp(2.0, 10.0);
      final padV = (height * 0.03).clamp(2.0, 8.0);
      final innerW = max(1.0, width - padH * 2);

      innerContent = Transform.rotate(
        angle: elem.rotation * (pi / 180.0),
        alignment: Alignment.center,
        child: Container(
          decoration: BoxDecoration(
            color: elem.fillColor,
            border: elem.borderColor != null && elem.borderWidth > 0
                ? Border.all(
                    color: elem.borderColor!,
                    width: (elem.borderWidth * scale).clamp(0.5, 8.0),
                  )
                : null,
            borderRadius: elem.isCircle
                ? null
                : BorderRadius.circular(elem.borderRadius * scale),
            shape: elem.isCircle ? BoxShape.circle : BoxShape.rectangle,
          ),
          alignment: elem.verticalAlignment,
          padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
          child: elem.paragraphs.isEmpty
              ? const SizedBox.shrink()
              : ClipRect(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: elem.verticalAlignment,
                    child: SizedBox(
                      width: innerW,
                      child: _buildShapeTextContent(elem, scale),
                    ),
                  ),
                ),
        ),
      );
    } else if (elem is SlideTableElement) {
      innerContent = _buildTable(elem, scale);
    } else {
      return const SizedBox.shrink();
    }

    Widget finalChild = innerContent;

    if (widget.slide.animations.isNotEmpty && widget.revealedStep != null) {
      finalChild = _wrapWithTimingStep(
        elem: elem,
        child: innerContent,
        width: width,
        height: height,
        scale: scale,
      );
    } else if (_animationsActive && !elem.isBackgroundDecor) {
      final fgIdx = _foregroundIndexMap[index];
      final totalFg = max(1, _foregroundCount);
      final stepWindow = totalFg > 1 ? 0.45 / max(1, totalFg - 1) : 0.0;
      final start = (fgIdx * min<double>(0.08, stepWindow)).clamp(0.0, 0.55).toDouble();
      final end = (start + 0.45).clamp(0.15, 1.0).toDouble();

      finalChild = AnimatedBuilder(
        animation: _controller,
        child: innerContent,
        builder: (context, child) {
          final t = Curves.easeOutCubic.transform(
            Interval(start, end).transform(_controller.value),
          );
          return Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, 8 * (1.0 - t) * scale),
              child: child,
            ),
          );
        },
      );
    }

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: finalChild,
    );
  }

  Widget _wrapWithTimingStep({
    required SlideElement elem,
    required Widget child,
    required double width,
    required double height,
    required double scale,
  }) {
    final steps = _stepsForElement(elem);
    if (steps == null || steps.isEmpty) return child;

    final currentStep = widget.revealedStep!;
    final entrance = steps.where((s) => s.isEntrance).firstOrNull;
    final exit = steps.where((s) => s.isExit).firstOrNull;
    final emphasis = steps
        .where((s) => s.isEmphasis && s.clickGroup == currentStep)
        .firstOrNull;

    if (entrance != null && currentStep < entrance.clickGroup) {
      return IgnorePointer(
        child: Opacity(opacity: 0.0, child: child),
      );
    }

    if (exit != null && currentStep > exit.clickGroup) {
      return IgnorePointer(
        child: Opacity(opacity: 0.0, child: child),
      );
    }

    if (exit != null && currentStep == exit.clickGroup) {
      if (!_animationsActive) {
        return IgnorePointer(
          child: Opacity(opacity: 0.0, child: child),
        );
      }
      final totalMs = max(120, _controller.duration?.inMilliseconds ?? 420);
      final start = (exit.delayMs / totalMs).clamp(0.0, 0.85);
      final end = ((exit.delayMs + exit.durationMs) / totalMs)
          .clamp(start + 0.05, 1.0);

      return AnimatedBuilder(
        animation: _controller,
        child: child,
        builder: (context, builtChild) {
          final rawT = Interval(start, end).transform(_controller.value);
          final outT = (1.0 - Curves.easeInCubic.transform(rawT)).clamp(0.0, 1.0);
          return _applyAnimationEffect(
            child: builtChild!,
            effect: exit.effect,
            direction: exit.direction,
            t: outT,
            width: width,
            height: height,
            scale: scale,
          );
        },
      );
    }

    if (entrance != null && currentStep == entrance.clickGroup) {
      if (!_animationsActive) return child;
      final totalMs = max(120, _controller.duration?.inMilliseconds ?? 420);
      final start = (entrance.delayMs / totalMs).clamp(0.0, 0.85);
      final end = ((entrance.delayMs + entrance.durationMs) / totalMs)
          .clamp(start + 0.05, 1.0);

      return AnimatedBuilder(
        animation: _controller,
        child: child,
        builder: (context, builtChild) {
          final rawT = Interval(start, end).transform(_controller.value);
          final t = Curves.easeOutCubic.transform(rawT).clamp(0.0, 1.0);
          return _applyAnimationEffect(
            child: builtChild!,
            effect: entrance.effect,
            direction: entrance.direction,
            t: t,
            width: width,
            height: height,
            scale: scale,
          );
        },
      );
    }

    if (emphasis != null && _animationsActive) {
      return AnimatedBuilder(
        animation: _controller,
        child: child,
        builder: (context, builtChild) {
          final pulse = sin(_controller.value * pi) * 0.07;
          return Transform.scale(
            scale: 1.0 + pulse,
            alignment: Alignment.center,
            child: builtChild,
          );
        },
      );
    }

    return child;
  }

  Widget _applyAnimationEffect({
    required Widget child,
    required SlideAnimationEffect effect,
    required SlideAnimationDirection direction,
    required double t,
    required double width,
    required double height,
    required double scale,
  }) {
    switch (effect) {
      case SlideAnimationEffect.appear:
        return Opacity(opacity: t > 0.05 ? 1.0 : 0.0, child: child);
      case SlideAnimationEffect.fade:
        return Opacity(opacity: t, child: child);
      case SlideAnimationEffect.flyIn:
      case SlideAnimationEffect.floatIn:
        final dist = effect == SlideAnimationEffect.floatIn
            ? 22.0 * scale
            : 56.0 * scale;
        final offset = switch (direction) {
          SlideAnimationDirection.fromLeft => Offset(-dist * (1.0 - t), 0),
          SlideAnimationDirection.fromRight => Offset(dist * (1.0 - t), 0),
          SlideAnimationDirection.fromTop => Offset(0, -dist * (1.0 - t)),
          SlideAnimationDirection.fromBottom ||
          SlideAnimationDirection.center =>
            Offset(0, dist * (1.0 - t)),
        };
        return Opacity(
          opacity: (t * 1.4).clamp(0.0, 1.0),
          child: Transform.translate(offset: offset, child: child),
        );
      case SlideAnimationEffect.wipe:
        final AlignmentGeometry align = switch (direction) {
          SlideAnimationDirection.fromRight => Alignment.centerRight,
          SlideAnimationDirection.fromTop => Alignment.topCenter,
          SlideAnimationDirection.fromBottom => Alignment.bottomCenter,
          _ => Alignment.centerLeft,
        };
        final isVertical = direction == SlideAnimationDirection.fromTop ||
            direction == SlideAnimationDirection.fromBottom;
        return ClipRect(
          child: Align(
            alignment: align,
            widthFactor: isVertical ? 1.0 : max(0.001, t),
            heightFactor: isVertical ? max(0.001, t) : 1.0,
            child: child,
          ),
        );
      case SlideAnimationEffect.split:
        return ClipRect(
          child: Align(
            alignment: Alignment.center,
            widthFactor: max(0.001, t),
            child: Opacity(opacity: (t * 1.2).clamp(0.0, 1.0), child: child),
          ),
        );
      case SlideAnimationEffect.zoom:
        return Opacity(
          opacity: t,
          child: Transform.scale(
            scale: 0.72 + (0.28 * t),
            alignment: Alignment.center,
            child: child,
          ),
        );
      case SlideAnimationEffect.emphasis:
        final pulse = sin(t * pi) * 0.07;
        return Transform.scale(
          scale: 1.0 + pulse,
          alignment: Alignment.center,
          child: child,
        );
    }
  }

  Widget _buildShapeTextContent(SlideShapeElement elem, double scale) {
    if (elem.paragraphs.isEmpty) return const SizedBox.shrink();

    final isDarkFill =
        elem.fillColor != null && elem.fillColor!.computeLuminance() < 0.4;
    final defaultColor =
        isDarkFill ? Colors.white : (widget.themeColors['dk1'] ?? Colors.black87);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final para in elem.paragraphs)
          Padding(
            padding: EdgeInsets.only(
              top: para.spaceBefore * scale,
              bottom: para.spaceAfter * scale,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (para.isBullet)
                  Padding(
                    padding: EdgeInsetsDirectional.only(end: 4 * scale, top: 1 * scale),
                    child: Text(
                      para.bulletChar ?? '•',
                      style: TextStyle(
                        fontSize: (para.spans.firstOrNull?.fontSize ?? 14.0) * scale,
                        color: para.spans.firstOrNull?.fontColor ?? defaultColor,
                      ),
                    ),
                  ),
                Expanded(
                  child: RichText(
                    textAlign: para.alignment,
                    text: TextSpan(
                      children: [
                        for (final span in para.spans)
                          _buildTextSpan(span, scale, defaultColor),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  TextSpan _buildTextSpan(SlideTextSpan span, double scale, Color defaultColor) {
    final effectiveFontSize = (span.fontSize * scale).clamp(6.0, 72.0);
    final fontColor = span.fontColor ?? defaultColor;

    final baseStyle = TextStyle(
      fontSize: effectiveFontSize,
      color: fontColor,
      fontWeight: span.bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: span.italic ? FontStyle.italic : FontStyle.normal,
      decoration: span.underline ? TextDecoration.underline : TextDecoration.none,
      fontFamily: span.fontFamily,
      height: 1.25,
    );

    if (widget.searchQuery.isEmpty ||
        !EncodingUtils.searchMatches(span.text, widget.searchQuery)) {
      return TextSpan(text: span.text, style: baseStyle);
    }

    // Highlighting matching search terms
    final cleanQuery =
        EncodingUtils.removeDiacritics(widget.searchQuery.toLowerCase());
    final cleanText = EncodingUtils.removeDiacritics(span.text.toLowerCase());
    final childSpans = <TextSpan>[];
    int start = 0;

    while (start < span.text.length) {
      final index = cleanText.indexOf(cleanQuery, start);
      if (index == -1) {
        childSpans.add(TextSpan(text: span.text.substring(start)));
        break;
      }
      if (index > start) {
        childSpans.add(TextSpan(text: span.text.substring(start, index)));
      }
      final matchEnd = index + cleanQuery.length;
      childSpans.add(
        TextSpan(
          text: span.text.substring(index, matchEnd),
          style: const TextStyle(
            backgroundColor: Colors.yellow,
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
      start = matchEnd;
    }

    return TextSpan(style: baseStyle, children: childSpans);
  }

  Widget _buildTable(SlideTableElement elem, double scale) {
    if (elem.rows.isEmpty) return const SizedBox.shrink();

    return Table(
      border: TableBorder.all(
        color: Colors.grey.withValues(alpha: 0.5),
        width: (1.0 * scale).clamp(0.5, 3.0),
      ),
      children: [
        for (final row in elem.rows)
          TableRow(
            children: [
              for (final cell in row)
                Container(
                  color: cell.fillColor,
                  padding: EdgeInsets.all(4 * scale),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final p in cell.paragraphs)
                        RichText(
                          textAlign: p.alignment,
                          text: TextSpan(
                            children: [
                              for (final span in p.spans)
                                _buildTextSpan(
                                  span,
                                  scale,
                                  cell.fillColor != null &&
                                          cell.fillColor!.computeLuminance() < 0.4
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// Fullscreen immersive Slideshow Screen (Diaporama) with directional slide transitions,
/// step-by-step `<p:timing>` entrance animations, replay/rotate controls, and playback progress bar.
class PresentationSlideshowScreen extends StatefulWidget {
  const PresentationSlideshowScreen({
    super.key,
    required this.deck,
    this.filePath = '',
    this.initialSlideIndex = 0,
    required this.title,
    this.enableAnimations = true,
  });

  final PresentationDeck deck;
  final String filePath;
  final int initialSlideIndex;
  final String title;
  final bool enableAnimations;

  @override
  State<PresentationSlideshowScreen> createState() =>
      _PresentationSlideshowScreenState();
}

class _PresentationSlideshowScreenState
    extends State<PresentationSlideshowScreen>
    with SingleTickerProviderStateMixin {
  static const int _autoPlaySlideSeconds = 4;
  static const int _autoPlayStepMs = 2200;

  late int _currentIndex;
  int _revealedStep = 0;
  int _replayTrigger = 0;
  bool _navigatingForward = true;
  bool _wasSlideChange = false;
  bool _showControls = true;
  bool _isAutoPlaying = false;
  bool _isLandscape = false;
  bool _enteredDesktopFullScreen = false;
  Timer? _hideControlsTimer;
  late final AnimationController _autoPlayProgressController;

  bool get _isDesktop =>
      !Platform.environment.containsKey('FLUTTER_TEST') &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  PresentationSlide get _currentSlide => widget.deck.slides[_currentIndex];

  @override
  void initState() {
    super.initState();
    _currentIndex =
        widget.initialSlideIndex.clamp(0, widget.deck.slides.length - 1);
    _autoPlayProgressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: _autoPlaySlideSeconds),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && _isAutoPlaying && mounted) {
          _advanceStepOrNextSlide(fromAutoPlay: true);
        }
      });
    if (_isDesktop) {
      _enterDesktopFullScreenIfNeeded();
      final ht = HandTrackingService.instance;
      if (ht.isSupported) {
        ht.attach((cmd) {
          if (!mounted) return;
          if (cmd is NextStepCommand) _advanceStepOrNextSlide();
          if (cmd is PrevStepCommand) _stepBackOrPrevSlide();
        });
      }
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    _scheduleHideControls();
  }

  Future<void> _enterDesktopFullScreenIfNeeded() async {
    final alreadyFull = await windowManager.isFullScreen();
    if (!alreadyFull && mounted) {
      _enteredDesktopFullScreen = true;
      await windowManager.setFullScreen(true);
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _autoPlayProgressController.dispose();
    if (_isDesktop) {
      HandTrackingService.instance.detach();
      if (_enteredDesktopFullScreen) {
        windowManager.setFullScreen(false);
      }
    } else {
      SystemChrome.setPreferredOrientations([]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHideControls();
  }

  void _restartAutoPlayCountdown() {
    if (!_isAutoPlaying) return;
    final hasMoreSteps =
        widget.enableAnimations &&
        _revealedStep < _currentSlide.animationClickStepCount;
    _autoPlayProgressController.duration = Duration(
      milliseconds: hasMoreSteps ? _autoPlayStepMs : _autoPlaySlideSeconds * 1000,
    );
    _autoPlayProgressController.forward(from: 0.0);
  }

  void _advanceStepOrNextSlide({bool fromAutoPlay = false}) {
    final totalSteps =
        widget.enableAnimations ? _currentSlide.animationClickStepCount : 0;
    if (_revealedStep < totalSteps) {
      setState(() {
        _wasSlideChange = false;
        _revealedStep++;
      });
      _restartAutoPlayCountdown();
    } else if (_currentIndex < widget.deck.slides.length - 1) {
      setState(() {
        _navigatingForward = true;
        _wasSlideChange = true;
        _currentIndex++;
        _revealedStep = 0;
      });
      _restartAutoPlayCountdown();
    } else if (fromAutoPlay && _isAutoPlaying) {
      setState(() {
        _navigatingForward = true;
        _wasSlideChange = true;
        _currentIndex = 0;
        _revealedStep = 0;
      });
      _restartAutoPlayCountdown();
    }
    if (!fromAutoPlay && _showControls) _scheduleHideControls();
  }

  void _stepBackOrPrevSlide() {
    if (_revealedStep > 0) {
      setState(() {
        _wasSlideChange = false;
        _revealedStep--;
      });
      _restartAutoPlayCountdown();
    } else if (_currentIndex > 0) {
      final prevIdx = _currentIndex - 1;
      final prevSteps = widget.enableAnimations
          ? widget.deck.slides[prevIdx].animationClickStepCount
          : 0;
      setState(() {
        _navigatingForward = false;
        _wasSlideChange = true;
        _currentIndex = prevIdx;
        _revealedStep = prevSteps;
      });
      _restartAutoPlayCountdown();
    }
    if (_showControls) _scheduleHideControls();
  }

  void _jumpToSlideIndex(int targetIndex) {
    final clamped = targetIndex.clamp(0, widget.deck.slides.length - 1);
    if (clamped == _currentIndex) return;
    setState(() {
      _navigatingForward = clamped > _currentIndex;
      _wasSlideChange = true;
      _currentIndex = clamped;
      _revealedStep = 0;
    });
    _restartAutoPlayCountdown();
    if (_showControls) _scheduleHideControls();
  }

  void _replayCurrentSlide() {
    HapticFeedback.selectionClick();
    setState(() {
      _wasSlideChange = false;
      _revealedStep = _currentSlide.animationClickStepCount > 0 && _revealedStep > 0
          ? 1
          : 0;
      _replayTrigger++;
    });
    _restartAutoPlayCountdown();
    if (_showControls) _scheduleHideControls();
  }

  Future<void> _toggleLandscape() async {
    HapticFeedback.selectionClick();
    final nextLandscape = !_isLandscape;
    setState(() => _isLandscape = nextLandscape);
    if (nextLandscape) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations([]);
    }
    if (_showControls) _scheduleHideControls();
  }

  void _toggleAutoPlay() {
    setState(() {
      _isAutoPlaying = !_isAutoPlaying;
      if (_isAutoPlaying) {
        _restartAutoPlayCountdown();
      } else {
        _autoPlayProgressController.stop();
        _autoPlayProgressController.value = 0.0;
      }
    });
    if (_showControls) _scheduleHideControls();
  }

  Widget _buildSlideTransition(
    Widget child,
    Animation<double> animation,
    PresentationSlide targetSlide,
  ) {
    final isIncoming = child.key == ValueKey('slideshow_slide_$_currentIndex');
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeInOutCubic,
    );

    Offset directionalOffset(Offset forwardBegin) {
      final begin = _navigatingForward ? forwardBegin : -forwardBegin;
      final effectiveBegin = isIncoming ? begin : -begin;
      return effectiveBegin;
    }

    switch (targetSlide.transitionType) {
      case SlideTransitionType.pushLeft:
        return SlideTransition(
          position: Tween<Offset>(
            begin: directionalOffset(const Offset(1.0, 0.0)),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      case SlideTransitionType.pushRight:
        return SlideTransition(
          position: Tween<Offset>(
            begin: directionalOffset(const Offset(-1.0, 0.0)),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      case SlideTransitionType.pushUp:
        return SlideTransition(
          position: Tween<Offset>(
            begin: directionalOffset(const Offset(0.0, 1.0)),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      case SlideTransitionType.pushDown:
        return SlideTransition(
          position: Tween<Offset>(
            begin: directionalOffset(const Offset(0.0, -1.0)),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      case SlideTransitionType.cover:
        if (!isIncoming) return child;
        final coverBegin = _navigatingForward
            ? const Offset(1.0, 0.0)
            : const Offset(-1.0, 0.0);
        return SlideTransition(
          position: Tween<Offset>(begin: coverBegin, end: Offset.zero)
              .animate(curved),
          child: child,
        );
      case SlideTransitionType.uncover:
        if (isIncoming) return child;
        final uncoverExit = _navigatingForward
            ? const Offset(-1.0, 0.0)
            : const Offset(1.0, 0.0);
        return SlideTransition(
          position: Tween<Offset>(begin: uncoverExit, end: Offset.zero)
              .animate(curved),
          child: child,
        );
      case SlideTransitionType.wipe:
        if (!isIncoming) return child;
        return AnimatedBuilder(
          animation: curved,
          child: child,
          builder: (context, builtChild) {
            return ClipRect(
              child: Align(
                alignment: _navigatingForward
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                widthFactor: max(0.001, curved.value),
                child: builtChild,
              ),
            );
          },
        );
      case SlideTransitionType.split:
        if (!isIncoming) return child;
        return AnimatedBuilder(
          animation: curved,
          child: child,
          builder: (context, builtChild) {
            return ClipRect(
              child: Align(
                alignment: Alignment.center,
                widthFactor: max(0.001, curved.value),
                child: builtChild,
              ),
            );
          },
        );
      case SlideTransitionType.zoom:
        return ScaleTransition(
          scale: Tween<double>(
            begin: isIncoming ? 0.88 : 1.05,
            end: 1.0,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      case SlideTransitionType.cut:
        return child;
      case SlideTransitionType.fade:
      case SlideTransitionType.none:
        return FadeTransition(opacity: animation, child: child);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final slide = _currentSlide;
    final totalSlides = widget.deck.slides.length;
    final totalSteps =
        widget.enableAnimations ? slide.animationClickStepCount : 0;
    final transitionDuration = slide.transitionType == SlideTransitionType.cut
        ? Duration.zero
        : slide.transitionType == SlideTransitionType.none
            ? const Duration(milliseconds: 180)
            : Duration(milliseconds: slide.transitionDurationMs);
    final entranceDelay = _wasSlideChange && transitionDuration.inMilliseconds > 0
        ? Duration(
            milliseconds: (transitionDuration.inMilliseconds * 0.4).round(),
          )
        : Duration.zero;
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    final canStepBack = _currentIndex > 0 || _revealedStep > 0;
    final canStepNext =
        _currentIndex < totalSlides - 1 || _revealedStep < totalSteps;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            _advanceStepOrNextSlide,
        const SingleActivator(LogicalKeyboardKey.pageDown):
            _advanceStepOrNextSlide,
        const SingleActivator(LogicalKeyboardKey.space):
            _advanceStepOrNextSlide,
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            _stepBackOrPrevSlide,
        const SingleActivator(LogicalKeyboardKey.pageUp):
            _stepBackOrPrevSlide,
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(_currentIndex),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity;
          if (v == null) return;
          if (v < -200) {
            _jumpToSlideIndex(_currentIndex + 1);
          } else if (v > 200) {
            _jumpToSlideIndex(_currentIndex - 1);
          }
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Slide Canvas clipped strictly to aspect ratio
            Center(
              child: AspectRatio(
                aspectRatio: widget.deck.aspectRatio,
                child: ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AnimatedSwitcher(
                        duration: transitionDuration,
                        layoutBuilder: (currentChild, previousChildren) {
                          if (slide.transitionType ==
                              SlideTransitionType.uncover) {
                            return Stack(
                              alignment: Alignment.center,
                              children: [
                                ?currentChild,
                                ...previousChildren,
                              ],
                            );
                          }
                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              ...previousChildren,
                              ?currentChild,
                            ],
                          );
                        },
                        transitionBuilder: (child, animation) =>
                            _buildSlideTransition(child, animation, slide),
                        child: KeyedSubtree(
                          key: ValueKey('slideshow_slide_$_currentIndex'),
                          child: SlideCanvasView(
                            slide: slide,
                            aspectRatio: widget.deck.aspectRatio,
                            themeColors: widget.deck.themeColors,
                            enableAnimations: widget.enableAnimations,
                            revealedStep: _revealedStep,
                            replayTrigger: _replayTrigger,
                            entranceDelay: entranceDelay,
                          ),
                        ),
                      ),
                      if (_isAutoPlaying)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 3,
                          child: AnimatedBuilder(
                            animation: _autoPlayProgressController,
                            builder: (context, _) => LinearProgressIndicator(
                              value: _autoPlayProgressController.value,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.2),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                              minHeight: 3,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            // Tap navigation zones (left side = previous, right side = next)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 60,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _stepBackOrPrevSlide,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 60,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _advanceStepOrNextSlide,
                child: const SizedBox.expand(),
              ),
            ),

            // Top Overlay Bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !_showControls,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 220),
                  offset: _showControls ? Offset.zero : const Offset(0, -1),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _showControls ? 1.0 : 0.0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 36, 12, 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.82),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: l10n.exitSlideshow,
                            icon: const Icon(
                              Icons.arrow_back_rounded,
                              color: Colors.white,
                            ),
                            onPressed: () =>
                                Navigator.of(context).pop(_currentIndex),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              EncodingUtils.cleanDisplayName(widget.title),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (totalSteps > 0)
                            Container(
                              margin: const EdgeInsetsDirectional.only(end: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                l10n.stepXOfY(_revealedStep, totalSteps),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          IconButton(
                            tooltip: l10n.replayAnimation,
                            icon: const Icon(
                              Icons.replay_rounded,
                              color: Colors.white,
                            ),
                            onPressed: _replayCurrentSlide,
                          ),
                          if (_isDesktop)
                            IconButton(
                              tooltip: 'Switch to Presenter View',
                              icon: const Icon(
                                Icons.co_present_rounded,
                                color: Colors.white,
                              ),
                              onPressed: () async {
                                final idx = _currentIndex;
                                if (_enteredDesktopFullScreen) {
                                  _enteredDesktopFullScreen = false;
                                  await windowManager.setFullScreen(false);
                                }
                                if (!context.mounted) return;
                                await Navigator.of(context)
                                    .pushReplacement<int, int>(
                                  MaterialPageRoute<int>(
                                    builder: (_) => PresenterViewScreen(
                                      deck: widget.deck,
                                      filePath: widget.filePath,
                                      title: widget.title,
                                      initialSlideIndex: idx,
                                      enableAnimations: widget.enableAnimations,
                                    ),
                                  ),
                                );
                              },
                            )
                          else
                            IconButton(
                              tooltip: l10n.rotateScreen,
                              icon: Icon(
                                _isLandscape
                                    ? Icons.screen_lock_rotation_rounded
                                    : Icons.screen_rotation_rounded,
                                color: Colors.white,
                              ),
                              onPressed: _toggleLandscape,
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              '${_currentIndex + 1} / $totalSlides',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Bottom Overlay Controls
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !_showControls,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 220),
                  offset: _showControls ? Offset.zero : const Offset(0, 1),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _showControls ? 1.0 : 0.0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.85),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: SafeArea(
                        top: false,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (totalSlides > 1) ...[
                              PageScrubber(
                                darkOverlayStyle: true,
                                currentPage: _currentIndex + 1,
                                totalPages: totalSlides,
                                labelBuilder: (p) =>
                                    l10n.slideXOfY(p, totalSlides),
                                subtitleBuilder: (p) =>
                                    EncodingUtils.cleanDisplayName(
                                  widget.deck.slides[p - 1].title,
                                ),
                                onPageSelected: (p) => _jumpToSlideIndex(p - 1),
                              ),
                              const SizedBox(height: 6),
                            ],
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                IconButton(
                                  tooltip: l10n.previousPage,
                                  icon: Transform.flip(
                                    flipX: isRtl,
                                    child: const Icon(
                                      Icons.skip_previous_rounded,
                                      size: 32,
                                      color: Colors.white,
                                    ),
                                  ),
                                  onPressed:
                                      canStepBack ? _stepBackOrPrevSlide : null,
                                ),
                                FilledButton.tonalIcon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor:
                                        Colors.white.withValues(alpha: 0.25),
                                    foregroundColor: Colors.white,
                                  ),
                                  icon: Icon(
                                    _isAutoPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                  ),
                                  label: Text(
                                    _isAutoPlaying ? l10n.pause : l10n.autoPlay,
                                  ),
                                  onPressed: _toggleAutoPlay,
                                ),
                                IconButton(
                                  tooltip: l10n.nextPage,
                                  icon: Transform.flip(
                                    flipX: isRtl,
                                    child: const Icon(
                                      Icons.skip_next_rounded,
                                      size: 32,
                                      color: Colors.white,
                                    ),
                                  ),
                                  onPressed: canStepNext
                                      ? () => _advanceStepOrNextSlide()
                                      : null,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
      ),
    );
  }
}
