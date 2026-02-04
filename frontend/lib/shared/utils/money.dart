// Money helpers.
//
// Source of truth:
// - Course prices are stored and transported as **öre** (integer cents) via
//   `price_amount_cents` (backend + API + Stripe `unit_amount`).
// - UI/Editor represent prices in **SEK (kr)** and convert explicitly.

/// Formats an amount in öre (cents) to a SEK string with exactly two decimals.
///
/// Example: `49000` -> `490.00 kr`
String formatSekFromOre(int amountOre) {
  final abs = amountOre.abs();
  final kronor = abs ~/ 100;
  final ore = abs % 100;
  final sign = amountOre < 0 ? '-' : '';
  return '$sign$kronor.${ore.toString().padLeft(2, '0')} kr';
}

/// Formats an amount in öre (cents) to a SEK input string (no currency suffix).
///
/// - If divisible by 100: `49000` -> `490`
/// - Otherwise: `49050` -> `490.50`
String formatSekInputFromOre(int amountOre) {
  if (amountOre % 100 == 0) {
    return (amountOre ~/ 100).toString();
  }
  final abs = amountOre.abs();
  final kronor = abs ~/ 100;
  final ore = abs % 100;
  final sign = amountOre < 0 ? '-' : '';
  return '$sign$kronor.${ore.toString().padLeft(2, '0')}';
}

/// Parses a SEK input string to öre (cents).
///
/// Accepts `,` or `.` as decimal separator and up to 2 decimals.
/// Returns `null` when the input is invalid.
///
/// Examples:
/// - `490` -> `49000`
/// - `490.00` -> `49000`
/// - `490,5` -> `49050`
int? parseSekInputToOre(String raw) {
  final normalized = raw.trim().replaceAll(' ', '').replaceAll(',', '.');
  if (normalized.isEmpty) return null;

  final match = RegExp(
    r'^([0-9]+)(?:[.]([0-9]{0,2}))?$',
  ).firstMatch(normalized);
  if (match == null) return null;

  final kronor = int.tryParse(match.group(1) ?? '');
  if (kronor == null) return null;

  final decimals = match.group(2) ?? '';
  final ore = decimals.isEmpty ? 0 : int.parse(decimals.padRight(2, '0'));
  return kronor * 100 + ore;
}
