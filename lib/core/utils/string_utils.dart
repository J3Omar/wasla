// Utilities shared across the app.

/// Converts Arabic-Indic and Extended Arabic-Indic numerals to ASCII digits.
///
/// Arabic-Indic: ٠١٢٣٤٥٦٧٨٩ (U+0660–U+0669)
/// Extended (Persian/Urdu): ۰۱۲۳۴۵۶۷۸۹ (U+06F0–U+06F9)
///
/// Example: '١٠.٠.٠.١١' → '10.0.0.11'
String normalizeDigits(String input) {
  return input.replaceAllMapped(
    RegExp(r'[\u0660-\u0669\u06F0-\u06F9]'),
    (m) {
      final cp = m.group(0)!.codeUnitAt(0);
      // Arabic-Indic block: U+0660 = '٠'
      if (cp >= 0x0660 && cp <= 0x0669) {
        return String.fromCharCode(cp - 0x0660 + 0x30);
      }
      // Extended Arabic-Indic block: U+06F0 = '۰'
      return String.fromCharCode(cp - 0x06F0 + 0x30);
    },
  );
}
