import 'package:flutter/material.dart';
import '../../services/preferences_service.dart';

/// Spotify-style elevated desktop dropdown for playlist sorting and view density.
class DesktopPlaylistSortDropdown {
  DesktopPlaylistSortDropdown._();

  /// Displays the anchored Spotify Sort & View Dropdown.
  static Future<void> show({
    required BuildContext context,
    required Offset globalPosition,
    required PlaylistSortOption currentSort,
    required PlaylistViewMode currentViewMode,
    required ValueChanged<PlaylistSortOption> onSortChanged,
    required ValueChanged<PlaylistViewMode> onViewModeChanged,
  }) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final overlayBox =
        overlay ??
        (Navigator.of(context).context.findRenderObject() as RenderBox);

    final position = RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
      Offset.zero & overlayBox.size,
    );

    final themeColor = PreferencesService().legibleThemeColor;

    final entries = <PopupMenuEntry<VoidCallback>>[
      // 1. "Sort by" Header
      const _DropdownHeaderEntry(title: 'Sort by'),

      // Sort Options
      for (final option in PlaylistSortOption.values)
        _DropdownItemEntry(
          title: option.label,
          isSelected: currentSort == option,
          activeColor: themeColor,
          onTap: () => onSortChanged(option),
        ),

      // 2. Hairline Divider
      const _DropdownDividerEntry(),

      // 3. "View as" Header
      const _DropdownHeaderEntry(title: 'View as'),

      // View Options
      _DropdownItemEntry(
        title: 'Compact',
        leadingIcon: Icons.density_small_rounded,
        isSelected: currentViewMode == PlaylistViewMode.compact,
        activeColor: themeColor,
        onTap: () => onViewModeChanged(PlaylistViewMode.compact),
      ),
      _DropdownItemEntry(
        title: 'List',
        leadingIcon: Icons.format_list_bulleted_rounded,
        isSelected: currentViewMode == PlaylistViewMode.list,
        activeColor: themeColor,
        onTap: () => onViewModeChanged(PlaylistViewMode.list),
      ),
    ];

    final selected = await showMenu<VoidCallback>(
      context: context,
      position: position,
      items: entries,
      elevation: 16.0,
      shadowColor: Colors.black.withValues(alpha: 0.60),
      color: const Color(0xFF181818),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
        side: BorderSide(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.0,
        ),
      ),
      constraints: const BoxConstraints(minWidth: 180.0, maxWidth: 220.0),
      clipBehavior: Clip.antiAlias,
    );

    selected?.call();
  }
}

class _DropdownHeaderEntry extends PopupMenuEntry<VoidCallback> {
  final String title;
  const _DropdownHeaderEntry({required this.title});

  @override
  double get height => 26.0;

  @override
  bool represents(VoidCallback? value) => false;

  @override
  State<_DropdownHeaderEntry> createState() => _DropdownHeaderEntryState();
}

class _DropdownHeaderEntryState extends State<_DropdownHeaderEntry> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14.0, 6.0, 14.0, 4.0),
      child: Text(
        widget.title,
        style: const TextStyle(
          color: Color(0xFFA3A3A3),
          fontSize: 11.0,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _DropdownDividerEntry extends PopupMenuEntry<VoidCallback> {
  const _DropdownDividerEntry();

  @override
  double get height => 13.0;

  @override
  bool represents(VoidCallback? value) => false;

  @override
  State<_DropdownDividerEntry> createState() => _DropdownDividerEntryState();
}

class _DropdownDividerEntryState extends State<_DropdownDividerEntry> {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1.0,
      color: Colors.white.withValues(alpha: 0.08),
      margin: const EdgeInsets.symmetric(vertical: 6.0),
    );
  }
}

class _DropdownItemEntry extends PopupMenuEntry<VoidCallback> {
  final String title;
  final IconData? leadingIcon;
  final bool isSelected;
  final Color activeColor;
  final VoidCallback onTap;

  const _DropdownItemEntry({
    required this.title,
    this.leadingIcon,
    required this.isSelected,
    required this.activeColor,
    required this.onTap,
  });

  @override
  double get height => 34.0;

  @override
  bool represents(VoidCallback? value) => value == onTap;

  @override
  State<_DropdownItemEntry> createState() => _DropdownItemEntryState();
}

class _DropdownItemEntryState extends State<_DropdownItemEntry> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final itemColor = widget.isSelected
        ? widget.activeColor
        : Colors.white.withValues(alpha: 0.88);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        onTap: () => Navigator.of(context).pop(widget.onTap),
        child: Container(
          height: 34.0,
          padding: const EdgeInsets.symmetric(horizontal: 14.0),
          color: _isHovered
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.transparent,
          child: Row(
            children: [
              if (widget.leadingIcon != null) ...[
                Icon(
                  widget.leadingIcon,
                  size: 16.0,
                  color: widget.isSelected
                      ? widget.activeColor
                      : Colors.white.withValues(alpha: 0.70),
                ),
                const SizedBox(width: 10.0),
              ],
              Expanded(
                child: Text(
                  widget.title,
                  style: TextStyle(
                    color: itemColor,
                    fontSize: 13.0,
                    fontWeight: widget.isSelected
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.isSelected)
                Icon(Icons.check, size: 16.0, color: widget.activeColor),
            ],
          ),
        ),
      ),
    );
  }
}
