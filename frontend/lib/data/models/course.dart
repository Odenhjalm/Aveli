import 'package:json_annotation/json_annotation.dart';

import 'package:aveli/shared/utils/course_cover_contract.dart';

part 'course.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake, explicitToJson: true)
class Course {
  const Course({
    required this.id,
    this.slug,
    required this.title,
    this.description,
    this.coverMediaId,
    this.cover,
    this.videoUrl,
    this.isPublished = false,
  });

  factory Course.fromJson(Map<String, dynamic> json) => _$CourseFromJson(json);

  Map<String, dynamic> toJson() => _$CourseToJson(this);

  final String id;
  final String? slug;
  final String title;
  final String? description;
  final String? coverMediaId;
  final CourseCoverData? cover;
  final String? videoUrl;

  @JsonKey(defaultValue: false)
  final bool isPublished;
}
