import 'dart:io';

import 'package:flutter/material.dart';

import '../services/device_pdfs.dart';
import '../services/encoding_utils.dart';
import '../services/reading_progress.dart';
import '../services/recent_files.dart';
import '../services/theme_prefs.dart';
import '../theme/app_theme.dart';
import '../widgets/pdf_glyph.dart';

enum DesktopLibraryFilter { recent, all, pdf, word, powerpoint, excel }

enum DesktopSortMode { date, name, size }

class _LibraryItem {
  const _LibraryItem({
    required this.path,
    required this.name,
    required this.modified,
    this.size,
    this.progress,
  });

  final String path;
  final String name;
  final DateTime modified;
  final int? size;
  final ReadingPosition? progress;

  String get extension {
    final dot = path.lastIndexOf('.');
    return dot == -1 ? '' : path.substring(dot).toLowerCase();
  }

  bool get isPdf => extension == '.pdf';
  bool get isWord => extension == '.docx' || extension == '.doc';
  bool get isPowerPoint => extension == '.pptx' || extension == '.ppt';
  bool get isExcel => extension == '.xlsx' || extension == '.xls';

  String get formatLabel {
    if (isPdf) return 'PDF';
    if (isWord) return extension == '.doc' ? 'DOC' : 'DOCX';
    if (isPowerPoint) return extension == '.ppt' ? 'PPT' : 'PPTX';
    if (isExcel) return extension == '.xls' ? 'XLS' : 'XLSX';
    return 'FILE';
  }
}

/// Pinned Home tab for Windows & Linux: collapsible filter sidebar + Grid/List
/// library view with quick search (Ctrl+K) and responsive laptop/desktop sizing.
class DesktopHomeView extends StatefulWidget {
  const DesktopHomeView({
    super.key,
    required this.onOpenFile,
    required this.onPickFile,
    required this.onOpenSettings,
    required this.searchFocusNode,
    required this.refreshTrigger,
  });

  final Future<void> Function(String path, String title) onOpenFile;
  final Future<void> Function() onPickFile;
  final VoidCallback onOpenSettings;
  final FocusNode searchFocusNode;
  final int refreshTrigger;

  @override
  State<DesktopHomeView> createState() => _DesktopHomeViewState();
}

class _DesktopHomeViewState extends State<DesktopHomeView> {
  DesktopLibraryFilter _filter = DesktopLibraryFilter.recent;
  DesktopSortMode _sortMode = DesktopSortMode.date;
  bool _isGridView = true;
  bool _sidebarExpanded = true;
  bool _isLoading = true;

