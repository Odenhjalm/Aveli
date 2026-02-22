bool isValidSlug(String slug) {
  final uuidRegex = RegExp(r'^[0-9a-fA-F-]{36}$');
  if (uuidRegex.hasMatch(slug)) return false;
  return slug.trim().isNotEmpty;
}
