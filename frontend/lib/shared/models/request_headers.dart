import 'package:flutter/foundation.dart';

@immutable
class RequestHeader {
  const RequestHeader({required this.name, required this.value});

  final String name;
  final String value;
}

@immutable
class RequestHeaders {
  RequestHeaders({required List<RequestHeader> entries})
    : entries = List<RequestHeader>.unmodifiable(entries);

  final List<RequestHeader> entries;

  static final RequestHeaders empty = RequestHeaders(entries: const []);

  factory RequestHeaders.fromResponseObject(
    Object? payload, {
    required String label,
  }) {
    if (payload is! Map) {
      throw StateError('$label must be an object');
    }

    final entries = <RequestHeader>[];
    for (final entry in payload.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw StateError('$label must contain string header entries');
      }
      entries.add(
        RequestHeader(name: entry.key as String, value: entry.value as String),
      );
    }
    return RequestHeaders(entries: entries);
  }

  bool get isEmpty => entries.isEmpty;

  void forEach(void Function(String name, String value) visitor) {
    for (final entry in entries) {
      visitor(entry.name, entry.value);
    }
  }

  String? valueFor(String name) {
    for (final entry in entries) {
      if (entry.name == name) {
        return entry.value;
      }
    }
    return null;
  }

  Map<String, String> toMap() {
    final headers = <String, String>{};
    forEach((name, value) {
      headers[name] = value;
    });
    return headers;
  }
}
