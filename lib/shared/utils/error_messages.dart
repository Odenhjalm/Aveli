import 'package:dio/dio.dart';

String friendlyHttpError(Object error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    final detail = _extractDetail(error.response?.data);
    final baseMessage = status != null
        ? 'HTTP $status'
        : (error.message ?? 'Nätverksfel');
    if (detail != null && detail.isNotEmpty) {
      return '$baseMessage: $detail';
    }
    return baseMessage;
  }
  return error.toString();
}

String? _extractDetail(dynamic data) {
  if (data is Map) {
    final detail = data['detail'];
    if (detail is String) return detail;
    if (detail is List && detail.isNotEmpty && detail.first is String) {
      return detail.first as String;
    }
  }
  return null;
}
