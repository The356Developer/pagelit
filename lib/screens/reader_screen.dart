import 'dart:async';
import 'dart:io';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../l10n/app_localizations.dart';
import '../services/device_pdfs.dart';
import '../services/encoding_utils.dart';
import '../services/gallery_saver.dart';
import '../services/gemini_share_service.dart';
import '../services/pdf_toc_extractor.dart';
import '../services/reading_prefs.dart';
import '../services/reading_progress.dart';
import '../theme/app_theme.dart';
import '../widgets/page_scrubber.dart';
import '../widgets/pdf_glyph.dart';
import 'settings_screen.dart';

/// Colours offered for new and selected annotations.
const _annotationPalette = [
  Colors.yellow,
  Colors.orange,
  Colors.green,
  Colors.cyan,
  Colors.pink,
  Colors.purple,
  Colors.red,
];

/// Tool button size. 48px is Material's minimum comfortable touch target.
const _toolButtonSize = 48.0;

/// The PDF reader: viewing, annotating, sharing and saving pages to the gallery.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.filePath, required this.title});

  final String filePath;
  final String title;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

enum _Tool { pan, highlight, underline, strikethrough, squiggly, comment }

class _ReaderScreenState extends State<ReaderScreen> {
  final PdfViewerController _controller = PdfViewerController();
  final GlobalKey _viewerKey = GlobalKey();
  final TextEditingController _commentInput = TextEditingController();
  final TextEditingController _searchFieldController = TextEditingController();
  final TextEditingController _jumpInput = TextEditingController();

  /// Annotations added in this session, newest last (for undo).
  final List<Annotation> _addedAnnotations = [];

  _Tool _tool = _Tool.pan;
  Color _color = ReadingPrefs.annotationColor.value;
  final ValueNotifier<int> _pageNumberNotifier = ValueNotifier<int>(1);
  int get _pageNumber => _pageNumberNotifier.value;
  int _pageCount = 0;
  bool _isLoaded = false;
  bool _isBusy = false;
  bool _isSearchOpen = false;
  int _quarterTurns = 0;
  String? _password;
  PdfTocResult? _tocResult;
  Future<PdfTocResult>? _tocFuture;
  bool _hasRestoredInitialPosition = false;

  /// Annotation currently selected in pan mode (offered for recolour/delete).
  Annotation? _selectedAnnotation;

  /// Full-screen reading: no app bar, no toolbar, no system bars.
  bool _immersive = false;
  PdfTextSearchResult? _searchResult;
  Timer? _progressDebounce;

  static const List<Color> _palette = [
    Colors.yellow,
    Colors.orange,
    Colors.green,
    Colors.cyan,
    Colors.pink,
    Colors.purple,
    Colors.red,
  ];

  final GlobalKey<SfPdfViewerState> _pdfViewerStateKey =
      GlobalKey<SfPdfViewerState>();
  String? _selectedText;
  Rect? _selectedRegion;

  late SfPdfViewer _viewer;

