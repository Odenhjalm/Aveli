import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class RecordedSessionPlayer extends StatefulWidget {
  const RecordedSessionPlayer({super.key, required this.videoUrl});

  final String videoUrl;

  @override
  State<RecordedSessionPlayer> createState() => _RecordedSessionPlayerState();
}

class _RecordedSessionPlayerState extends State<RecordedSessionPlayer> {
  late final Player _player;
  late final VideoController _controller;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _player.open(Media(widget.videoUrl));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Video(controller: _controller),
      ),
    );
  }
}
