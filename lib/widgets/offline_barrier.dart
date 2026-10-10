import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Context-aware offline barrier preventing failed network calls on stream-dependent screens
/// and offering a direct 1-tap shortcut to Downloads.
class OfflineBarrier extends StatelessWidget {
  final VoidCallback onGoToDownloads;
  final String? message;

  const OfflineBarrier({
    super.key,
    required this.onGoToDownloads,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF161622),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFFFB74D).withValues(alpha: 0.35),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFB74D).withValues(alpha: 0.12),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                size: 38,
                color: Color(0xFFFFB74D),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'You are offline',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message ??
                  'Search & streaming require an active internet connection. All your downloaded music is ready for zero-data playback.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                onGoToDownloads();
              },
              icon: const Icon(
                Icons.download_done_rounded,
                color: Colors.black,
                size: 18,
              ),
              label: const Text(
                'Go to Downloads',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                elevation: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
