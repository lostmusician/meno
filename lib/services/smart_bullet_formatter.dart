import 'package:flutter/services.dart';

/// Continues Markdown-style unordered lists without changing stored syntax.
class SmartBulletTextInputFormatter extends TextInputFormatter {
  const SmartBulletTextInputFormatter();

  static final _bulletLine = RegExp(r'^(\s*)- (.*)$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!oldValue.composing.isCollapsed || !newValue.composing.isCollapsed) {
      return newValue;
    }
    if (!oldValue.selection.isCollapsed || !newValue.selection.isCollapsed) {
      return newValue;
    }

    final insertionStart = oldValue.selection.start;
    if (insertionStart < 0 || newValue.selection.start < 0) return newValue;
    final insertedLength = newValue.text.length - oldValue.text.length;
    if (insertedLength != 1 ||
        insertionStart >= newValue.text.length ||
        newValue.text[insertionStart] != '\n') {
      return newValue;
    }

    final lineStart = oldValue.text.lastIndexOf('\n', insertionStart - 1) + 1;
    final line = oldValue.text.substring(lineStart, insertionStart);
    final match = _bulletLine.firstMatch(line);
    if (match == null) return newValue;

    final indentation = match.group(1)!;
    final content = match.group(2)!;
    if (content.trim().isEmpty) {
      final text = newValue.text.replaceRange(
        lineStart,
        insertionStart + 1,
        '\n',
      );
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: lineStart + 1),
      );
    }

    final continuation = '$indentation- ';
    final text = newValue.text.replaceRange(
      insertionStart + 1,
      insertionStart + 1,
      continuation,
    );
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: insertionStart + 1 + continuation.length,
      ),
    );
  }
}