  List<RecentFile> _recents = const [];
  List<DevicePdf> _deviceDocs = const [];
  List<String> _folders = const [];
  Map<String, ReadingPosition> _progress = const {};

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  @override
  void didUpdateWidget(covariant DesktopHomeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTrigger != widget.refreshTrigger) {
      _loadLibrary(showSpinner: false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLibrary({bool showSpinner = true}) async {
    if (showSpinner && mounted) {
      setState(() => _isLoading = true);
    }
    final recents = await RecentFilesStore.load();
    final progress = await ReadingProgress.all();
    final folders = await DevicePdfLibrary.loadFolders();
    final docs = await DevicePdfLibrary.listPdfs(folders);
    if (!mounted) return;
    setState(() {
      _recents = recents;
      _progress = progress;
      _folders = folders;
      _deviceDocs = docs;
      _isLoading = false;
    });
  }

  Future<void> _addFolder() async {
    await DevicePdfLibrary.addFolder();
    await _loadLibrary(showSpinner: false);
  }

  Future<void> _removeFolder(String folder) async {
    await DevicePdfLibrary.removeFolder(folder);
    await _loadLibrary(showSpinner: false);
  }

  List<_LibraryItem> _buildItems() {
    final map = <String, _LibraryItem>{};

    if (_filter == DesktopLibraryFilter.recent) {
      for (final r in _recents) {
        if (!File(r.path).existsSync()) continue;
        map[r.path] = _LibraryItem(
          path: r.path,
          name: EncodingUtils.cleanDisplayName(r.name),
          modified: r.openedAt,
          progress: _progress[r.path],
        );
      }
    } else {
      for (final d in _deviceDocs) {
        final p = d.path;
        if (p == null) continue;
        map[p] = _LibraryItem(
          path: p,
          name: d.name,
          modified: d.modified,
          size: d.size,
          progress: _progress[p],
        );
      }
      for (final r in _recents) {
        if (map.containsKey(r.path) || !File(r.path).existsSync()) continue;
        map[r.path] = _LibraryItem(
          path: r.path,
          name: EncodingUtils.cleanDisplayName(r.name),
          modified: r.openedAt,
          progress: _progress[r.path],
        );
      }
    }

    var items = map.values.where((item) {
      switch (_filter) {
        case DesktopLibraryFilter.recent:
        case DesktopLibraryFilter.all:
          return true;
        case DesktopLibraryFilter.pdf:
          return item.isPdf;
        case DesktopLibraryFilter.word:
          return item.isWord;
        case DesktopLibraryFilter.powerpoint:
          return item.isPowerPoint;
        case DesktopLibraryFilter.excel:
          return item.isExcel;
      }
    }).toList();

    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      items = items
          .where((item) => item.name.toLowerCase().contains(q))
          .toList();
    }

    items.sort((a, b) {
      switch (_sortMode) {
        case DesktopSortMode.date:
          return b.modified.compareTo(a.modified);
        case DesktopSortMode.name:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case DesktopSortMode.size:
          return (b.size ?? 0).compareTo(a.size ?? 0);
      }
    });

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final effectiveExpanded = width >= 960 ? _sidebarExpanded : false;
    final items = _buildItems();

    return Row(
      children: [
        _LibrarySidebar(
          expanded: effectiveExpanded,
          canToggle: width >= 960,
          activeFilter: _filter,
          folders: _folders,
          recentCount: _recents.length,
          allCount: _deviceDocs.length,
          onToggleExpanded: () =>
              setState(() => _sidebarExpanded = !_sidebarExpanded),
          onSelectFilter: (f) => setState(() => _filter = f),
          onAddFolder: _addFolder,
          onRemoveFolder: _removeFolder,
          onOpenSettings: widget.onOpenSettings,
        ),
        Expanded(
          child: Column(
            children: [
              _LibraryToolbar(
                searchController: _searchController,
                searchFocusNode: widget.searchFocusNode,
                searchQuery: _searchQuery,
                sortMode: _sortMode,
                isGridView: _isGridView,
                onSearchChanged: (v) => setState(() => _searchQuery = v),
                onSortChanged: (m) => setState(() => _sortMode = m),
                onToggleView: (grid) => setState(() => _isGridView = grid),
                onPickFile: widget.onPickFile,
                onRefresh: () => _loadLibrary(showSpinner: false),
              ),
              Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : items.isEmpty
                        ? _EmptyLibraryState(
                            hasSearch: _searchQuery.trim().isNotEmpty,
                            onPickFile: widget.onPickFile,
                            onAddFolder: _addFolder,
                            emptyTitle: 'No documents yet',
                          )
                        : _isGridView
                            ? _LibraryGrid(
                                items: items,
                                onOpenFile: widget.onOpenFile,
                              )
                            : _LibraryList(
                                items: items,
                                onOpenFile: widget.onOpenFile,
                              ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LibrarySidebar extends StatelessWidget {
  const _LibrarySidebar({
    required this.expanded,
    required this.canToggle,
    required this.activeFilter,
    required this.folders,
    required this.recentCount,
    required this.allCount,
    required this.onToggleExpanded,
    required this.onSelectFilter,
    required this.onAddFolder,
    required this.onRemoveFolder,
    required this.onOpenSettings,
  });

  final bool expanded;
  final bool canToggle;
  final DesktopLibraryFilter activeFilter;
  final List<String> folders;
  final int recentCount;
  final int allCount;
  final VoidCallback onToggleExpanded;
  final ValueChanged<DesktopLibraryFilter> onSelectFilter;
  final VoidCallback onAddFolder;
  final ValueChanged<String> onRemoveFolder;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: expanded ? 240 : 64,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
          right: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                if (expanded) ...[
                  Text(
                    'Library',
                    style: textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const Spacer(),
                ],
                if (canToggle)
                  IconButton(
                    icon: Icon(
                      expanded
                          ? Icons.chevron_left_rounded
                          : Icons.chevron_right_rounded,
                      size: 20,
                    ),
                    tooltip: expanded ? 'Collapse sidebar' : 'Expand sidebar',
                    onPressed: onToggleExpanded,
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                _SidebarNavTile(
                  expanded: expanded,
                  icon: Icons.history_rounded,
                  label: 'Recent',
                  count: recentCount,
                  selected: activeFilter == DesktopLibraryFilter.recent,
                  onTap: () => onSelectFilter(DesktopLibraryFilter.recent),
                ),
                _SidebarNavTile(
                  expanded: expanded,
                  icon: Icons.folder_copy_outlined,
                  label: 'All Documents',
                  count: allCount,
                  selected: activeFilter == DesktopLibraryFilter.all,
                  onTap: () => onSelectFilter(DesktopLibraryFilter.all),
                ),
                const SizedBox(height: 10),
                if (expanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
                    child: Text(
                      'FORMATS',
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                _SidebarNavTile(
                  expanded: expanded,
                  icon: Icons.picture_as_pdf_rounded,
                  label: 'PDF',
                  selected: activeFilter == DesktopLibraryFilter.pdf,
                  onTap: () => onSelectFilter(DesktopLibraryFilter.pdf),
                ),
                _SidebarNavTile(
                  expanded: expanded,
                  icon: Icons.description_outlined,
                  label: 'Word',
                  selected: activeFilter == DesktopLibraryFilter.word,
                  onTap: () => onSelectFilter(DesktopLibraryFilter.word),
                ),
                _SidebarNavTile(
                  expanded: expanded,
                  icon: Icons.slideshow_rounded,
                  label: 'PowerPoint',
                  selected: activeFilter == DesktopLibraryFilter.powerpoint,
                  onTap: () => onSelectFilter(DesktopLibraryFilter.powerpoint),
                ),
                _SidebarNavTile(
                  expanded: expanded,
                  icon: Icons.table_chart_outlined,
                  label: 'Excel',
                  selected: activeFilter == DesktopLibraryFilter.excel,
                  onTap: () => onSelectFilter(DesktopLibraryFilter.excel),
                ),
                if (expanded) ...[
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
                    child: Row(
                      children: [
                        Text(
                          'FOLDERS',
                          style: textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.create_new_folder_outlined,
                              size: 18),
                          tooltip: 'Add folder',
                          onPressed: onAddFolder,
                        ),
                      ],
                    ),
                  ),
                  if (folders.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: Text(
                        'Scanning Downloads & Documents',
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    for (final folder in folders)
                      ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.only(left: 10),
                        leading: const Icon(Icons.folder_outlined, size: 18),
                        title: Text(
                          folder.split(Platform.pathSeparator).last,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close_rounded, size: 16),
                          onPressed: () => onRemoveFolder(folder),
                        ),
                      ),
                ],
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                _SidebarNavTile(
                  expanded: expanded,
                  icon: isDark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                  label: isDark ? 'Paper Light' : 'Night Mode',
                  selected: false,
                  onTap: () => ThemePrefs.set(
                    isDark ? ThemeMode.light : ThemeMode.dark,
                  ),
                ),
                _SidebarNavTile(
                  expanded: expanded,
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  selected: false,
                  onTap: onOpenSettings,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarNavTile extends StatelessWidget {
  const _SidebarNavTile({
    required this.expanded,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final bool expanded;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = selected ? scheme.primaryContainer : Colors.transparent;
    final fg = selected ? scheme.onPrimaryContainer : scheme.onSurface;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppShape.radiusSmall),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppShape.radiusSmall),
          onTap: onTap,
          child: SizedBox(
            height: 38,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: expanded ? 10 : 0),
              child: Row(
                mainAxisAlignment: expanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 19,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  if (expanded) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: fg,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w500,
                            ),
                      ),
                    ),
                    if (count != null && count! > 0)
                      Text(
                        '$count',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LibraryToolbar extends StatelessWidget {
  const _LibraryToolbar({
    required this.searchController,
    required this.searchFocusNode,
    required this.searchQuery,
    required this.sortMode,
    required this.isGridView,
    required this.onSearchChanged,
    required this.onSortChanged,
    required this.onToggleView,
    required this.onPickFile,
    required this.onRefresh,
  });

  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final String searchQuery;
  final DesktopSortMode sortMode;
  final bool isGridView;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<DesktopSortMode> onSortChanged;
  final ValueChanged<bool> onToggleView;
  final Future<void> Function() onPickFile;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: scheme.surface,
      child: Row(
        children: [
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: TextField(
                controller: searchController,
                focusNode: searchFocusNode,
                onChanged: onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search documents… (Ctrl+K)',
                  prefixIcon: const Icon(Icons.search_rounded, size: 19),
                  suffixIcon: searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 17),
                          onPressed: () {
                            searchController.clear();
                            onSearchChanged('');
                          },
                        )
                      : null,
                  isDense: true,
                  filled: true,
                  fillColor: scheme.surfaceContainerLow,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppShape.radiusSmall),
                    borderSide: BorderSide(color: scheme.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppShape.radiusSmall),
                    borderSide: BorderSide(color: scheme.outlineVariant),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          PopupMenuButton<DesktopSortMode>(
            tooltip: 'Sort documents',
            initialValue: sortMode,
            onSelected: onSortChanged,
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: DesktopSortMode.date,
                child: Text('Sort by Date'),
              ),
              PopupMenuItem(
                value: DesktopSortMode.name,
                child: Text('Sort by Name'),
              ),
              PopupMenuItem(
                value: DesktopSortMode.size,
                child: Text('Sort by Size'),
              ),
            ],
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppShape.radiusSmall),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                children: [
                  const Icon(Icons.sort_rounded, size: 17),
                  const SizedBox(width: 6),
                  Text(
                    switch (sortMode) {
                      DesktopSortMode.date => 'Date',
                      DesktopSortMode.name => 'Name',
                      DesktopSortMode.size => 'Size',
                    },
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppShape.radiusSmall),
                ),
              ),
            ),
            segments: const [
              ButtonSegment(
                value: true,
                icon: Icon(Icons.grid_view_rounded, size: 17),
              ),
              ButtonSegment(
                value: false,
                icon: Icon(Icons.view_list_rounded, size: 17),
              ),
            ],
            selected: {isGridView},
            onSelectionChanged: (set) => onToggleView(set.first),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 19),
            tooltip: 'Refresh library',
            onPressed: onRefresh,
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onPickFile,
            icon: const Icon(Icons.folder_open_rounded, size: 18),
            label: const Text('Open File'),
          ),
        ],
      ),
    );
  }
}

class _LibraryGrid extends StatelessWidget {
  const _LibraryGrid({required this.items, required this.onOpenFile});

  final List<_LibraryItem> items;
  final Future<void> Function(String path, String title) onOpenFile;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        mainAxisExtent: 158,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _DocumentGridCard(
          item: item,
          onTap: () => onOpenFile(item.path, item.name),
        );
      },
    );
  }
}

