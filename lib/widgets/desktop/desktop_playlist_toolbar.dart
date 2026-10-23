import 'package:flutter/material.dart';
import '../../services/preferences_service.dart';
import 'desktop_playlist_sort_dropdown.dart';

/// Spotify-style desktop playlist sub-header action bar.
///
/// Features left-aligned Stadium pill buttons ("+ Add", "Name & details")
/// and right-aligned inline search toggle with floating "Sort by / View as" dropdown.
class DesktopPlaylistToolbar extends StatefulWidget {
  final VoidCallback? onAddTap;
  final VoidCallback? onEditDetailsTap;
  final bool showAddButton;
  final bool showEditDetailsButton;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final PlaylistSortOption currentSort;
  final PlaylistViewMode currentViewMode;
  final ValueChanged<PlaylistSortOption> onSortChanged;
  final ValueChanged<PlaylistViewMode> onViewModeChanged;

  const DesktopPlaylistToolbar({
    super.key,
    this.onAddTap,
    this.onEditDetailsTap,
    this.showAddButton = true,
    this.showEditDetailsButton = true,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.currentSort,
    required this.currentViewMode,
    required this.onSortChanged,
    required this.onViewModeChanged,
  });

  @override
  State<DesktopPlaylistToolbar> createState() => _DesktopPlaylistToolbarState();
}

class _DesktopPlaylistToolbarState extends State<DesktopPlaylistToolbar> {
  bool _isSearchExpanded = false;
  late final TextEditingController _searchCtrl;
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _sortButtonKey = GlobalKey();

  bool _isSearchHovered = false;
  bool _isSortHovered = false;
  bool _isAddHovered = false;
  bool _isEditHovered = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(text: widget.searchQuery);
    _isSearchExpanded = widget.searchQuery.isNotEmpty;
  }

  @override
  void didUpdateWidget(covariant DesktopPlaylistToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != _searchCtrl.text) {
      _searchCtrl.text = widget.searchQuery;
      if (widget.searchQuery.isNotEmpty && !_isSearchExpanded) {
        _isSearchExpanded = true;
      }
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _isSearchExpanded = !_isSearchExpanded;
      if (_isSearchExpanded) {
        _focusNode.requestFocus();
      } else {
        _searchCtrl.clear();
        widget.onSearchChanged('');
        _focusNode.unfocus();
      }
    });
  }

  void _openSortDropdown() {
    final renderBox =
        _sortButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final globalPosition = Offset(offset.dx, offset.dy + size.height + 4.0);

    DesktopPlaylistSortDropdown.show(
      context: context,
      globalPosition: globalPosition,
      currentSort: widget.currentSort,
      currentViewMode: widget.currentViewMode,
      onSortChanged: widget.onSortChanged,
      onViewModeChanged: widget.onViewModeChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44.0,
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // ─── Left Action Group ───────────────────────────────────────────
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showAddButton) ...[
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) => setState(() => _isAddHovered = true),
                  onExit: (_) => setState(() => _isAddHovered = false),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20.0),
                    onTap: widget.onAddTap,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14.0,
                        vertical: 6.0,
                      ),
                      decoration: BoxDecoration(
                        color: _isAddHovered
                            ? const Color(0xFF282828)
                            : const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(20.0),
                        border: Border.all(
                          color: _isAddHovered
                              ? Colors.white.withValues(alpha: 0.25)
                              : Colors.white.withValues(alpha: 0.12),
                          width: 1.0,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, size: 16.0, color: Colors.white),
                          SizedBox(width: 6.0),
                          Text(
                            'Add',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13.0,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8.0),
              ],

              if (widget.showEditDetailsButton) ...[
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) => setState(() => _isEditHovered = true),
                  onExit: (_) => setState(() => _isEditHovered = false),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20.0),
                    onTap: widget.onEditDetailsTap,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14.0,
                        vertical: 6.0,
                      ),
                      decoration: BoxDecoration(
                        color: _isEditHovered
                            ? const Color(0xFF282828)
                            : const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(20.0),
                        border: Border.all(
                          color: _isEditHovered
                              ? Colors.white.withValues(alpha: 0.25)
                              : Colors.white.withValues(alpha: 0.12),
                          width: 1.0,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.drive_file_rename_outline_rounded,
                            size: 15.0,
                            color: Colors.white,
                          ),
                          SizedBox(width: 6.0),
                          Text(
                            'Name & details',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13.0,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),

          // ─── Right Action Group ──────────────────────────────────────────
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Inline Search Box / Search Toggle Icon
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                width: _isSearchExpanded ? 200.0 : 34.0,
                height: 32.0,
                decoration: BoxDecoration(
                  color: _isSearchExpanded
                      ? const Color(0xFF222222)
                      : (_isSearchHovered
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.transparent),
                  borderRadius: BorderRadius.circular(16.0),
                  border: _isSearchExpanded
                      ? Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                          width: 1.0,
                        )
                      : null,
                ),
                child: _isSearchExpanded
                    ? Row(
                        children: [
                          const SizedBox(width: 8.0),
                          const Icon(
                            Icons.search_rounded,
                            size: 16.0,
                            color: Color(0xFFB3B3B3),
                          ),
                          const SizedBox(width: 6.0),
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              focusNode: _focusNode,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.0,
                              ),
                              cursorColor: Colors.white,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                hintText: 'Search in playlist',
                                hintStyle: TextStyle(
                                  color: Color(0xFF757575),
                                  fontSize: 12.5,
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                              onChanged: widget.onSearchChanged,
                            ),
                          ),
                          InkWell(
                            borderRadius: BorderRadius.circular(12.0),
                            onTap: _toggleSearch,
                            child: const Padding(
                              padding: EdgeInsets.all(4.0),
                              child: Icon(
                                Icons.close_rounded,
                                size: 15.0,
                                color: Color(0xFFB3B3B3),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4.0),
                        ],
                      )
                    : MouseRegion(
                        cursor: SystemMouseCursors.click,
                        onEnter: (_) => setState(() => _isSearchHovered = true),
                        onExit: (_) => setState(() => _isSearchHovered = false),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.search_rounded,
                            size: 20.0,
                            color: _isSearchHovered
                                ? Colors.white
                                : const Color(0xFFB3B3B3),
                          ),
                          tooltip: 'Search in playlist',
                          onPressed: _toggleSearch,
                        ),
                      ),
              ),

              const SizedBox(width: 16.0),

              // Sort / View Trigger Button
              MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _isSortHovered = true),
                onExit: (_) => setState(() => _isSortHovered = false),
                child: InkWell(
                  key: _sortButtonKey,
                  borderRadius: BorderRadius.circular(6.0),
                  onTap: _openSortDropdown,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 6.0,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.currentSort.label,
                          style: TextStyle(
                            color: _isSortHovered
                                ? Colors.white
                                : const Color(0xFFB3B3B3),
                            fontSize: 13.0,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4.0),
                        Icon(
                          Icons.arrow_drop_down_rounded,
                          size: 18.0,
                          color: _isSortHovered
                              ? Colors.white
                              : const Color(0xFFB3B3B3),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
