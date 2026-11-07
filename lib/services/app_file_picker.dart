import 'dart:typed_data';
import 'app_file_picker_stub.dart'
    if (dart.library.js_interop) 'app_file_picker_web.dart'
    as picker;

class AppPickedFile {
  final String name;
  final Uint8List bytes;

  const AppPickedFile({required this.name, required this.bytes});
}

/// Cross-platform picker for Exportify .csv and .zip playlist archives.
/// Uses native browser HTML5 File API on Web / PWA (zero plugin registration issues)
/// and file_picker on Android / iOS / Desktop.
Future<AppPickedFile?> pickMusicArchiveOrCsv() =>
    picker.pickMusicArchiveOrCsv();

/// Cross-platform picker for images (jpg, jpeg, png, webp).
/// Uses native browser HTML5 File API on Web / PWA and file_picker on Desktop / Mobile.
Future<AppPickedFile?> pickImageFile() => picker.pickImageFile();
