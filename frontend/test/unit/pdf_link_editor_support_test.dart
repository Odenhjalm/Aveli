import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/shared/utils/pdf_link_editor_support.dart';

void main() {
  test('finds PDF line when cursor is inside the link row', () {
    const plainText = 'Intro\n📄 guide.pdf\nLjud\n';
    final range = findPdfLinkDeletionRange(
      plainText: plainText,
      cursorOffset: plainText.indexOf('guide'),
      forward: false,
    );

    expect(range, isNotNull);
    expect(plainText.substring(range!.start, range.end), '📄 guide.pdf\n');
  });

  test('backspace at the next line start removes preceding PDF row', () {
    const plainText = 'Intro\n📄 guide.pdf\nLjud\n';
    final range = findPdfLinkDeletionRange(
      plainText: plainText,
      cursorOffset: plainText.indexOf('Ljud'),
      forward: false,
    );

    expect(range, isNotNull);
    expect(plainText.substring(range!.start, range.end), '📄 guide.pdf\n');
  });

  test('delete at the previous line end removes following PDF row', () {
    const plainText = 'Intro\n📄 guide.pdf\nLjud\n';
    final range = findPdfLinkDeletionRange(
      plainText: plainText,
      cursorOffset: plainText.indexOf('📄') - 1,
      forward: true,
    );

    expect(range, isNotNull);
    expect(plainText.substring(range!.start, range.end), '📄 guide.pdf\n');
  });

  test('ignores ordinary linked text that is not a PDF row', () {
    const plainText = 'Intro\nBoka nu\nLjud\n';
    final range = findPdfLinkDeletionRange(
      plainText: plainText,
      cursorOffset: plainText.indexOf('Boka'),
      forward: false,
    );

    expect(range, isNull);
    expect(isPdfLinkEditorLine('Boka nu'), isFalse);
    expect(isPdfLinkEditorLine('📄 guide.pdf'), isTrue);
  });
}
