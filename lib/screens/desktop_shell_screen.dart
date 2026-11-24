import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../services/encoding_utils.dart';
import '../services/recent_files.dart';
import '../theme/app_theme.dart';
import '../widgets/pdf_glyph.dart';
import 'desktop_home_view.dart';
import 'excel_viewer_screen.dart';
import 'presentation_viewer_screen.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';
import 'word_viewer_screen.dart';

enum _DesktopTabKind { home, document, settings }

class _DesktopTab {
  const _DesktopTab({
    required this.id,
    required this.kind,
    required this.title,
    this.filePath,
  });

  final String id;
  final _DesktopTabKind kind;
  final String title;
  final String? filePath;

  String get extension {
    final p = filePath;
    if (p == null) return '';
    final dot = p.lastIndexOf('.');
    return dot == -1 ? '' : p.substring(dot).toLowerCase();
  }
}

/// Top-level desktop shell for Windows & Linux:
/// integrated custom title bar, pinned Home tab, multi-document tabs,
/// drag-and-drop file opening, and global keyboard shortcuts.
class DesktopShellScreen extends StatefulWidget {
  const DesktopShellScreen({super.key, this.initialFilePath});

  final String? initialFilePath;

  @override
  State<DesktopShellScreen> createState() => _DesktopShellScreenState();
}

