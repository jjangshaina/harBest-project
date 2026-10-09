import 'package:flutter/material.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';

class PlantImage extends StatelessWidget {
  final String? imageUrl;

  /// Fixed square size. If null, the image fills the available width
  /// and uses [aspectRatio] to decide its height.
  final double? size;
  final double aspectRatio;
  final double borderRadius;

  /// When true, tapping the image opens a full-screen, zoomable viewer.
  final bool enableZoom;

  const PlantImage({
    super.key,
    required this.imageUrl,
    this.size,
    this.aspectRatio = 1.6,
    this.borderRadius = 16,
    this.enableZoom = false,
  }); 

  static const String fallbackUrl =
      'https://urbangardeningmanila.wordpress.com/wp-content/uploads/2021/11/71bms5snrxl.jpg';

      String get _urlToShow =>
      (imageUrl != null && imageUrl!.isNotEmpty) ? imageUrl! : fallbackUrl;

  void _openViewer(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) => _PlantImageViewer(url: _urlToShow),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }


   @override
  Widget build(BuildContext context) {
    final image = Image.network(
      _urlToShow,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const Center(child: CircularProgressIndicator());
      },
      errorBuilder: (context, error, stackTrace) => Container(
        color: AppColors.track,
        child: const Center(
          child: Icon(AppIcons.photo, size: 40, color: AppColors.textTertiary),
        ),
      ),
    );

    final sized = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: size != null
          ? SizedBox(width: size, height: size, child: image)
          : AspectRatio(aspectRatio: aspectRatio, child: image),
    );

    if (!enableZoom) return sized;

    return GestureDetector(
      onTap: () => _openViewer(context),
      child: sized,
    );
  }
}

/// Full-screen close-up view: pinch to zoom, drag to pan, double-tap
/// to toggle zoom, tap the X (or swipe back) to close.
class _PlantImageViewer extends StatefulWidget {
  final String url;
  const _PlantImageViewer({required this.url});

  @override
  State<_PlantImageViewer> createState() => _PlantImageViewerState();
}

class _PlantImageViewerState extends State<_PlantImageViewer> {
  final _controller = TransformationController();
  TapDownDetails? _doubleTapDetails;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    if (_controller.value != Matrix4.identity()) {
      _controller.value = Matrix4.identity();
    } else if (_doubleTapDetails != null) {
      final pos = _doubleTapDetails!.localPosition;
      _controller.value = Matrix4.identity()
        ..translate(-pos.dx * 1.5, -pos.dy * 1.5)
        ..scale(2.5);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onDoubleTapDown: (d) => _doubleTapDetails = d,
              onDoubleTap: _handleDoubleTap,
              child: InteractiveViewer(
                transformationController: _controller,
                minScale: 1.0,
                maxScale: 5.0,
                child: Center(
                  child: Image.network(
                    widget.url,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      AppIcons.photo,
                      size: 60,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(AppIcons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}