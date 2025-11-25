import 'package:wisdom/data/models/seminar.dart';

class SeminarPreJoinArgs {
  const SeminarPreJoinArgs({
    required this.seminarId,
    required this.session,
    required this.wsUrl,
    required this.token,
  });

  final String seminarId;
  final SeminarSession session;
  final String wsUrl;
  final String token;
}

class SeminarBroadcastArgs {
  const SeminarBroadcastArgs({
    required this.seminarId,
    required this.session,
    required this.wsUrl,
    required this.token,
    this.autoConnect = true,
    this.initialMicEnabled = true,
    this.initialCameraEnabled = true,
  });

  final String seminarId;
  final SeminarSession session;
  final String wsUrl;
  final String token;
  final bool autoConnect;
  final bool initialMicEnabled;
  final bool initialCameraEnabled;
}
