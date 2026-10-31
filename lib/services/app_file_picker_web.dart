import 'dart:async';
import 'dart:js_interop';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import 'app_file_picker.dart';

Future<AppPickedFile?> pickMusicArchiveOrCsv() async {
  // Strategy 1: Native HTML5 File Input attached to DOM (essential for PWA)
  try {
    final completer = Completer<AppPickedFile?>();
    final uploadInput = web.HTMLInputElement()
      ..type = 'file'
      ..accept =
          '.csv,.zip,text/csv,text/plain,application/zip,application/x-zip-compressed,application/octet-stream';

    uploadInput.style
      ..position = 'fixed'
      ..top = '-10000px'
      ..left = '-10000px'
      ..opacity = '0';

    web.document.body?.append(uploadInput);

    void cleanup() {
      try {
        uploadInput.remove();
      } catch (_) {}
    }

    uploadInput.addEventListener(
      'cancel',
      ((web.Event e) {
        cleanup();
        if (!completer.isCompleted) completer.complete(null);
      }).toJS,
    );

    uploadInput.addEventListener(
      'change',
      ((web.Event event) {
        final files = uploadInput.files;
        if (files != null && files.length > 0) {
          final file = files.item(0)!;
          final reader = web.FileReader();

          reader.addEventListener(
            'loadend',
            ((web.Event e) {
              cleanup();
              final result = reader.result;
              if (result != null) {
                try {
                  final bytes = (result as JSArrayBuffer).toDart.asUint8List();
                  if (!completer.isCompleted) {
                    completer.complete(
                      AppPickedFile(name: file.name, bytes: bytes),
                    );
                  }
                } catch (_) {
                  if (!completer.isCompleted) completer.complete(null);
                }
              } else {
                if (!completer.isCompleted) completer.complete(null);
              }
            }).toJS,
          );

          reader.addEventListener(
            'error',
            ((web.Event e) {
              cleanup();
              if (!completer.isCompleted) completer.complete(null);
            }).toJS,
          );

          reader.readAsArrayBuffer(file);
        } else {
          cleanup();
          if (!completer.isCompleted) completer.complete(null);
        }
      }).toJS,
    );

    uploadInput.click();
    final picked = await completer.future;
    if (picked != null) return picked;
  } catch (e) {
    debugPrint('[FilePicker Web DOM] Error: $e');
  }

  // Strategy 2: FilePicker plugin fallback
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
  } catch (e) {
    debugPrint('[FilePicker Web Plugin] Error: $e');
  }

  return null;
}

Future<AppPickedFile?> pickImageFile() async {
  // Strategy 1: Native HTML5 File Input attached to DOM (essential for PWA)
  try {
    final completer = Completer<AppPickedFile?>();
    final uploadInput = web.HTMLInputElement()
      ..type = 'file'
      ..accept = 'image/jpeg,image/png,image/webp,image/*';

    uploadInput.style
      ..position = 'fixed'
      ..top = '-10000px'
      ..left = '-10000px'
      ..opacity = '0';

    web.document.body?.append(uploadInput);

    void cleanup() {
      try {
        uploadInput.remove();
      } catch (_) {}
    }

    uploadInput.addEventListener(
      'cancel',
      ((web.Event e) {
        cleanup();
        if (!completer.isCompleted) completer.complete(null);
      }).toJS,
    );

    uploadInput.addEventListener(
      'change',
      ((web.Event event) {
        final files = uploadInput.files;
        if (files != null && files.length > 0) {
          final file = files.item(0)!;
          final reader = web.FileReader();

          reader.addEventListener(
            'loadend',
            ((web.Event e) {
              cleanup();
              final result = reader.result;
              if (result != null) {
                try {
                  final bytes = (result as JSArrayBuffer).toDart.asUint8List();
                  if (!completer.isCompleted) {
                    completer.complete(
                      AppPickedFile(name: file.name, bytes: bytes),
                    );
                  }
                } catch (_) {
                  if (!completer.isCompleted) completer.complete(null);
                }
              } else {
                if (!completer.isCompleted) completer.complete(null);
              }
            }).toJS,
          );

          reader.addEventListener(
            'error',
            ((web.Event e) {
              cleanup();
              if (!completer.isCompleted) completer.complete(null);
            }).toJS,
          );

          reader.readAsArrayBuffer(file);
        } else {
          cleanup();
          if (!completer.isCompleted) completer.complete(null);
        }
      }).toJS,
    );

    uploadInput.click();
    final picked = await completer.future;
    if (picked != null) return picked;
  } catch (e) {
    debugPrint('[ImagePicker Web DOM] Error: $e');
  }

  // Strategy 2: FilePicker plugin fallback
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
  } catch (e) {
    debugPrint('[ImagePicker Web Plugin] Error: $e');
  }

  return null;
}
