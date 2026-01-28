import 'package:flutter/material.dart';
import 'package:aveli/shared/widgets/app_avatar.dart';
import 'package:aveli/shared/widgets/card_text.dart';

class TeacherCard extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final String? subjects;
  final VoidCallback? onTap;
  const TeacherCard({
    super.key,
    required this.name,
    this.avatarUrl,
    this.subjects,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 2),
              AppAvatar(url: avatarUrl, size: 52),
              const SizedBox(width: 10),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TeacherNameText(
                    name,
                    baseStyle: Theme.of(context).textTheme.titleMedium,
                    fontWeight: FontWeight.w700,
                  ),
                  if ((subjects ?? '').isNotEmpty)
                    Text(
                      subjects!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