  void _initViewer() {
    _viewer = SfPdfViewer.file(
      File(widget.filePath),
      key: _pdfViewerStateKey,
      controller: _controller,
      password: _password,
      pageLayoutMode: ReadingPrefs.layoutMode.value,
      scrollDirection: ReadingPrefs.scrollDirection.value,
      canShowScrollHead: false,
      canShowScrollStatus: false,
      canShowPaginationDialog: false,
      canShowTextSelectionMenu: false,
      enableDoubleTapZooming: true,
      maxZoomLevel: 3.0,
      pageSpacing: 6,
      initialPageNumber: _pageNumberNotifier.value,
      onTextSelectionChanged: _onTextSelectionChanged,
      onDocumentLoaded: (details) {
        _controller.annotationSettings.author = 'Pagelit';
        _applyColorToSettings(_color);
        final tier1 = PdfTocExtractor.extractFromBookmarks(details.document);
        setState(() {
          _isLoaded = true;
          _pageCount = _controller.pageCount;
          if (tier1.isNotEmpty) {
            _tocResult = tier1;
          }
        });
        if (!_hasRestoredInitialPosition) {
          _hasRestoredInitialPosition = true;
          _restorePosition();
        }
      },
      onDocumentLoadFailed: _handleLoadFailed,
      onHyperlinkClicked: (details) async {
        final raw = details.uri;
        final uri = Uri.tryParse(raw);
        if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'mailto')) {
          try {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } catch (_) {}
        }
      },
      onPageChanged: (details) {
        _pageNumberNotifier.value = details.newPageNumber;
        if (_selectedText != null || _selectedRegion != null) {
          setState(() {
            _selectedText = null;
            _selectedRegion = null;
          });
        }
        _scheduleProgressSave();
      },
      onAnnotationAdded: _onAnnotationAdded,
      onAnnotationRemoved: _onAnnotationRemoved,
      onAnnotationSelected: _onAnnotationSelected,
      onAnnotationDeselected: _onAnnotationDeselected,
    );
  }

  void _onReadingPrefLayoutOrScrollChanged() {
    if (!mounted) return;
    setState(() {
      _initViewer();
    });
  }

  Future<PdfTocResult> _startBackgroundTocScan() {
    if (_tocFuture != null) return _tocFuture!;
    Future<PdfTocResult> runScan() async {
      try {
        final res = await PdfTocExtractor.extractFromFile(
          widget.filePath,
          password: _password,
        );
        if (mounted) {
          setState(() => _tocResult = res);
        }
        return res;
      } catch (_) {
        if (mounted) {
          setState(() => _tocResult = PdfTocResult.empty);
        }
        return PdfTocResult.empty;
      }
    }

    _tocFuture = runScan();
    return _tocFuture!;
  }

  void _handleLoadFailed(PdfDocumentLoadFailedDetails details) {
    if (!mounted) return;
    final err = details.error.toLowerCase();
    if (err.contains('password') || err.contains('protect') || err.contains('encrypt')) {
      _promptPassword();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.couldNotOpenPdf(details.error))),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _promptPassword() async {
    final l10n = context.l10n;
    final passwordController = TextEditingController();
    final entered = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(l10n.passwordProtected),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.passwordPrompt),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              autofocus: true,
              obscureText: true,
              decoration: InputDecoration(
                hintText: l10n.passwordHint,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (val) => Navigator.of(context).pop(val),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(passwordController.text),
            child: Text(l10n.unlock),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (entered == null || entered.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _password = entered;
      _isLoaded = false;
      _tocResult = null;
      _tocFuture = null;
      _initViewer();
    });
  }

  void _openBookmarksSheet() {
    if (!_isLoaded) return;
    final pendingFuture =
        _tocResult != null ? null : (_tocFuture ?? _startBackgroundTocScan());
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _OutlineSheet(
        initialResult: _tocResult,
        pendingFuture: pendingFuture,
        currentPage: _pageNumberNotifier.value,
        onSelect: _jumpToTocEntry,
      ),
    );
  }

  void _jumpToTocEntry(PdfTocEntry entry) {
    if (entry.bookmark != null) {
      try {
        final hasDirectDest = entry.bookmark!.destination != null ||
            entry.bookmark!.namedDestination?.destination != null;
        if (hasDirectDest) {
          _controller.jumpToBookmark(entry.bookmark!);
          return;
        }
      } catch (_) {}
    }
    if (entry.pageNumber != null) {
      _controller.jumpToPage(entry.pageNumber!);
    }
  }

  void _rotateClockwise() {
    HapticFeedback.selectionClick();
    setState(() => _quarterTurns = (_quarterTurns + 1) % 4);
  }

  Future<void> _printDocument() async {
    final l10n = context.l10n;
    final ok = await DevicePdfLibrary.printFile(widget.filePath);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.printingNotSupported)),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _initViewer();
    ReadingPrefs.keepScreenOn.addListener(_applyKeepScreenOn);
    ReadingPrefs.layoutMode.addListener(_onReadingPrefLayoutOrScrollChanged);
    ReadingPrefs.scrollDirection.addListener(_onReadingPrefLayoutOrScrollChanged);
    _applyKeepScreenOn();
  }

  @override
  void dispose() {
    ReadingPrefs.keepScreenOn.removeListener(_applyKeepScreenOn);
    ReadingPrefs.layoutMode.removeListener(_onReadingPrefLayoutOrScrollChanged);
    ReadingPrefs.scrollDirection.removeListener(_onReadingPrefLayoutOrScrollChanged);
    unawaited(WakelockPlus.disable());
    if (_immersive) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    _progressDebounce?.cancel();
    _saveProgress();
    _pageNumberNotifier.dispose();
    _commentInput.dispose();
    _searchFieldController.dispose();
    _jumpInput.dispose();
    _searchResult?.removeListener(_onSearchResultChanged);
    super.dispose();
  }

  void _applyKeepScreenOn() {
    if (ReadingPrefs.keepScreenOn.value) {
      unawaited(WakelockPlus.enable());
    } else {
      unawaited(WakelockPlus.disable());
    }
  }

  // ------------------------------------------------------------- progress

  void _saveProgress() {
    if (_pageCount > 0) {
      ReadingProgress.save(widget.filePath, _pageNumber, _pageCount);
    }
  }

  void _scheduleProgressSave() {
    _progressDebounce?.cancel();
    _progressDebounce = Timer(const Duration(milliseconds: 700), _saveProgress);
  }

  Future<void> _restorePosition() async {
    final saved = await ReadingProgress.get(widget.filePath);
    if (!mounted || saved == null || saved.page <= 1) return;
    if (saved.page <= _controller.pageCount) {
      _controller.jumpToPage(saved.page);
    }
  }

  Future<void> _promptJumpToPage() async {
    if (!_isLoaded || _pageCount <= 1) return;
    final l10n = context.l10n;
    _jumpInput.text = '$_pageNumber';
    final target = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.goToPage),
        content: TextField(
          controller: _jumpInput,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: l10n.pageNumberHint,
            border: const OutlineInputBorder(),
            suffixText: l10n.ofWord,
          ),
          onSubmitted: (value) =>
              Navigator.of(context).pop(int.tryParse(value)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(int.tryParse(_jumpInput.text)),
            child: Text(l10n.go),
          ),
        ],
      ),
    );
    if (!mounted || target == null) return;
    if (target < 1 || target > _pageCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pageMustBeBetween(_pageCount))),
      );
      return;
    }
    HapticFeedback.selectionClick();
    _controller.jumpToPage(target);
  }

  // ---------------------------------------------------------------- search

  void _toggleSearch() {
    if (_isSearchOpen) {
      _closeSearch();
      return;
    }
    setState(() => _isSearchOpen = true);
  }

  void _performSearch(String query) {
    final trimmed = query.trim();
    if (!_isLoaded || trimmed.isEmpty) return;
    _searchResult?.removeListener(_onSearchResultChanged);
    _searchResult?.clear();
    final result = _controller.searchText(trimmed);
    _searchResult = result;
    result.addListener(_onSearchResultChanged);
    if (mounted) setState(() {});
  }

  void _onSearchResultChanged() {
    if (mounted) setState(() {});
  }

  void _closeSearch() {
    _searchResult?.removeListener(_onSearchResultChanged);
    _searchResult?.clear();
    _searchResult = null;
    _searchFieldController.clear();
    if (mounted) setState(() => _isSearchOpen = false);
  }

  // ---------------------------------------------------------------- tools

  void _setTool(_Tool tool) {
    if (!_isLoaded) return;
    HapticFeedback.selectionClick();

    // If text was selected with precision handles and the user taps Highlight/Underline/Strikethrough:
    if (_selectedText != null && _selectedText!.trim().isNotEmpty) {
      if (tool == _Tool.highlight) {
        _highlightCurrentSelection();
        return;
      } else if (tool == _Tool.underline) {
        _underlineCurrentSelection();
        return;
      } else if (tool == _Tool.strikethrough) {
        _strikethroughCurrentSelection();
        return;
      }
    }

    setState(() => _tool = tool);
    _controller.annotationMode = switch (tool) {
      _Tool.pan => PdfAnnotationMode.none,
      _Tool.highlight => PdfAnnotationMode.highlight,
      _Tool.underline => PdfAnnotationMode.underline,
      _Tool.strikethrough => PdfAnnotationMode.strikethrough,
      _Tool.squiggly => PdfAnnotationMode.squiggly,
      _Tool.comment => PdfAnnotationMode.stickyNote,
    };
  }

  void _setColor(Color color) {
    HapticFeedback.selectionClick();
    setState(() => _color = color);
    if (_isLoaded) _applyColorToSettings(color);
  }

  void _applyColorToSettings(Color color) {
    final settings = _controller.annotationSettings;
    settings.highlight.color = color;
    settings.underline.color = color;
    settings.strikethrough.color = color;
    settings.squiggly.color = color;
    settings.stickyNote.color = color;
  }

  // ------------------------------------------------------------- selection

  void _onTextSelectionChanged(PdfTextSelectionChangedDetails details) {
    if (mounted) {
      setState(() {
        _selectedText = details.selectedText;
        _selectedRegion = details.globalSelectedRegion;
      });
    }
  }

  void _highlightCurrentSelection() {
    final lines = _pdfViewerStateKey.currentState?.getSelectedTextLines();
    if (lines != null && lines.isNotEmpty) {
      HapticFeedback.selectionClick();
      final annotation = HighlightAnnotation(textBoundsCollection: lines)
        ..color = _color;
      _controller.addAnnotation(annotation);
      _controller.clearSelection();
      setState(() {
        _selectedText = null;
        _selectedRegion = null;
      });
    }
  }

  void _underlineCurrentSelection() {
    final lines = _pdfViewerStateKey.currentState?.getSelectedTextLines();
    if (lines != null && lines.isNotEmpty) {
      HapticFeedback.selectionClick();
      final annotation = UnderlineAnnotation(textBoundsCollection: lines)
        ..color = _color;
      _controller.addAnnotation(annotation);
      _controller.clearSelection();
      setState(() {
        _selectedText = null;
        _selectedRegion = null;
      });
    }
  }

  void _strikethroughCurrentSelection() {
    final lines = _pdfViewerStateKey.currentState?.getSelectedTextLines();
    if (lines != null && lines.isNotEmpty) {
      HapticFeedback.selectionClick();
      final annotation = StrikethroughAnnotation(textBoundsCollection: lines)
        ..color = _color;
      _controller.addAnnotation(annotation);
      _controller.clearSelection();
      setState(() {
        _selectedText = null;
        _selectedRegion = null;
      });
    }
  }

  void _askGeminiAboutSelection() {
    final text = _selectedText;
    if (text != null && text.trim().isNotEmpty) {
      _controller.clearSelection();
      setState(() {
        _selectedText = null;
        _selectedRegion = null;
      });
      GeminiShareService.askGeminiAboutText(
        context: context,
        selectedText: text,
        pageTitle: '$_baseName (Page $_pageNumber)',
      );
    }
  }

  void _copySelection() {
    final text = _selectedText;
    if (text != null && text.trim().isNotEmpty) {
      Clipboard.setData(ClipboardData(text: text));
      _controller.clearSelection();
      setState(() {
        _selectedText = null;
        _selectedRegion = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.copiedToClipboard),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _clearTextSelection() {
    _controller.clearSelection();
    setState(() {
      _selectedText = null;
      _selectedRegion = null;
    });
  }

  void _onAnnotationSelected(Annotation annotation) {
    if (mounted) setState(() => _selectedAnnotation = annotation);
  }

  void _onAnnotationDeselected(Annotation annotation) {
    if (mounted && identical(_selectedAnnotation, annotation)) {
      setState(() => _selectedAnnotation = null);
    }
  }

  void _deleteSelected() {
    final annotation = _selectedAnnotation;
    if (annotation == null) return;
    HapticFeedback.mediumImpact();
    _controller.removeAnnotation(annotation);
    setState(() => _selectedAnnotation = null);
  }

  void _recolorSelected(Color color) {
    final annotation = _selectedAnnotation;
    if (annotation == null) return;
    HapticFeedback.selectionClick();
    annotation.color = color;
    setState(() => _color = color);
  }

  // ------------------------------------------------------------- reading

  void _toggleImmersive() {
    if (!_isLoaded) return;
    HapticFeedback.selectionClick();
    if (!_immersive && _tool != _Tool.pan) _setTool(_Tool.pan);
    if (!_immersive && _isSearchOpen) _closeSearch();
    setState(() => _immersive = !_immersive);
    SystemChrome.setEnabledSystemUIMode(
      _immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  void _undo() {
    if (_addedAnnotations.isEmpty) return;
    final annotation = _addedAnnotations.removeLast();
    _controller.removeAnnotation(annotation);
    _refreshCommentCount();
  }

  // ------------------------------------------------------------ annotations

  void _onAnnotationAdded(Annotation annotation) {
    _addedAnnotations.add(annotation);
    if (annotation is StickyNoteAnnotation) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _promptCommentText(annotation),
      );
    }
    _refreshCommentCount();
  }

  void _onAnnotationRemoved(Annotation annotation) {
    _addedAnnotations.remove(annotation);
    _refreshCommentCount();
  }

  Future<void> _promptCommentText(StickyNoteAnnotation annotation) async {
    final l10n = context.l10n;
    _commentInput.clear();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.addComment),
        content: TextField(
          controller: _commentInput,
          autofocus: true,
          maxLines: null,
          decoration: InputDecoration(
            hintText: l10n.commentHint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_commentInput.text),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    final trimmed = text?.trim();
    if (!mounted) return;
    if (trimmed == null || trimmed.isEmpty) {
      _controller.removeAnnotation(annotation);
      _addedAnnotations.remove(annotation);
      _refreshCommentCount();
    } else {
      annotation.text = trimmed;
      _refreshCommentCount();
    }
  }

  List<StickyNoteAnnotation> get _comments =>
      _controller.getAnnotations().whereType<StickyNoteAnnotation>().toList();

  void _refreshCommentCount() {
    if (mounted) setState(() {});
  }

  Future<void> _openCommentsSheet() async {
    if (!mounted) return;
    final l10n = context.l10n;
    if (_comments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.noCommentsYet),
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) =>
          SafeArea(child: _CommentsSheet(controller: _controller)),
    );
    _refreshCommentCount();
  }

  // ----------------------------------------------------------------- share

  String get _baseName =>
      EncodingUtils.cleanDisplayName(widget.title)
          .replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');

  Future<void> _sharePdf() async {
    if (!_isLoaded || _isBusy) return;
    setState(() => _isBusy = true);
    try {
      final bytes = await _controller.saveDocument();
      final dir = await getTemporaryDirectory();
      final outFile = File(
        '${dir.path}${Platform.pathSeparator}${_baseName}_annotated.pdf',
      );
      await outFile.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(outFile.path, mimeType: 'application/pdf')],
          title: widget.title,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.couldNotShare('$e'))));
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _saveAnnotatedCopy() async {
    if (!_isLoaded || _isBusy) return;
    final l10n = context.l10n;
    setState(() => _isBusy = true);
    try {
      final bytes = await _controller.saveDocument();
      final savedPath = await FileSaver.instance.saveFile(
        name: '${_baseName}_annotated',
        bytes: Uint8List.fromList(bytes),
        fileExtension: 'pdf',
        mimeType: MimeType.pdf,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.savedToPath(savedPath)),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.couldNotSave('$e'))));
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  // --------------------------------------------------------------- gallery

  Future<void> _savePageToGallery() async {
    if (!_isLoaded || _isBusy) return;
    final l10n = context.l10n;
    setState(() => _isBusy = true);
    try {
      await GallerySaver.saveBoundaryToGallery(
        context: context,
        boundaryKey: _viewerKey,
        baseName: 'Pagelit_${_baseName}_page_${_controller.pageNumber}',
        successMessage: l10n.viewOfPageSaved(_controller.pageNumber),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _askGemini() async {
    if (!_isLoaded || _isBusy) return;
    setState(() => _isBusy = true);
    try {
      await GeminiShareService.shareBoundaryToGemini(
        context: context,
        boundaryKey: _viewerKey,
        pageTitle: '$_baseName (Page ${_controller.pageNumber})',
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  // ----------------------------------------------------------------- build

  Widget _buildSearchBar() {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final result = _searchResult;
    final hasMatches =
        result != null &&
        result.isSearchCompleted &&
        result.totalInstanceCount > 0;
    final status = result == null || !result.isSearchCompleted
        ? ''
        : result.totalInstanceCount == 0
        ? l10n.noResults
        : '${result.currentInstanceIndex} / ${result.totalInstanceCount}';
    return Material(
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            IconButton(
              tooltip: l10n.closeSearch,
              icon: const Icon(Icons.close_rounded, size: 22),
              onPressed: _closeSearch,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: TextField(
                  controller: _searchFieldController,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  style: text.bodyMedium,
                  cursorColor: colorScheme.primary,
                  decoration: InputDecoration(
                    hintText: l10n.searchInDocument,
                    hintStyle: text.bodyMedium?.copyWith(
                      color: colorScheme.outline,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  onSubmitted: _performSearch,
                  onChanged: (value) {
                    if (value.trim().isEmpty && _searchResult != null) {
                      _searchResult?.removeListener(_onSearchResultChanged);
                      _searchResult?.clear();
                      _searchResult = null;
                      setState(() {});
                    }
                  },
                ),
              ),
            ),
            if (status.isNotEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 8),
                child: _MatchBadge(
                  label: status,
                  empty: status == l10n.noResults,
                ),
              ),
            IconButton(
              tooltip: l10n.previousMatch,
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
              onPressed: hasMatches
                  ? () => _searchResult!.previousInstance()
                  : null,
            ),
            IconButton(
              tooltip: l10n.nextMatch,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              onPressed: hasMatches
                  ? () => _searchResult!.nextInstance()
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: _immersive
          ? null
          : AppBar(
              titleSpacing: 0,
              title: LayoutBuilder(
                builder: (context, constraints) {
                  final cleanTitle = EncodingUtils.cleanDisplayName(widget.title);
                  if (constraints.maxWidth < 64) {
                    return Text(
                      cleanTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    );
                  }
                  return Row(
                    children: [
                      const PdfGlyph(size: 20),
                      const SizedBox(width: 6),
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
                if (_pageCount > 0)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 4),
                    child: ValueListenableBuilder<int>(
                      valueListenable: _pageNumberNotifier,
                      builder: (context, page, _) => _PagePill(
                        label: '$page / $_pageCount',
                        onTap: _promptJumpToPage,
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: l10n.tableOfContents,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.menu_book_rounded),
                  onPressed: _isLoaded ? _openBookmarksSheet : null,
                ),
                IconButton(
                  tooltip: l10n.search,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    _isSearchOpen
                        ? Icons.search_off_rounded
                        : Icons.search_rounded,
                  ),
                  onPressed: _isLoaded ? _toggleSearch : null,
                ),
                IconButton(
                  tooltip: l10n.fullScreen,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.fullscreen_rounded),
                  onPressed: _isLoaded ? _toggleImmersive : null,
                ),
                IconButton(
                  tooltip: l10n.askGemini,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.auto_awesome_rounded),
                  color: Theme.of(context).colorScheme.primary,
                  onPressed: _isLoaded && !_isBusy ? _askGemini : null,
                ),
                PopupMenuButton<String>(
                  tooltip: l10n.more,
                  icon: const Icon(Icons.more_vert_rounded),
                  enabled: _isLoaded && !_isBusy,
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'comments',
                      child: ListTile(
                        leading: const Icon(Icons.chat_bubble_outline_rounded),
                        title: Text(l10n.comments),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'share',
                      child: ListTile(
                        leading: const Icon(Icons.share_rounded),
                        title: Text(l10n.sharePdf),
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'rotate',
                      child: ListTile(
                        leading: const Icon(Icons.rotate_right_rounded),
                        title: Text(l10n.rotate90),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'print',
                      child: ListTile(
                        leading: const Icon(Icons.print_rounded),
                        title: Text(l10n.printDocument),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'save_copy',
                      child: ListTile(
                        leading: const Icon(Icons.save_as_rounded),
                        title: Text(l10n.saveAnnotatedCopy),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'gallery',
                      child: ListTile(
                        leading: const Icon(Icons.add_photo_alternate_rounded),
                        title: Text(l10n.saveCurrentViewToGallery),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'gemini',
                      child: ListTile(
                        leading: const Icon(Icons.auto_awesome_rounded),
                        title: Text(l10n.askGeminiAboutPage),
                      ),
                    ),
                    const PopupMenuDivider(),
                    for (final entry in {
                      ComfortMode.normal: l10n.comfortNormal,
                      ComfortMode.sepia: l10n.comfortSepia,
                      ComfortMode.dim: l10n.comfortDim,
                      ComfortMode.inverted: l10n.comfortNight,
                    }.entries)
                      PopupMenuItem(
                        value: 'comfort_${entry.key.name}',
                        child: Row(
                          children: [
                            SizedBox(
                              width: 24,
                              child: ReadingPrefs.comfortMode.value == entry.key
                                  ? Icon(
                                      Icons.check_rounded,
                                      size: 18,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    )
                                  : null,
                            ),
                            Text(entry.value),
                          ],
                        ),
                      ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'settings',
                      child: ListTile(
                        leading: const Icon(Icons.settings_outlined),
                        title: Text(l10n.settings),
                      ),
                    ),
                  ],
                  onSelected: (value) {
                    switch (value) {
                                            case 'comments':
                        _openCommentsSheet();
                      case 'share':
                        _sharePdf();
                      case 'rotate':
                        _rotateClockwise();
                      case 'print':
                        _printDocument();
                      case 'save_copy':
                        _saveAnnotatedCopy();
                      case 'gallery':
                        _savePageToGallery();
                      case 'gemini':
                        _askGemini();
                      case 'comfort_normal':
                        ReadingPrefs.setComfortMode(ComfortMode.normal);
                      case 'comfort_sepia':
                        ReadingPrefs.setComfortMode(ComfortMode.sepia);
                      case 'comfort_dim':
                        ReadingPrefs.setComfortMode(ComfortMode.dim);
                      case 'comfort_inverted':
                        ReadingPrefs.setComfortMode(ComfortMode.inverted);
                      case 'settings':
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const SettingsScreen(),
                          ),
                        );
                    }
                  },
                ),
              ],
            ),
      body: Column(
        children: [
          if (_isSearchOpen && !_immersive) _buildSearchBar(),
          Expanded(child: _buildViewerArea()),
        ],
      ),
      bottomNavigationBar: _immersive ? null : _buildBottomBar(),
    );
  }

  Widget _buildViewerArea() {
    final l10n = context.l10n;
    return ValueListenableBuilder<ComfortMode>(
      valueListenable: ReadingPrefs.comfortMode,
      builder: (context, comfort, _) {
        Widget content = RepaintBoundary(
          key: _viewerKey,
          child: RotatedBox(
            quarterTurns: _quarterTurns,
            child: _viewer,
          ),
        );

        if (comfort == ComfortMode.inverted) {
          content = ColorFiltered(
            colorFilter: const ColorFilter.matrix([
              -1.0,  0.0,  0.0, 0.0, 255.0,
               0.0, -1.0,  0.0, 0.0, 255.0,
               0.0,  0.0, -1.0, 0.0, 255.0,
               0.0,  0.0,  0.0, 1.0,   0.0,
            ]),
            child: content,
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            content,
            if (comfort == ComfortMode.sepia || comfort == ComfortMode.dim)
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: comfort == ComfortMode.sepia
                        ? const Color(0x33E0C489)
                        : const Color(0x6B000000),
                  ),
                ),
              ),
            if (!_isLoaded) const _OpeningPlaceholder(),
            if (_immersive) ...[
              Positioned(
                top: 0,
                right: 0,
                child: SafeArea(
                  child: IconButton(
                    tooltip: l10n.exitFullScreen,
                    style: IconButton.styleFrom(backgroundColor: Colors.black38),
                    icon: const Icon(
                      Icons.fullscreen_exit_rounded,
                      color: Colors.white,
                    ),
                    onPressed: _toggleImmersive,
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Center(
                    child: ValueListenableBuilder<int>(
                      valueListenable: _pageNumberNotifier,
                      builder: (context, page, _) => _PagePill(
                        label: '$page / $_pageCount',
                        onTap: _promptJumpToPage,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (_selectedText != null && _selectedText!.trim().isNotEmpty)
              _buildSelectionQuickBar(),
            if (_tool == _Tool.highlight && !_immersive)
              _buildHighlightTipBar(),
          ],
        );
      },
    );
  }

  Widget _buildSelectionQuickBar() {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final region = _selectedRegion;

    double topPos = 16.0;
    if (region != null) {
      if (region.top > 130) {
        topPos = (region.top - 62).clamp(16.0, mediaQuery.size.height - 180);
      } else {
        topPos = (region.bottom + 14).clamp(16.0, mediaQuery.size.height - 180);
      }
    }

    return Positioned(
      top: topPos,
      left: 16,
      right: 16,
      child: Center(
        child: Material(
          elevation: 8,
          shadowColor: Colors.black45,
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      minimumSize: const Size(40, 36),
                    ),
                    icon: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: _color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colorScheme.onSurface,
                          width: 1.5,
                        ),
                      ),
                    ),
                    label: Text(
                      l10n.toolHighlight,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    onPressed: _highlightCurrentSelection,
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    tooltip: l10n.toolUnderline,
                    icon: const Icon(Icons.format_underlined_rounded, size: 20),
                    onPressed: _underlineCurrentSelection,
                  ),
                  IconButton(
                    tooltip: l10n.toolStrikethrough,
                    icon: const Icon(Icons.format_strikethrough_rounded, size: 20),
                    onPressed: _strikethroughCurrentSelection,
                  ),
                  IconButton(
                    tooltip: l10n.askGemini,
                    icon: Icon(
                      Icons.auto_awesome_rounded,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                    onPressed: _askGeminiAboutSelection,
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(context).copyButtonLabel,
                    icon: const Icon(Icons.copy_rounded, size: 19),
                    onPressed: _copySelection,
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                    icon: const Icon(Icons.close_rounded, size: 19),
                    onPressed: _clearTextSelection,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHighlightTipBar() {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;

    return Positioned(
      top: 10,
      left: 20,
      right: 20,
      child: Center(
        child: Material(
          elevation: 3,
          color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.touch_app_rounded,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    l10n.precisionHighlightHint,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _setTool(_Tool.pan),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Text(
                      l10n.toolReadPan,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
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

  Widget _buildSelectionBar() {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppShape.radiusLarge),
          boxShadow: [
            BoxShadow(
              color: colorScheme.brightness == Brightness.dark
                  ? Colors.black.withValues(alpha: 0.35)
                  : const Color(0x1A17161C),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: colorScheme.surfaceContainerLowest,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppShape.radiusLarge),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final color in _annotationPalette)
                  InkWell(
                    onTap: () => _recolorSelected(color),
                    customBorder: const CircleBorder(),
                    child: SizedBox(
                      width: 36,
                      height: 44,
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color:
                                  _selectedAnnotation?.color.toARGB32() ==
                                          color.toARGB32() ||
                                      (_selectedAnnotation == null &&
                                          _color.toARGB32() == color.toARGB32())
                                  ? colorScheme.onSurface
                                  : colorScheme.outlineVariant,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton(
                    tooltip: l10n.deleteAnnotation,
                    icon: const Icon(Icons.delete_outline_rounded, size: 21),
                    onPressed: _deleteSelected,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    Widget toolButton(_Tool tool, IconData icon, String tooltip) {
      final selected = _tool == tool;
      return Tooltip(
        message: tooltip,
        child: IconButton(
          onPressed: () => _setTool(tool),
          constraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          icon: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: _toolButtonSize,
            height: _toolButtonSize,
            decoration: BoxDecoration(
              color: selected ? colorScheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(AppShape.radiusSmall),
            ),
            child: Icon(
              icon,
              size: 21,
              color: selected ? Colors.white : colorScheme.onSurface,
            ),
          ),
        ),
      );
    }

    Widget swatch(Color color) {
      final selected = _color.toARGB32() == color.toARGB32();
      return InkWell(
        onTap: () => _setColor(color),
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 36,
          height: 44,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? colorScheme.onSurface
                      : colorScheme.outlineVariant,
                  width: selected ? 2 : 1,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final selected = _selectedAnnotation;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: selected == null
                ? const SizedBox(width: double.infinity, height: 0)
                : _buildSelectionBar(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppShape.radiusLarge),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.brightness == Brightness.dark
                        ? Colors.black.withValues(alpha: 0.35)
                        : const Color(0x1A17161C),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Material(
                color: colorScheme.surfaceContainerLowest,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppShape.radiusLarge),
                  side: BorderSide(color: colorScheme.outlineVariant),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isLoaded && _pageCount > 1) _buildScrubber(),
                    if (_isLoaded && _pageCount > 1)
                      Divider(
                        indent: 14,
                        endIndent: 14,
                        color: colorScheme.outlineVariant,
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: constraints.maxWidth,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  toolButton(
                                    _Tool.pan,
                                    Icons.pan_tool_alt_rounded,
                                    l10n.toolReadPan,
                                  ),
                                  toolButton(
                                    _Tool.highlight,
                                    Icons.highlight_rounded,
                                    l10n.toolHighlight,
                                  ),
                                  toolButton(
                                    _Tool.underline,
                                    Icons.format_underlined_rounded,
                                    l10n.toolUnderline,
                                  ),
                                  toolButton(
                                    _Tool.strikethrough,
                                    Icons.format_strikethrough_rounded,
                                    l10n.toolStrikethrough,
                                  ),
                                  toolButton(
                                    _Tool.squiggly,
                                    Icons.waves_rounded,
                                    l10n.toolSquiggly,
                                  ),
                                  toolButton(
                                    _Tool.comment,
                                    Icons.sticky_note_2_rounded,
                                    l10n.toolComment,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Divider(
                      indent: 14,
                      endIndent: 14,
                      height: 1,
                      color: colorScheme.outlineVariant,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          Tooltip(
                            message: l10n.annotationColor,
                            child: Icon(
                              Icons.palette_outlined,
                              size: 20,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final color in _palette) swatch(color),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            tooltip: l10n.undo,
                            icon: const Icon(Icons.undo_rounded, size: 21),
                            onPressed: _addedAnnotations.isEmpty ? null : _undo,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrubber() {
    final l10n = context.l10n;
    return ValueListenableBuilder<int>(
      valueListenable: _pageNumberNotifier,
      builder: (context, page, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
          child: PageScrubber(
            currentPage: page,
            totalPages: _pageCount,
            chapterPages: _tocResult?.topLevelPages ?? const [],
            labelBuilder: (p) => l10n.pageNumberLabel(p, _pageCount),
            subtitleBuilder: (p) => _tocResult?.chapterTitleForPage(p),
            onPageSelected: (target) {
              _pageNumberNotifier.value = target;
              _controller.jumpToPage(target);
              _scheduleProgressSave();
            },
          ),
        );
      },
    );
  }
}

/// Outline / Table of contents viewer supporting embedded outlines,
/// detected printed TOC pages, and detected chapter headings.
class _OutlineSheet extends StatefulWidget {
  const _OutlineSheet({
    required this.initialResult,
    required this.pendingFuture,
    required this.currentPage,
    required this.onSelect,
  });

  final PdfTocResult? initialResult;
  final Future<PdfTocResult>? pendingFuture;
  final int currentPage;
  final ValueChanged<PdfTocEntry> onSelect;

  @override
  State<_OutlineSheet> createState() => _OutlineSheetState();
}

class _OutlineSheetState extends State<_OutlineSheet> {
  final TextEditingController _filterController = TextEditingController();
  final Set<String> _expandedKeys = <String>{};
  PdfTocResult? _result;
  String _filterQuery = '';

  @override
  void initState() {
    super.initState();
    _result = widget.initialResult;
    if (_result != null) {
      _expandBranchContainingCurrentPage();
    } else if (widget.pendingFuture != null) {
      widget.pendingFuture!.then((resolved) {
        if (!mounted) return;
        setState(() {
          _result = resolved;
          _expandBranchContainingCurrentPage();
        });
      });
    }
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  void _expandBranchContainingCurrentPage() {
    final res = _result;
    if (res == null || res.entries.isEmpty) return;

    String? findPath(List<PdfTocEntry> list, String prefix) {
      String? bestPath;
      int bestPage = -1;
      for (int i = 0; i < list.length; i++) {
        final item = list[i];
        final key = '$prefix.$i';
        final p = item.pageNumber;
        if (p != null && p <= widget.currentPage && p >= bestPage) {
          bestPage = p;
          bestPath = key;
        }
        if (item.children.isNotEmpty) {
          final childMatch = findPath(item.children, key);
          if (childMatch != null) {
            bestPath = childMatch;
          }
        }
      }
      return bestPath;
    }

    final matchPath = findPath(res.entries, 'r');
    if (matchPath != null) {
      final parts = matchPath.split('.');
      for (int i = 2; i <= parts.length; i++) {
        _expandedKeys.add(parts.sublist(0, i).join('.'));
      }
    }
  }

  PdfTocEntry? _findActiveEntry(PdfTocResult? res) {
    if (res == null) return null;
    PdfTocEntry? best;
    int bestPage = -1;
    int bestDepth = -1;
    for (final entry in res.flattened) {
      final p = entry.pageNumber;
      if (p == null || p > widget.currentPage) continue;
      if (p > bestPage || (p == bestPage && entry.level >= bestDepth)) {
        bestPage = p;
        bestDepth = entry.level;
        best = entry;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final res = _result;
    final activeEntry = _findActiveEntry(res);
    final flattened = res?.flattened ?? const <PdfTocEntry>[];
    final showSearch = flattened.length > 8;
    final filtered = _filterQuery.isEmpty
        ? const <PdfTocEntry>[]
        : flattened
            .where((e) => EncodingUtils.searchMatches(e.title, _filterQuery))
            .toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.62,
          minChildSize: 0.36,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 16, 10),
                  child: Row(
                    children: [
                      const Icon(Icons.menu_book_rounded, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.tableOfContents,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (res != null &&
                          res.isNotEmpty &&
                          res.source != null &&
                          res.source != PdfTocSource.embeddedBookmarks)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            l10n.detectedChapters,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (showSearch)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: TextField(
                      controller: _filterController,
                      decoration: InputDecoration(
                        hintText: l10n.filterChaptersHint,
                        prefixIcon: const Icon(Icons.search_rounded, size: 19),
                        suffixIcon: _filterQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () => setState(() {
                                  _filterQuery = '';
                                  _filterController.clear();
                                }),
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                      ),
                      onChanged: (val) =>
                          setState(() => _filterQuery = val.trim()),
                    ),
                  ),
                const Divider(height: 1),
                Expanded(
                  child: _buildBody(
                    context,
                    l10n,
                    scheme,
                    res,
                    activeEntry,
                    filtered,
                    scrollController,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme scheme,
    PdfTocResult? res,
    PdfTocEntry? activeEntry,
    List<PdfTocEntry> filtered,
    ScrollController scrollController,
  ) {
    if (res == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 14),
              Text(
                l10n.scanningChapters,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }

    if (res.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.menu_book_outlined,
                size: 42,
                color: scheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.noTableOfContents,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    if (_filterQuery.isNotEmpty) {
      if (filtered.isEmpty) {
        return Center(
          child: Text(
            l10n.noResults,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        );
      }
      return ListView.builder(
        controller: scrollController,
        itemCount: filtered.length,
        itemBuilder: (context, idx) {
          final entry = filtered[idx];
          return _buildEntryRow(
            context,
            scheme,
            entry,
            activeEntry: activeEntry,
            depth: entry.level,
            nodeKey: 'f_$idx',
            hasChildren: false,
          );
        },
      );
    }

    return ListView.builder(
      controller: scrollController,
      itemCount: res.entries.length,
      itemBuilder: (context, index) {
        return _buildTreeBranch(
          context,
          scheme,
          res.entries[index],
          activeEntry: activeEntry,
          depth: 0,
          nodeKey: 'r.$index',
        );
      },
    );
  }

  Widget _buildTreeBranch(
    BuildContext context,
    ColorScheme scheme,
    PdfTocEntry entry, {
    required PdfTocEntry? activeEntry,
    required int depth,
    required String nodeKey,
  }) {
    final hasChildren = entry.children.isNotEmpty;
    final isExpanded = _expandedKeys.contains(nodeKey);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildEntryRow(
          context,
          scheme,
          entry,
          activeEntry: activeEntry,
          depth: depth,
          nodeKey: nodeKey,
          hasChildren: hasChildren,
          isExpanded: isExpanded,
        ),
        if (hasChildren && isExpanded)
          for (int i = 0; i < entry.children.length; i++)
            _buildTreeBranch(
              context,
              scheme,
              entry.children[i],
              activeEntry: activeEntry,
              depth: depth + 1,
              nodeKey: '$nodeKey.$i',
            ),
      ],
    );
  }

  Widget _buildEntryRow(
    BuildContext context,
    ColorScheme scheme,
    PdfTocEntry entry, {
    required PdfTocEntry? activeEntry,
    required int depth,
    required String nodeKey,
    required bool hasChildren,
    bool isExpanded = false,
  }) {
    final isActive = identical(entry, activeEntry);
    final canNavigate = entry.pageNumber != null || entry.bookmark != null;
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return InkWell(
      onTap: canNavigate
          ? () {
              Navigator.of(context).pop();
              widget.onSelect(entry);
            }
          : null,
      child: Container(
        color: isActive
            ? scheme.primaryContainer.withValues(alpha: 0.35)
            : Colors.transparent,
        padding: EdgeInsetsDirectional.fromSTEB(
          16.0 + (depth * 16.0),
          10,
          12,
          10,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                entry.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: depth == 0 ? 14.5 : 13.5,
                  fontWeight: isActive || depth == 0
                      ? FontWeight.w600
                      : FontWeight.normal,
                  color: isActive ? scheme.primary : scheme.onSurface,
                ),
              ),
            ),
            if (entry.pageNumber != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isActive
                      ? scheme.primary
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${entry.pageNumber}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isActive
                        ? scheme.onPrimary
                        : scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
            if (hasChildren)
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                icon: isExpanded
                    ? Icon(
                        Icons.expand_more_rounded,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      )
                    : Transform.flip(
                        flipX: isRtl,
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                onPressed: () {
                  setState(() {
                    if (isExpanded) {
                      _expandedKeys.remove(nodeKey);
                    } else {
                      _expandedKeys.add(nodeKey);
                    }
                  });
                },
              )
            else
              const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

/// Lists the document's sticky notes.
class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({required this.controller});

  final PdfViewerController controller;

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  late final List<StickyNoteAnnotation> _notes = widget.controller
      .getAnnotations()
      .whereType<StickyNoteAnnotation>()
      .toList();

  void _delete(StickyNoteAnnotation note) {
    widget.controller.removeAnnotation(note);
    setState(() => _notes.remove(note));
    if (_notes.isEmpty) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_notes.isEmpty) {
      return SizedBox(
        height: 160,
        child: Center(child: Text(l10n.noCommentsLeft)),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: _notes.length,
      itemBuilder: (context, index) {
        final note = _notes[index];
        return ListTile(
          leading: Icon(Icons.sticky_note_2_rounded, color: note.color),
          title: Text(note.text, maxLines: 3, overflow: TextOverflow.ellipsis),
          subtitle: Text('${l10n.goToPage} ${note.pageNumber}'),
          trailing: IconButton(
            tooltip: l10n.deleteComment,
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _delete(note),
          ),
          onTap: () {
            Navigator.of(context).pop();
            widget.controller.jumpToPage(note.pageNumber);
          },
        );
      },
    );
  }
}

class _PagePill extends StatelessWidget {
  const _PagePill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Tooltip(
      message: l10n.goToPage,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Text(
            label,
            style: text.labelMedium?.copyWith(color: scheme.onSurface),
          ),
        ),
      ),
    );
  }
}

class _MatchBadge extends StatelessWidget {
  const _MatchBadge({required this.label, required this.empty});

  final String label;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: empty ? scheme.surfaceContainer : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        label,
        style: text.labelSmall?.copyWith(
          color: empty ? scheme.outline : scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _OpeningPlaceholder extends StatelessWidget {
  const _OpeningPlaceholder();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: scheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PdfGlyph(size: 40),
            const SizedBox(height: 18),
            Text(l10n.openingDocument, style: text.titleSmall),
            const SizedBox(height: 14),
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                color: scheme.primary,
                backgroundColor: scheme.surfaceContainerHigh,
                minHeight: 3,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

