import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../services/bug_report_service.dart';
import '../services/preferences_service.dart';
import '../services/web_attachment_helper.dart';

List<Uint8List> _prepareAttachmentsSync(List<Uint8List> raw) {
  return raw.where((b) => b.isNotEmpty).toList();
}

class BugAttachment {
  final Uint8List bytes;
  final String label;
  final bool isAppViewport;
  bool isEnabled;

  BugAttachment({
    required this.bytes,
    required this.label,
    this.isAppViewport = false,
    this.isEnabled = true,
  });
}

class BugReportSheet extends StatefulWidget {
  final Uint8List? screenshotBytes;
  final BugReportSnapshot? snapshot;

  const BugReportSheet({super.key, this.screenshotBytes, this.snapshot});

  @override
  State<BugReportSheet> createState() => _BugReportSheetState();
}

class _BugReportSheetState extends State<BugReportSheet> {
  final TextEditingController _textController = TextEditingController();
  final List<BugAttachment> _attachments = [];
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final initialBytes =
        widget.screenshotBytes ?? widget.snapshot?.screenshotBytes;
    if (initialBytes != null && initialBytes.isNotEmpty) {
      _attachments.add(
        BugAttachment(
          bytes: initialBytes,
          label: 'App Viewport',
          isAppViewport: true,
          isEnabled: true,
        ),
      );
    }
  }

  int get _wordCount {
    final text = _textController.text.trim();
    if (text.isEmpty) return 0;
    return text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }

  bool get _isWordCountValid => _wordCount >= 10;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _showPermissionWarningSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFFA2D48),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.white,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _pickImages() async {
    try {
      debugPrint('[BugReportSheet] Initiating image picker pipeline...');
      final picker = ImagePicker();
      List<XFile> pickedFiles = [];

      try {
        pickedFiles = await picker.pickMultiImage(
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 70,
        );
        debugPrint(
          '[BugReportSheet] pickMultiImage returned ${pickedFiles.length} files',
        );
      } on PlatformException catch (pe) {
        debugPrint(
          '[BugReportSheet] pickMultiImage PlatformException (${pe.code}): ${pe.message}',
        );
      } catch (e) {
        debugPrint('[BugReportSheet] pickMultiImage unsupported or threw: $e');
      }

      // Graceful fallback to single image picker if pickMultiImage returns empty or throws
      if (pickedFiles.isEmpty) {
        debugPrint(
          '[BugReportSheet] Falling back to pickImage(source: ImageSource.gallery)...',
        );
        try {
          final single = await picker.pickImage(
            source: ImageSource.gallery,
            maxWidth: 1024,
            maxHeight: 1024,
            imageQuality: 70,
          );
          if (single != null) {
            pickedFiles = [single];
            debugPrint('[BugReportSheet] Fallback pickImage acquired 1 file');
          } else {
            debugPrint('[BugReportSheet] User dismissed picker');
          }
        } on PlatformException catch (pe) {
          debugPrint(
            '[BugReportSheet] Fallback pickImage PlatformException (${pe.code}): ${pe.message}',
          );
          _showPermissionWarningSnackBar(
            'Storage permission denied. Please grant photo/storage permissions in device system settings.',
          );
          return;
        } catch (e) {
          debugPrint('[BugReportSheet] Fallback pickImage error: $e');
        }
      }

      if (pickedFiles.isEmpty) return;

      for (final file in pickedFiles) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          final nextIndex =
              _attachments.where((a) => !a.isAppViewport).length + 1;
          _attachments.add(
            BugAttachment(
              bytes: bytes,
              label: 'Attached #$nextIndex',
              isAppViewport: false,
              isEnabled: true,
            ),
          );
        }
      }

      if (!mounted) return;
      setState(() {});
    } on PlatformException catch (pe) {
      debugPrint(
        '[BugReportSheet] Uncaught PlatformException in picker pipeline: ${pe.code} - ${pe.message}',
      );
      _showPermissionWarningSnackBar(
        'Storage permission denied. Please grant photo/storage permissions in device system settings.',
      );
    } catch (e, stack) {
      debugPrint(
        '[BugReportSheet] Unexpected error during image selection: $e\n$stack',
      );
    }
  }

  Future<void> _copyAutoScreenshotToClipboard() async {
    final viewportAttachment = _attachments
        .where((a) => a.isAppViewport)
        .firstOrNull;
    if (viewportAttachment == null) return;

    final success = await copyImageToClipboardWeb(viewportAttachment.bytes);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF181818),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle_rounded : Icons.info_outline_rounded,
              color: success
                  ? const Color(0xFF1DB954)
                  : const Color(0xFFFFA726),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                success
                    ? 'Screenshot copied! Press Ctrl+V in your webmail to paste.'
                    : 'Could not copy to clipboard directly. Evidence bundle will download on send.',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _handleSubmit() async {
    if (!_isWordCountValid || _isSubmitting) return;

    setState(() => _isSubmitting = true);

    final rawAttachments = _attachments
        .where((a) => a.isEnabled)
        .map((a) => a.bytes)
        .toList();

    // Off-thread attachment preparation via compute()
    final enabledAttachments = rawAttachments.isEmpty
        ? <Uint8List>[]
        : await compute(_prepareAttachmentsSync, rawAttachments);

    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();

    messenger.showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF181818),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        content: const Row(
          children: [
            Icon(
              Icons.mark_email_read_outlined,
              color: Color(0xFFFA2D48),
              size: 22,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Opening your email client... Tap Send to deliver directly to Charan.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 4),
      ),
    );

    await BugReportService.instance.sendDirectReport(
      userDescription: _textController.text.trim(),
      attachments: enabledAttachments,
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = PreferencesService().themeColor;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1.5,
          ),
          left: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
          right: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: bottomInset > 0 ? bottomInset + 16 : 28,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle pill
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Header Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF181818),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: const Icon(
                    Icons.bug_report_rounded,
                    color: Color(0xFFFA2D48),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Report an Issue',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white70,
                    size: 22,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Multi-Screenshot Horizontal Thumbnail Strip
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: _attachments.length + 1,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  // Add Attachment Tile at the end of the strip
                  if (index == _attachments.length) {
                    return Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: const Color(0xFF181818),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                          width: 1,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: _pickImages,
                          borderRadius: BorderRadius.circular(12),
                          splashColor: const Color(
                            0xFFFA2D48,
                          ).withValues(alpha: 0.15),
                          highlightColor: Colors.white.withValues(alpha: 0.05),
                          mouseCursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            child: const SizedBox(
                              width: 84,
                              height: 84,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.add_photo_alternate_rounded,
                                    color: Colors.white70,
                                    size: 24,
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    "Add image",
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.white60,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  final item = _attachments[index];
                  return Container(
                    width: 110,
                    height: 84,
                    decoration: BoxDecoration(
                      color: const Color(0xFF181818),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: item.isEnabled
                            ? const Color(0xFFFA2D48)
                            : Colors.white.withValues(alpha: 0.08),
                        width: 1.5,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Opacity(
                          opacity: item.isEnabled ? 1.0 : 0.3,
                          child: Image.memory(item.bytes, fit: BoxFit.cover),
                        ),
                        // Top-left badge: Auto or Custom
                        Positioned(
                          top: 5,
                          left: 5,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.isAppViewport ? 'Auto' : item.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        // Top-right action: Toggle or Delete
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () {
                              if (item.isAppViewport) {
                                setState(
                                  () => item.isEnabled = !item.isEnabled,
                                );
                              } else {
                                setState(() => _attachments.removeAt(index));
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                item.isAppViewport
                                    ? (item.isEnabled
                                          ? Icons.check_circle_rounded
                                          : Icons
                                                .radio_button_unchecked_rounded)
                                    : Icons.close_rounded,
                                size: 14,
                                color: item.isAppViewport
                                    ? (item.isEnabled
                                          ? const Color(0xFFFA2D48)
                                          : Colors.white70)
                                    : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (kIsWeb) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                  icon: const Icon(
                    Icons.copy_rounded,
                    size: 14,
                    color: Color(0xFFFA2D48),
                  ),
                  label: const Text(
                    'Copy auto-screenshot to clipboard',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  onPressed: _copyAutoScreenshotToClipboard,
                ),
              ),
            ],
            const SizedBox(height: 16),

            // Description Text Field
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0B0B0F),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _isWordCountValid
                      ? const Color(0xFF1DB954).withValues(alpha: 0.4)
                      : Colors.white.withValues(alpha: 0.08),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: TextField(
                controller: _textController,
                maxLines: 4,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.4,
                ),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText:
                      'What happened? What were you trying to play? (Minimum 10 words)',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 13,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Live Word Counter
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isWordCountValid
                      ? 'Detailed reproduction provided'
                      : 'Please provide more details on what failed',
                  style: TextStyle(
                    color: _isWordCountValid
                        ? const Color(0xFF1DB954)
                        : Colors.white.withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
                ),
                Text(
                  '$_wordCount / 10 words required',
                  style: TextStyle(
                    color: _isWordCountValid
                        ? const Color(0xFF1DB954)
                        : const Color(0xFFFFA726),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Submit Button
            AnimatedOpacity(
              opacity: (_isWordCountValid && !_isSubmitting) ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 200),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [themeColor, const Color(0xFFFA2D48)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: _isWordCountValid
                      ? [
                          BoxShadow(
                            color: themeColor.withValues(alpha: 0.25),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: (_isWordCountValid && !_isSubmitting)
                        ? _handleSubmit
                        : null,
                    child: Center(
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.mark_email_read_outlined,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  kIsWeb
                                      ? 'Download Bundle & Open Mail'
                                      : 'Launch Mail Client',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
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
    );
  }
}
