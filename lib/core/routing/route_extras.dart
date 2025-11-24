/// Shared typed payloads for router navigation extras.
class MessagesRouteArgs {
  const MessagesRouteArgs({required this.kind, required this.id});

  /// Message channel kind, e.g. `dm` or `service`.
  final String kind;

  /// Identifier associated with the channel (user id, service id, etc.).
  final String id;
}

/// Payload for the teacher course editor route.
class CourseEditorRouteArgs {
  const CourseEditorRouteArgs({this.courseId});

  final String? courseId;
}

/// Payload for course intro pages where course metadata is required.
class CourseIntroRouteArgs {
  const CourseIntroRouteArgs({this.courseId, this.title});

  final String? courseId;
  final String? title;
}

/// Payload for quiz routes that require identifiers.
class QuizRouteArgs {
  const QuizRouteArgs({required this.quizId, this.courseId});

  final String quizId;
  final String? courseId;
}

/// Optional extras for the community page (e.g. active tab).
class CommunityRouteArgs {
  const CommunityRouteArgs({this.initialTab});

  /// Supported values: `teachers` (default) or `services`.
  final String? initialTab;
}

/// Extras for the direct message chat route.
class ChatRouteArgs {
  const ChatRouteArgs({required this.peerId, this.displayName});

  final String peerId;
  final String? displayName;
}
