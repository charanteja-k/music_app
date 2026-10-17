import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../layouts/desktop_layout_state.dart';
import '../../services/api_config.dart';
import '../../services/app_file_picker.dart';
import '../../services/spotify_import_service.dart';

/// Opens the unified desktop & web Spotify / Exportify import dialog.
Future<void> showDesktopImportModal(BuildContext context) {
  return showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.75),
    builder: (context) => const DesktopImportModal(),
  );
}

/// Unified Spotify and Exportify Playlist Import Modal for Web and Desktop.
///
/// Supports:
/// 1. Direct Exportify CSV / ZIP file selection using in-memory bytes (web-safe, no dart:io File dependency).
/// 2. Direct Spotify Playlist URL or raw CSV text copy-paste well (zero-failure bypass).
/// 3. Live real-time resolution progress monitoring under browser connection limits.
class DesktopImportModal extends StatefulWidget {
  const DesktopImportModal({super.key});

  @override
  State<DesktopImportModal> createState() => _DesktopImportModalState();
}

class _DesktopImportModalState extends State<DesktopImportModal>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _pasteController = TextEditingController();
  final TextEditingController _playlistNameController = TextEditingController();

  String? _pickedFileName;
  List<ExportifyTrack> _parsedFileTracks = [];
  List<ExportifyPlaylist> _parsedZipPlaylists = [];
  bool _isReadingFile = false;
  bool _isFetchingUrl = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pasteController.dispose();
    _playlistNameController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // 1. FILE PICKER ACTION (Web & Desktop Safe)
  // ===========================================================================
  Future<void> _pickFile() async {
    setState(() {
      _isReadingFile = true;
      _errorMessage = null;
    });

    try {
      final picked = await pickMusicArchiveOrCsv();
      if (picked == null) {
        setState(() => _isReadingFile = false);
        return;
      }

      final fileName = picked.name;
      final bytes = picked.bytes;

      if (bytes.isEmpty) {
        setState(() {
          _errorMessage = 'Selected file is empty.';
          _isReadingFile = false;
        });
        return;
      }

      if (fileName.toLowerCase().endsWith('.zip')) {
        final playlists = ExportifyCsvParser.parseZipBytes(bytes);
        if (playlists.isEmpty) {
          setState(() {
            _errorMessage = 'No CSV playlists found inside this .zip archive.';
            _isReadingFile = false;
          });
          return;
        }

        setState(() {
          _pickedFileName = fileName;
          _parsedZipPlaylists = playlists;
          _parsedFileTracks = [];
          _isReadingFile = false;
          _playlistNameController.text =
              '${playlists.length} Exportify Playlists';
        });
      } else {
        final content = utf8.decode(bytes, allowMalformed: true);
        final tracks = ExportifyCsvParser.parse(content);

        if (tracks.isEmpty) {
          setState(() {
            _errorMessage =
                'Could not parse any tracks from this CSV. Check column headers.';
            _isReadingFile = false;
          });
          return;
        }

        final cleanName = fileName.replaceAll(
          RegExp(r'\.csv$', caseSensitive: false),
          '',
        );

        setState(() {
          _pickedFileName = fileName;
          _parsedFileTracks = tracks;
          _parsedZipPlaylists = [];
          _isReadingFile = false;
          if (_playlistNameController.text.trim().isEmpty) {
            _playlistNameController.text = cleanName;
          }
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error reading file: $e';
        _isReadingFile = false;
      });
    }
  }

  // ===========================================================================
  // 2. START IMPORT
  // ===========================================================================
  Future<void> _startFileImport() async {
    final service = SpotifyImportService();
    if (service.isImporting) return;

    if (_parsedZipPlaylists.isNotEmpty) {
      final selected = _parsedZipPlaylists
          .where((p) => p.tracks.isNotEmpty)
          .toList();
      if (selected.isEmpty) return;
      await service.startBackgroundMultiImport(
        playlists: selected,
        calibrateTaste: true,
      );
    } else if (_parsedFileTracks.isNotEmpty) {
      final name = _playlistNameController.text.trim().isNotEmpty
          ? _playlistNameController.text.trim()
          : 'Exportify Mix';
      await service.startBackgroundSingleImport(
        playlistName: name,
        tracks: _parsedFileTracks,
        calibrateTaste: true,
      );
    }
  }

  Future<void> _startPasteImport() async {
    final rawText = _pasteController.text.trim();
    if (rawText.isEmpty) {
      setState(
        () => _errorMessage =
            'Please paste a Spotify playlist URL or Exportify CSV content.',
      );
      return;
    }

    setState(() {
      _errorMessage = null;
    });

    final isSpotifyUrl =
        rawText.contains('spotify.com/playlist') ||
        rawText.contains('spotify:playlist:');

    if (isSpotifyUrl) {
      await _importSpotifyUrl(rawText);
    } else {
      // Parse as raw CSV text
      final tracks = ExportifyCsvParser.parse(rawText);
      if (tracks.isEmpty) {
        setState(() {
          _errorMessage =
              'Could not recognize any songs. Please verify the CSV format or paste a valid link.';
        });
        return;
      }

      final name = _playlistNameController.text.trim().isNotEmpty
          ? _playlistNameController.text.trim()
          : 'Exportify Mix';

      await SpotifyImportService().startBackgroundSingleImport(
        playlistName: name,
        tracks: tracks,
        calibrateTaste: true,
      );
    }
  }

  String _extractPlaylistId(String input) {
    final clean = input.trim();
    final regex = RegExp(r'(?:playlist[/:])?([a-zA-Z0-9]{22})');
    final match = regex.firstMatch(clean);
    if (match != null && match.groupCount >= 1) {
      return match.group(1)!;
    }
    return clean;
  }

  Future<void> _importSpotifyUrl(String url) async {
    setState(() => _isFetchingUrl = true);
    final playlistId = _extractPlaylistId(url);

    try {
      Map<String, dynamic>? data;

      // 1. Direct on-device embed scrape on non-web
      if (!kIsWeb) {
        try {
          final embedUrl = Uri.parse(
            'https://open.spotify.com/embed/playlist/$playlistId',
          );
          final res = await http
              .get(
                embedUrl,
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                  'Accept':
                      'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                },
              )
              .timeout(const Duration(seconds: 10));

          if (res.statusCode == 200) {
            final html = res.body;
            final match = RegExp(
              r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>',
            ).firstMatch(html);
            if (match != null && match.groupCount >= 1) {
              final parsed = json.decode(match.group(1)!);
              final entity =
                  parsed['props']?['pageProps']?['state']?['data']?['entity'];
              if (entity != null) {
                final name = entity['name'] as String? ?? 'Spotify Playlist';
                final rawList = List<dynamic>.from(entity['trackList'] ?? []);
                final List<String> tracks = [];
                for (final item in rawList) {
                  if (item is Map) {
                    final title = (item['title'] as String? ?? '').trim();
                    final subtitle = (item['subtitle'] as String? ?? '')
                        .replaceAll('\u00a0', ' ')
                        .trim();
                    if (title.isNotEmpty) {
                      tracks.add('$title $subtitle'.trim());
                    }
                  }
                }
                if (tracks.isNotEmpty) {
                  data = {'name': name, 'tracks': tracks};
                }
              }
            }
          }
        } catch (_) {}
      }

      // 2. Backend API fallback
      if (data == null) {
        try {
          final res = await http
              .post(
                Uri.parse('${ApiConfig.baseUrl}/spotify/import'),
                headers: {'Content-Type': 'application/json'},
                body: json.encode({
                  'playlist_id': playlistId,
                  'is_public': true,
                }),
              )
              .timeout(const Duration(seconds: 15));

          if (res.statusCode == 200) {
            data = json.decode(res.body);
          }
        } catch (_) {}
      }

      if (data == null || (data['tracks'] as List?)?.isEmpty == true) {
        setState(() {
          _errorMessage =
              'Could not fetch playlist. Please ensure it is Public, or use "Exportify CSV" to export and upload.';
          _isFetchingUrl = false;
        });
        return;
      }

      final tracks = List<String>.from(data['tracks'] ?? []);
      final fetchedName =
          (data['name'] as String?) ??
          (_playlistNameController.text.trim().isNotEmpty
              ? _playlistNameController.text.trim()
              : 'Spotify Playlist');

      setState(() => _isFetchingUrl = false);

      await SpotifyImportService().startBackgroundUrlImport(
        playlistId: playlistId,
        playlistName: fetchedName,
        rawTrackQueries: tracks,
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Error fetching playlist: $e';
        _isFetchingUrl = false;
      });
    }
  }

  // ===========================================================================
  // 3. UI RENDERING
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    final importService = SpotifyImportService();

    return AnimatedBuilder(
      animation: importService,
      builder: (context, _) {
        final isImporting = importService.isImporting;
        final hasFinished = importService.hasFinished;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24.0,
            vertical: 24.0,
          ),
          child: Container(
            width: 540.0,
            constraints: const BoxConstraints(maxHeight: 620.0),
            decoration: BoxDecoration(
              color: const Color(0xFF18181F),
              borderRadius: BorderRadius.circular(12.0),
              border: Border.all(color: const Color(0xFF282836), width: 1.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.7),
                  blurRadius: 30.0,
                  offset: const Offset(0, 15),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Modal Header
                _buildModalHeader(context, isImporting),

                if (isImporting)
                  Expanded(child: _buildProgressView(importService))
                else if (hasFinished)
                  Expanded(child: _buildFinishedView(context, importService))
                else ...[
                  // Tab selector
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20.0),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Color(0xFF282836),
                          width: 1.0,
                        ),
                      ),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicatorColor: const Color(0xFF1DB954),
                      indicatorWeight: 2.5,
                      labelColor: Colors.white,
                      unselectedLabelColor: const Color(0xFFA3A3A3),
                      labelStyle: const TextStyle(
                        fontSize: 13.0,
                        fontWeight: FontWeight.w600,
                      ),
                      tabs: const [
                        Tab(text: 'Upload Exportify CSV'),
                        Tab(text: 'Paste Spotify URL / CSV Content'),
                      ],
                    ),
                  ),

                  // Error Banner
                  if (_errorMessage != null)
                    Container(
                      margin: const EdgeInsets.fromLTRB(20.0, 12.0, 20.0, 0.0),
                      padding: const EdgeInsets.all(10.0),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8.0),
                        border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: Colors.redAccent,
                            size: 18.0,
                          ),
                          const SizedBox(width: 8.0),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Tab Contents
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [_buildFileUploadTab(), _buildPasteTab()],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildModalHeader(BuildContext context, bool isImporting) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20.0, 16.0, 16.0, 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 32.0,
                height: 32.0,
                decoration: BoxDecoration(
                  color: const Color(0xFF1DB954).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.sync_alt_rounded,
                  color: Color(0xFF1DB954),
                  size: 18.0,
                ),
              ),
              const SizedBox(width: 10.0),
              const Text(
                'Import Playlist',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16.0,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, color: Colors.white60),
            onPressed: () {
              if (SpotifyImportService().hasFinished) {
                SpotifyImportService().resetFinishedState();
              }
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 1: FILE UPLOAD
  // ===========================================================================
  Widget _buildFileUploadTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Upload dropzone well
          InkWell(
            onTap: _isReadingFile ? null : _pickFile,
            borderRadius: BorderRadius.circular(10.0),
            child: Container(
              height: 140.0,
              decoration: BoxDecoration(
                color: const Color(0xFF121217),
                borderRadius: BorderRadius.circular(10.0),
                border: Border.all(
                  color: _pickedFileName != null
                      ? const Color(0xFF1DB954)
                      : Colors.white.withValues(alpha: 0.12),
                  width: 1.5,
                ),
              ),
              child: _isReadingFile
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF1DB954),
                        strokeWidth: 2.5,
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _pickedFileName != null
                              ? Icons.check_circle_outline_rounded
                              : Icons.file_upload_outlined,
                          size: 36.0,
                          color: _pickedFileName != null
                              ? const Color(0xFF1DB954)
                              : const Color(0xFFA3A3A3),
                        ),
                        const SizedBox(height: 10.0),
                        Text(
                          _pickedFileName ??
                              'Click to select Exportify .csv or .zip file',
                          style: TextStyle(
                            color: _pickedFileName != null
                                ? Colors.white
                                : const Color(0xFFE0E0E0),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4.0),
                        Text(
                          _parsedZipPlaylists.isNotEmpty
                              ? 'Found ${_parsedZipPlaylists.length} playlists'
                              : (_parsedFileTracks.isNotEmpty
                                    ? 'Found ${_parsedFileTracks.length} tracks'
                                    : 'Supports Exportify, Soundiiz, and TuneMyMusic exports'),
                          style: const TextStyle(
                            color: Color(0xFF737373),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
            ),
          ),

          const SizedBox(height: 16.0),

          // Playlist Name Field
          TextField(
            controller: _playlistNameController,
            style: const TextStyle(color: Colors.white, fontSize: 13.0),
            decoration: InputDecoration(
              labelText: 'Playlist Name',
              labelStyle: const TextStyle(
                color: Color(0xFFA3A3A3),
                fontSize: 12.0,
              ),
              filled: true,
              fillColor: const Color(0xFF0E0E12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
                borderSide: const BorderSide(color: Color(0xFF1DB954)),
              ),
            ),
          ),

          const SizedBox(height: 20.0),

          // Action Button
          ElevatedButton.icon(
            icon: const Icon(Icons.download_rounded, size: 18.0),
            label: Text(
              _parsedZipPlaylists.isNotEmpty
                  ? 'Import ${_parsedZipPlaylists.length} Playlists'
                  : 'Import Playlist (${_parsedFileTracks.length} Tracks)',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1DB954),
              foregroundColor: Colors.black,
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.1),
              disabledForegroundColor: Colors.white38,
              padding: const EdgeInsets.symmetric(vertical: 14.0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
            ),
            onPressed:
                (_parsedFileTracks.isEmpty && _parsedZipPlaylists.isEmpty)
                ? null
                : _startFileImport,
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 2: PASTE URL OR CSV
  // ===========================================================================
  Widget _buildPasteTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Paste Public Spotify Playlist Link or CSV text:',
            style: TextStyle(
              color: Color(0xFFA3A3A3),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8.0),

          // Recessed Dark Obsidian Text Well (#0E0E12)
          Container(
            height: 140.0,
            decoration: BoxDecoration(
              color: const Color(0xFF0E0E12),
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1.0,
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 8.0,
            ),
            child: TextField(
              controller: _pasteController,
              maxLines: null,
              expands: true,
              style: const TextStyle(color: Colors.white, fontSize: 12.5),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText:
                    'https://open.spotify.com/playlist/...\nOR paste CSV lines copied from Exportify',
                hintStyle: TextStyle(color: Color(0xFF555555), fontSize: 12.0),
              ),
            ),
          ),

          const SizedBox(height: 16.0),

          // Playlist Name Field
          TextField(
            controller: _playlistNameController,
            style: const TextStyle(color: Colors.white, fontSize: 13.0),
            decoration: InputDecoration(
              labelText: 'Playlist Name (Optional)',
              labelStyle: const TextStyle(
                color: Color(0xFFA3A3A3),
                fontSize: 12.0,
              ),
              filled: true,
              fillColor: const Color(0xFF0E0E12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
                borderSide: const BorderSide(color: Color(0xFF1DB954)),
              ),
            ),
          ),

          const SizedBox(height: 20.0),

          // Action Button
          ElevatedButton.icon(
            icon: _isFetchingUrl
                ? const SizedBox(
                    width: 16.0,
                    height: 16.0,
                    child: CircularProgressIndicator(
                      color: Colors.black,
                      strokeWidth: 2.0,
                    ),
                  )
                : const Icon(Icons.download_rounded, size: 18.0),
            label: Text(
              _isFetchingUrl ? 'Resolving Playlist...' : 'Resolve & Import',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1DB954),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14.0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
            ),
            onPressed: _isFetchingUrl ? null : _startPasteImport,
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // PROGRESS VIEW (Active Resolution)
  // ===========================================================================
  Widget _buildProgressView(SpotifyImportService service) {
    final progress = service.overallProgress.clamp(0.0, 1.0);
    final processed = service.processedTracks;
    final total = service.totalTracks;
    final currentSong = service.currentTrackName;

    return Padding(
      padding: const EdgeInsets.all(28.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Resolving tracks: $processed / $total',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.0,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${(progress * 100).toInt()}%',
                style: const TextStyle(
                  color: Color(0xFF1DB954),
                  fontSize: 14.0,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12.0),

          ClipRRect(
            borderRadius: BorderRadius.circular(4.0),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8.0,
              backgroundColor: const Color(0xFF282836),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF1DB954),
              ),
            ),
          ),

          const SizedBox(height: 16.0),

          if (currentSong.isNotEmpty)
            Text(
              'Current: $currentSong',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFA3A3A3), fontSize: 12.5),
            ),

          const SizedBox(height: 24.0),

          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.cancel_outlined, size: 16.0),
              label: const Text('Cancel Import'),
              style: TextButton.styleFrom(foregroundColor: Colors.white60),
              onPressed: () {
                service.cancelImport();
              },
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // FINISHED VIEW (Success)
  // ===========================================================================
  Widget _buildFinishedView(
    BuildContext context,
    SpotifyImportService service,
  ) {
    final successCount = service.lastSuccessCount;
    final playlistName = service.lastImportedPlaylistName ?? 'Playlist';
    final playlistId = service.lastImportedPlaylistId;

    return Padding(
      padding: const EdgeInsets.all(28.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 56.0,
            color: Color(0xFF1DB954),
          ),
          const SizedBox(height: 16.0),

          const Text(
            'Import Complete!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 18.0,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8.0),

          Text(
            'Imported $successCount tracks into "$playlistName"',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFA3A3A3), fontSize: 13.5),
          ),

          const SizedBox(height: 28.0),

          if (playlistId != null && playlistId.isNotEmpty)
            ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow_rounded, size: 20.0),
              label: const Text('Open Playlist'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1DB954),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
              onPressed: () {
                service.resetFinishedState();
                DesktopLayoutState.openPlaylist(playlistId);
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
    );
  }
}
