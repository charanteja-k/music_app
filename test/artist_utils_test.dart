import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/utils/artist_utils.dart';

void main() {
  group('ArtistUtils', () {
    test('Capitalizes lowercase artist names correctly', () {
      expect(ArtistUtils.formatArtistName('vathshan'), equals('Vathshan'));
      expect(
        ArtistUtils.formatArtistName('sai abhyankkar'),
        equals('Sai Abhyankkar'),
      );
      expect(ArtistUtils.formatArtistName('mc sai'), equals('MC Sai'));
      expect(ArtistUtils.formatArtistName('gds'), equals('GDS'));
      expect(
        ArtistUtils.formatArtistName('hanan shaah'),
        equals('Hanan Shaah'),
      );
      expect(ArtistUtils.formatArtistName('arjn'), equals('ARJN'));
      expect(
        ArtistUtils.formatArtistName('anirudh ravichander'),
        equals('Anirudh Ravichander'),
      );
    });

    test('Strips YouTube - Topic suffix and formats properly', () {
      expect(
        ArtistUtils.formatArtistName('sai abhyankkar - Topic'),
        equals('Sai Abhyankkar'),
      );
      expect(
        ArtistUtils.formatArtistName('Vathshan - Topic'),
        equals('Vathshan'),
      );
    });

    test('Handles initials and dotted names correctly', () {
      expect(
        ArtistUtils.formatArtistName('a.r. rahman'),
        equals('A.R. Rahman'),
      );
    });

    test('Preserves already capitalized names and handles empty/blank', () {
      expect(ArtistUtils.formatArtistName('Sid Sriram'), equals('Sid Sriram'));
      expect(ArtistUtils.formatArtistName(''), equals('Unknown Artist'));
      expect(ArtistUtils.formatArtistName('   '), equals('Unknown Artist'));
    });
  });
}
