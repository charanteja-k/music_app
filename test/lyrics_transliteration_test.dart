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

    test('Detects Romanized Telugu lyrics accurately and rejects English', () {
      expect(
        LyricsTransliterationService.isRomanizedTelugu(
          'Rajamandri raagamajari\\nMayamma peru\\nTalavanollu leru mestiri',
        ),
        isTrue,
      );
      expect(
        LyricsTransliterationService.isRomanizedTelugu(
          'Inthakanna manchi polikedi naaku thattaledu gaani ammu',
        ),
        isTrue,
      );
      expect(
        LyricsTransliterationService.isRomanizedTelugu(
          'Samajavaragamana choosi choodangane\\nNee kallani pattuku vadalanannavi',
        ),
        isTrue,
      );
      expect(
        LyricsTransliterationService.isRomanizedTelugu(
          'Shape of you, I am in love with the shape of you\\nWe push and pull like a magnet do',
        ),
        isFalse,
      );
      expect(
        LyricsTransliterationService.isRomanizedTelugu(
          'Never gonna give you up, never gonna let you down',
        ),
        isFalse,
      );
    });

    test('Converts Romanized Telugu to Telugu native script', () {
      final input = 'Rajamandri raagamajari';
      final telugu = LyricsTransliterationService.toTeluguScript(input);
      expect(LyricsTransliterationService.hasIndicScript(telugu), isTrue);
      // Contains Telugu characters for ra, ja, ma, etc.
      expect(telugu.codeUnits.any((c) => c >= 0x0C00 && c <= 0x0C7F), isTrue);
    });

    test('Preserves timestamps during reverse transliteration of LRC lyrics', () {
      const lrc = '''[00:17.33] Rajamandri raagamajari
[00:19.44] Mayamma peru
[00:20.27] Talavanollu leru mestiri''';

      final teluguLrc = LyricsTransliterationService.toTeluguScriptLrc(lrc);
      final lines = teluguLrc.split('\n');

      expect(lines.length, equals(3));
      expect(lines[0].startsWith('[00:17.33]'), isTrue);
      expect(lines[1].startsWith('[00:19.44]'), isTrue);
      expect(lines[2].startsWith('[00:20.27]'), isTrue);
      expect(LyricsTransliterationService.hasIndicScript(lines[0]), isTrue);
      expect(LyricsTransliterationService.hasIndicScript(lines[1]), isTrue);
      expect(LyricsTransliterationService.hasIndicScript(lines[2]), isTrue);
    });
  });
}
