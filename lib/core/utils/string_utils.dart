// Utilities shared across the app.

/// Converts all localized Unicode numerals (Arabic, Persian, Devanagari, Thai, etc.)
/// to standard English/ASCII digits (0-9).
///
/// Example: '١٠.٠.٠.١١' → '10.0.0.11'
String normalizeDigits(String input) {
  // Unicode code points for '0' in major localized numeral systems
  const zeroDigits = [
    0x0660,
    0x06F0,
    0x0966,
    0x09E6,
    0x0A66,
    0x0AE6,
    0x0B66,
    0x0BE6,
    0x0C66,
    0x0CE6,
    0x0D66,
    0x0E50,
    0x0ED0,
    0x0F20,
    0x1040,
    0x17E0,
    0x1810,
    0x1946,
    0x19D0,
    0x1A80,
    0x1A90,
    0x1B50,
    0x1BB0,
    0x1C40,
    0x1C50,
    0xA620,
    0xA8D0,
    0xA900,
    0xA9D0,
    0xAA50,
    0xABF0,
    0xFF10,
  ];

  final buffer = StringBuffer();
  for (int i = 0; i < input.length; i++) {
    final int code = input.codeUnitAt(i);
    bool replaced = false;

    for (final zero in zeroDigits) {
      if (code >= zero && code <= zero + 9) {
        buffer.write(String.fromCharCode(0x0030 + (code - zero)));
        replaced = true;
        break;
      }
    }

    if (!replaced) {
      buffer.write(String.fromCharCode(code));
    }
  }

  return buffer.toString();
}