class _DocumentGridCard extends StatelessWidget {
  const _DocumentGridCard({required this.item, required this.onTap});

  final _LibraryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final badgeColor = _badgeColor(item, scheme);

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppShape.radiusMedium),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppShape.radiusMedium),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppShape.radiusMedium),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (item.isPdf)
                    const PdfGlyph(size: 26)
                  else
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _formatIcon(item),
                        size: 17,
                        color: badgeColor,
                      ),
                    ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.formatLabel,
                      style: textTheme.labelSmall?.copyWith(
                        color: badgeColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (item.progress != null && item.progress!.pages > 0)
                    Text(
                      '${item.progress!.percent}%',
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (item.progress != null && item.progress!.pages > 0) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: item.progress!.progress.clamp(0.0, 1.0),
                    minHeight: 3,
                    backgroundColor: scheme.outlineVariant,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                _formatMeta(item),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryList extends StatelessWidget {
  const _LibraryList({required this.items, required this.onOpenFile});

  final List<_LibraryItem> items;
  final Future<void> Function(String path, String title) onOpenFile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final item = items[index];
        final badgeColor = _badgeColor(item, scheme);
        return Material(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppShape.radiusSmall),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppShape.radiusSmall),
            onTap: () => onOpenFile(item.path, item.name),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppShape.radiusSmall),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                children: [
                  if (item.isPdf)
                    const PdfGlyph(size: 22)
                  else
                    Icon(_formatIcon(item), size: 22, color: badgeColor),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          item.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.formatLabel,
                      style: textTheme.labelSmall?.copyWith(
                        color: badgeColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 110,
                    child: Text(
                      _formatMeta(item),
                      textAlign: TextAlign.right,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyLibraryState extends StatelessWidget {
  const _EmptyLibraryState({
    required this.hasSearch,
    required this.onPickFile,
    required this.onAddFolder,
    required this.emptyTitle,
  });

  final bool hasSearch;
  final Future<void> Function() onPickFile;
  final VoidCallback onAddFolder;
  final String emptyTitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PdfGlyph(size: 56),
              const SizedBox(height: 16),
              Text(
                hasSearch ? 'No matching documents' : emptyTitle,
                style: textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                hasSearch
                    ? 'Try a different keyword or switch filters in the sidebar.'
                    : 'Drop a PDF, Word, or PowerPoint file anywhere on this window, or open one from disk.',
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              if (!hasSearch) ...[
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: onPickFile,
                      style: FilledButton.styleFrom(
                        fixedSize: const Size(164, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      icon: const Icon(Icons.folder_open_rounded, size: 18),
                      label: const Text('Open File'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onAddFolder,
                      style: OutlinedButton.styleFrom(
                        fixedSize: const Size(164, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      icon: const Icon(
                        Icons.create_new_folder_outlined,
                        size: 18,
                      ),
                      label: const Text('Add Folder'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Color _badgeColor(_LibraryItem item, ColorScheme scheme) {
  if (item.isPdf) return AppPalette.signal;
  if (item.isWord) return const Color(0xFF2B6CB0);
  if (item.isPowerPoint) return const Color(0xFFD97706);
  if (item.isExcel) return const Color(0xFF15803D);
  return scheme.primary;
}

IconData _formatIcon(_LibraryItem item) {
  if (item.isPdf) return Icons.picture_as_pdf_rounded;
  if (item.isWord) return Icons.description_rounded;
  if (item.isPowerPoint) return Icons.slideshow_rounded;
  if (item.isExcel) return Icons.table_chart_rounded;
  return Icons.insert_drive_file_outlined;
}

String _formatMeta(_LibraryItem item) {
  final d = item.modified;
  final date =
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  final bytes = item.size;
  if (bytes == null || bytes <= 0) return date;
  if (bytes < 1024 * 1024) {
    return '$date · ${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '$date · ${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
