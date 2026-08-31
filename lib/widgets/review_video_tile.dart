import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../utils/ui_helpers.dart';

class ReviewVideoTile extends StatelessWidget {
  final String url;
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const ReviewVideoTile({
    super.key,
    required this.url,
    this.width = 56,
    this.height = 56,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
  });

  @override
  Widget build(BuildContext context) {
    final trustedUrl = UiHelpers.sanitizeTrustedRemoteUrl(url);

    return Material(
      color: const Color(0xFF172B4D),
      borderRadius: borderRadius,
      child: InkWell(
        onTap: trustedUrl == null
            ? null
            : () {
                showDialog<void>(
                  context: context,
                  barrierColor: Colors.black87,
                  builder: (_) => _ReviewVideoDialog(url: trustedUrl),
                );
              },
        borderRadius: borderRadius,
        child: SizedBox(
          width: width,
          height: height,
          child: const Center(
            child: Icon(
              Icons.play_circle_outline_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewVideoDialog extends StatefulWidget {
  final String url;

  const _ReviewVideoDialog({required this.url});

  @override
  State<_ReviewVideoDialog> createState() => _ReviewVideoDialogState();
}

class _ReviewVideoDialogState extends State<_ReviewVideoDialog> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      await _controller.play();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    if (!_ready) return;
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
      } else {
        _controller.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_failed)
            const Padding(
              padding: EdgeInsets.all(36),
              child: Text(
                'No se pudo reproducir el video.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
            )
          else if (!_ready)
            const SizedBox(
              height: 240,
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF024C8B)),
              ),
            )
          else
            GestureDetector(
              onTap: _togglePlayback,
              child: AspectRatio(
                aspectRatio: _controller.value.aspectRatio == 0
                    ? 16 / 9
                    : _controller.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(_controller),
                    if (!_controller.value.isPlaying)
                      const Icon(
                        Icons.play_circle_fill_rounded,
                        color: Colors.white,
                        size: 64,
                      ),
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: VideoProgressIndicator(
                        _controller,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(
                          playedColor: Color(0xFF21AF97),
                          bufferedColor: Colors.white38,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            top: 6,
            right: 6,
            child: IconButton.filled(
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Cerrar video',
              icon: const Icon(Icons.close_rounded),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
