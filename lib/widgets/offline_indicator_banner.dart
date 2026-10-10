import 'package:flutter/material.dart';
import '../constants/app_theme_tokens.dart';
import '../services/connectivity_service.dart';

/// Non-intrusive persistent offline notification banner directing user to Downloads.
class OfflineIndicatorBanner extends StatefulWidget {
  final VoidCallback onGoToDownloads;
  final bool? isOfflineOverride;

  const OfflineIndicatorBanner({
    super.key,
    required this.onGoToDownloads,
    this.isOfflineOverride,
  });

  @override
  State<OfflineIndicatorBanner> createState() => _OfflineIndicatorBannerState();
}

class _OfflineIndicatorBannerState extends State<OfflineIndicatorBanner> {
  final ConnectivityService _connectivity = ConnectivityService();
  bool _isDismissed = false;

  @override
  void initState() {
    super.initState();
    _connectivity.addListener(_onConnectivityChanged);
    _connectivity.init();
  }

  @override
  void dispose() {
    _connectivity.removeListener(_onConnectivityChanged);
    super.dispose();
  }

  void _onConnectivityChanged() {
    if (mounted) {
      if (_connectivity.isOnline) {
        setState(() => _isDismissed = false);
      } else {
        setState(() {});
      }
    }
  }

  bool get _effectiveOffline =>
      widget.isOfflineOverride ?? _connectivity.isOffline;

  @override
  Widget build(BuildContext context) {
    if (!_effectiveOffline || _isDismissed) {
      return const SizedBox.shrink();
    }

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF161622).withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFFFFB74D).withValues(alpha: 0.35),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB74D).withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.wifi_off_rounded,
                  color: Color(0xFFFFB74D),
                  size: 15,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'You are offline',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      'Playing from Downloads',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: widget.onGoToDownloads,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppThemeTokens.brandRuby,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Downloads',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 12,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () {
                  setState(() => _isDismissed = true);
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.white10,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 13,
                    color: Colors.white60,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
