import 'package:file_picker/file_picker.dart';
import 'app_file_picker.dart';

Future<AppPickedFile?> pickMusicArchiveOrCsv() async {
  try {
    final pickedFiles = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'zip'],
    );

    if (pickedFiles.isNotEmpty) {
      final file = pickedFiles.first;
      final bytes = await file.xFile.readAsBytes();
      if (bytes.isNotEmpty) {
        return AppPickedFile(name: file.name, bytes: bytes);
      }
    }
  } catch (_) {}
  return null;
}

Future<AppPickedFile?> pickImageFile() async {
  try {
    final pickedFiles = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    );

    if (pickedFiles.isNotEmpty) {
      final file = pickedFiles.first;
      final bytes = await file.xFile.readAsBytes();
      if (bytes.isNotEmpty) {
        return AppPickedFile(name: file.name, bytes: bytes);
      }
    }
  } catch (_) {}
  return null;
}
