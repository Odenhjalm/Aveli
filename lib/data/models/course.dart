import 'package:json_annotation/json_annotation.dart';

part 'course.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake, explicitToJson: true)
class Course {
  const Course({
    required this.id,
    this.slug,
    required this.title,
    this.description,
    this.coverUrl,
    this.signedCoverUrl,
    this.videoUrl,
    this.isFreeIntro = false,
    this.isPublished = false,
  });

  factory Course.fromJson(Map<String, dynamic> json) => _$CourseFromJson(json);

  Map<String, dynamic> toJson() => _$CourseToJson(this);

  final String id;
  final String? slug;
  final String title;
  final String? description;
  final String? coverUrl;
  final String? signedCoverUrl;
  final String? videoUrl;

  @JsonKey(defaultValue: false)
  final bool isFreeIntro;

  @JsonKey(defaultValue: false)
  final bool isPublished;

  String? get resolvedCoverUrl => signedCoverUrl ?? coverUrl;
}
