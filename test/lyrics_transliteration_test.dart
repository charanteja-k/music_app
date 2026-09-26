import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/services/lyrics_transliteration_service.dart';

void main() {
  group('LyricsTransliterationService Tests', () {
    test('Detects Indic scripts accurately', () {
      expect(LyricsTransliterationService.hasIndicScript('Hello World'), isFalse);
      expect(LyricsTransliterationService.hasIndicScript('సమాజవరగమనా'), isTrue); // Telugu
      expect(LyricsTransliterationService.hasIndicScript('केसरिया तेरा इश्क़'), isTrue); // Hindi
      expect(LyricsTransliterationService.hasIndicScript('அரபிக் குத்து'), isTrue); // Tamil
    });

    test('Transliterates Telugu lyrics to English pronunciation', () {
      final input = 'సమాజవరగమనా చూసి';
      final output = LyricsTransliterationService.transliterateText(input);
      expect(output.toLowerCase(), contains('sama'));
      expect(output.toLowerCase(), contains('choosi'));
    });

    test('Transliterates Hindi lyrics to English pronunciation', () {
      final input = 'केसरिया तेरा इश्क़';
      final output = LyricsTransliterationService.transliterateText(input);
      expect(output.toLowerCase(), contains('kesari'));
      expect(output.toLowerCase(), contains('tera'));
    });

    test('Preserves timestamps in synchronized LRC lyrics', () {
      const lrc = '''[00:12.30]సమాజవరగమనా
[00:15.50]చూసి చూడంగానే
[00:18.20]English line mixed''';

      final romanizedLrc = LyricsTransliterationService.transliterateLrc(lrc);
      final lines = romanizedLrc.split('\n');

      expect(lines.length, equals(3));
      expect(lines[0].startsWith('[00:12.30]'), isTrue);
      expect(lines[1].startsWith('[00:15.50]'), isTrue);
      expect(lines[2].startsWith('[00:18.20]'), isTrue);
      expect(lines[0].toLowerCase(), contains('sama'));
      expect(lines[2].toLowerCase(), contains('english line mixed'));
    });
  });
}
