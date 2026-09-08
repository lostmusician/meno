import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meno/services/smart_bullet_formatter.dart';

void main() {
  const formatter = SmartBulletTextInputFormatter();

  TextEditingValue edit(
    String oldText,
    String newText, {
    int? oldCaret,
    int? newCaret,
    TextSelection? oldSelection,
    TextSelection? newSelection,
    TextRange composing = TextRange.empty,
  }) => formatter.formatEditUpdate(
    TextEditingValue(
      text: oldText,
      selection:
          oldSelection ??
          TextSelection.collapsed(offset: oldCaret ?? oldText.length),
      composing: composing,
    ),
    TextEditingValue(
      text: newText,
      selection:
          newSelection ??
          TextSelection.collapsed(offset: newCaret ?? newText.length),
      composing: composing,
    ),
  );

  test('continues a populated Markdown bullet and places the caret', () {
    final value = edit('- one', '- one\n');

    expect(value.text, '- one\n- ');
    expect(value.selection, const TextSelection.collapsed(offset: 8));
  });

  test('preserves indentation when continuing a bullet', () {
    final value = edit('  - nested', '  - nested\n');

    expect(value.text, '  - nested\n  - ');
  });

  test('empty bullet exits the list and removes its marker', () {
    final value = edit('- one\n- ', '- one\n- \n');

    expect(value.text, '- one\n\n');
    expect(value.selection, const TextSelection.collapsed(offset: 7));
  });

  test('ignores inline hyphens and non-bullet lines', () {
    expect(edit('well-being', 'well-being\n').text, 'well-being\n');
    expect(edit('plain line', 'plain line\n').text, 'plain line\n');
  });

  test('ignores pastes and replacement selections', () {
    expect(edit('- one', '- one\npasted').text, '- one\npasted');

    final value = edit(
      '- one',
      '- \n',
      oldSelection: const TextSelection(baseOffset: 2, extentOffset: 5),
      newSelection: const TextSelection.collapsed(offset: 3),
    );
    expect(value.text, '- \n');
  });

  test('ignores edits while an IME composing region is active', () {
    final value = edit(
      '- one',
      '- one\n',
      composing: const TextRange(start: 0, end: 5),
    );

    expect(value.text, '- one\n');
  });
}