class _DesktopShellScreenState extends State<DesktopShellScreen>
    with WindowListener {
  static const _supportedExtensions = {
    'pdf',
    'docx',
    'doc',
    'pptx',
    'ppt',
    'xlsx',
    'xls',
  };

  static const int _maxWarmDocumentTabs = 3;

  final List<_DesktopTab> _tabs = [
    const _DesktopTab(
      id: '__home__',
      kind: _DesktopTabKind.home,
      title: 'Home',
    ),
  ];
  final List<String> _warmDocumentTabIds = [];
  int _activeIndex = 0;
  bool _isMaximized = false;
  bool _isDraggingFile = false;
  int _homeRefreshTrigger = 0;

  final FocusNode _searchFocusNode = FocusNode();

  void _touchWarmTab(_DesktopTab tab) {
    if (tab.kind != _DesktopTabKind.document) return;
    _warmDocumentTabIds.remove(tab.id);
    _warmDocumentTabIds.add(tab.id);
    while (_warmDocumentTabIds.length > _maxWarmDocumentTabs) {
      _warmDocumentTabIds.removeAt(0);
    }
  }

  void _activateTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    setState(() {
      _activeIndex = index;
      _touchWarmTab(_tabs[index]);
    });
  }

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _syncMaximizedState();

    final initial = widget.initialFilePath;
    if (initial != null && initial.isNotEmpty && File(initial).existsSync()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        openDocument(initial, _basename(initial));
      });
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _syncMaximizedState() async {
    final max = await windowManager.isMaximized();
    if (mounted && max != _isMaximized) {
      setState(() => _isMaximized = max);
    }
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  String _basename(String path) =>
      EncodingUtils.cleanDisplayName(path.split(Platform.pathSeparator).last);

  bool _isSupportedPath(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1) return false;
    return _supportedExtensions.contains(path.substring(dot + 1).toLowerCase());
  }

  Future<void> openDocument(String path, String title) async {
    if (!File(path).existsSync()) return;
    final cleanTitle = EncodingUtils.cleanDisplayName(title);
    await RecentFilesStore.add(path, cleanTitle);

    final existingIndex = _tabs.indexWhere(
      (t) => t.kind == _DesktopTabKind.document && t.filePath == path,
    );
    if (existingIndex != -1) {
      setState(() {
        _activeIndex = existingIndex;
        _touchWarmTab(_tabs[existingIndex]);
        _homeRefreshTrigger++;
      });
      return;
    }

    final newTab = _DesktopTab(
      id: path,
      kind: _DesktopTabKind.document,
      title: cleanTitle,
      filePath: path,
    );
    setState(() {
      _tabs.add(newTab);
      _activeIndex = _tabs.length - 1;
      _touchWarmTab(newTab);
      _homeRefreshTrigger++;
    });
  }

  Future<void> _pickFile() async {
    final results = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: _supportedExtensions.toList(),
    );
    if (results.isEmpty) return;
    final path = results.first.path;
    if (path == null || path.isEmpty) return;
    await openDocument(path, _basename(path));
  }

  void _openSettingsTab() {
    final existing = _tabs.indexWhere((t) => t.kind == _DesktopTabKind.settings);
    if (existing != -1) {
      _activateTab(existing);
      return;
    }
    setState(() {
      _tabs.add(
        const _DesktopTab(
          id: '__settings__',
          kind: _DesktopTabKind.settings,
          title: 'Settings',
        ),
      );
      _activeIndex = _tabs.length - 1;
    });
  }

  void _closeTab(int index) {
    if (index <= 0 || index >= _tabs.length) return;
    setState(() {
      final removed = _tabs.removeAt(index);
      _warmDocumentTabIds.remove(removed.id);
      if (_activeIndex >= _tabs.length) {
        _activeIndex = _tabs.length - 1;
      } else if (_activeIndex > index) {
        _activeIndex--;
      }
      _touchWarmTab(_tabs[_activeIndex]);
      _homeRefreshTrigger++;
    });
  }

  void _cycleTab(int delta) {
    if (_tabs.length <= 1) return;
    final next = (_activeIndex + delta + _tabs.length) % _tabs.length;
    _activateTab(next);
  }

  void _focusHomeSearch() {
    _activateTab(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  bool _shouldKeepTabMounted(int index, _DesktopTab tab) {
    if (index == _activeIndex) return true;
    if (tab.kind == _DesktopTabKind.home) return true;
    if (tab.kind == _DesktopTabKind.settings) return false;
    return _warmDocumentTabIds.contains(tab.id);
  }

  Widget _buildBoundedTabStack() {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (int i = 0; i < _tabs.length; i++)
          if (_shouldKeepTabMounted(i, _tabs[i]))
            KeyedSubtree(
              key: ValueKey('shell_slot_${_tabs[i].id}'),
              child: Offstage(
                offstage: i != _activeIndex,
                child: TickerMode(
                  enabled: i == _activeIndex,
                  child: ExcludeFocus(
                    excluding: i != _activeIndex,
                    child: _buildTabBody(_tabs[i]),
                  ),
                ),
              ),
            ),
      ],
    );
  }

  Widget _buildTabBody(_DesktopTab tab) {
    switch (tab.kind) {
      case _DesktopTabKind.home:
        return DesktopHomeView(
          key: const ValueKey('desktop_home'),
          onOpenFile: openDocument,
          onPickFile: _pickFile,
          onOpenSettings: _openSettingsTab,
          searchFocusNode: _searchFocusNode,
          refreshTrigger: _homeRefreshTrigger,
        );
      case _DesktopTabKind.settings:
        return const SettingsScreen(key: ValueKey('desktop_settings'));
      case _DesktopTabKind.document:
        final path = tab.filePath!;
        final ext = tab.extension;
        if (ext == '.docx' || ext == '.doc') {
          return WordViewerScreen(
            key: ValueKey('word_$path'),
            filePath: path,
            title: tab.title,
          );
        }
        if (ext == '.pptx' || ext == '.ppt') {
          return PresentationViewerScreen(
            key: ValueKey('ppt_$path'),
            filePath: path,
            title: tab.title,
          );
        }
        if (ext == '.xlsx' || ext == '.xls') {
          return ExcelViewerScreen(
            key: ValueKey('xls_$path'),
            filePath: path,
            title: tab.title,
          );
        }
        return ReaderScreen(
          key: ValueKey('pdf_$path'),
          filePath: path,
          title: tab.title,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyO, control: true):
            _pickFile,
        const SingleActivator(LogicalKeyboardKey.keyW, control: true): () =>
            _closeTab(_activeIndex),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _focusHomeSearch,
        const SingleActivator(LogicalKeyboardKey.tab, control: true): () =>
            _cycleTab(1),
        const SingleActivator(
          LogicalKeyboardKey.tab,
          control: true,
          shift: true,
        ): () => _cycleTab(-1),
      },
      child: Focus(
        autofocus: true,
        child: DropTarget(
          onDragEntered: (_) => setState(() => _isDraggingFile = true),
          onDragExited: (_) => setState(() => _isDraggingFile = false),
          onDragDone: (details) async {
            setState(() => _isDraggingFile = false);
            for (final file in details.files) {
              if (_isSupportedPath(file.path)) {
                await openDocument(file.path, _basename(file.path));
              }
            }
          },
          child: Scaffold(
            backgroundColor: scheme.surface,
            body: Stack(
              children: [
                Column(
                  children: [
                    _DesktopTitleAndTabBar(
                      tabs: _tabs,
                      activeIndex: _activeIndex,
                      isMaximized: _isMaximized,
                      onSelectTab: _activateTab,
                      onCloseTab: _closeTab,
                      onNewTabPickFile: _pickFile,
                    ),
                    Expanded(
                      child: _buildBoundedTabStack(),
                    ),
                  ],
                ),
                if (_isDraggingFile)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        color: AppPalette.signal.withValues(alpha: 0.12),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 20,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              borderRadius: BorderRadius.circular(
                                AppShape.radiusLarge,
                              ),
                              border: Border.all(
                                color: AppPalette.signal,
                                width: 2,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const PdfGlyph(size: 40),
                                const SizedBox(height: 10),
                                Text(
                                  'Drop to open in Pagelit',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ],
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

class _DesktopTitleAndTabBar extends StatelessWidget {
  const _DesktopTitleAndTabBar({
    required this.tabs,
    required this.activeIndex,
    required this.isMaximized,
    required this.onSelectTab,
    required this.onCloseTab,
    required this.onNewTabPickFile,
  });

  final List<_DesktopTab> tabs;
  final int activeIndex;
  final bool isMaximized;
  final ValueChanged<int> onSelectTab;
  final ValueChanged<int> onCloseTab;
  final VoidCallback onNewTabPickFile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      child: Row(
        children: [
          DragToMoveArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const PdfGlyph(size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Pagelit',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              itemBuilder: (context, index) {
                final tab = tabs[index];
                final isActive = index == activeIndex;
                return _TabPill(
                  tab: tab,
                  isActive: isActive,
                  onTap: () => onSelectTab(index),
                  onClose: tab.kind == _DesktopTabKind.home
                      ? null
                      : () => onCloseTab(index),
                );
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded, size: 18),
            tooltip: 'Open file (Ctrl+O)',
            onPressed: onNewTabPickFile,
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 36,
            height: 42,
            child: DragToMoveArea(child: const SizedBox.expand()),
          ),
          _WindowCaptionButton(
            icon: Icons.remove_rounded,
            tooltip: 'Minimize',
            onPressed: () => windowManager.minimize(),
          ),
          _WindowCaptionButton(
            icon: isMaximized
                ? Icons.filter_none_rounded
                : Icons.crop_square_rounded,
            iconSize: isMaximized ? 14 : 16,
            tooltip: isMaximized ? 'Restore' : 'Maximize',
            onPressed: () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
          ),
          _WindowCaptionButton(
            icon: Icons.close_rounded,
            tooltip: 'Close',
            isClose: true,
            onPressed: () => windowManager.close(),
          ),
        ],
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.tab,
    required this.isActive,
    required this.onTap,
    this.onClose,
  });

  final _DesktopTab tab;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(top: 5, right: 3),
      child: Material(
        color: isActive ? scheme.surface : Colors.transparent,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        child: InkWell(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          onTap: onTap,
          child: Container(
            constraints: BoxConstraints(
              minWidth: tab.kind == _DesktopTabKind.home ? 84 : 130,
              maxWidth: 220,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10),
              ),
              border: isActive
                  ? Border.all(color: scheme.outlineVariant)
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _tabIcon(tab),
                  size: 15,
                  color: isActive ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    tab.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelMedium?.copyWith(
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                      color: isActive
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (onClose != null) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: onClose,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _tabIcon(_DesktopTab tab) {
    switch (tab.kind) {
      case _DesktopTabKind.home:
        return Icons.home_rounded;
      case _DesktopTabKind.settings:
        return Icons.settings_outlined;
      case _DesktopTabKind.document:
        final ext = tab.extension;
        if (ext == '.docx' || ext == '.doc') return Icons.description_outlined;
        if (ext == '.pptx' || ext == '.ppt') return Icons.slideshow_rounded;
        if (ext == '.xlsx' || ext == '.xls') return Icons.table_chart_outlined;
        return Icons.picture_as_pdf_rounded;
    }
  }
}

class _WindowCaptionButton extends StatelessWidget {
  const _WindowCaptionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconSize = 16,
    this.isClose = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double iconSize;
  final bool isClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        hoverColor: isClose ? AppPalette.signal : scheme.surfaceContainerHigh,
        onTap: onPressed,
        child: SizedBox(
          width: 44,
          height: 42,
          child: Icon(icon, size: iconSize, color: scheme.onSurface),
        ),
      ),
    );
  }
}
