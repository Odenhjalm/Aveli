import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/bootstrap/safe_media.dart';
import 'package:aveli/shared/widgets/background_layer.dart';
import 'package:aveli/shared/widgets/brand_header.dart';
import 'package:aveli/widgets/base_page.dart';

import 'go_router_back_button.dart';

/// CONTRACT:
/// All pages MUST render via AppScaffold.
/// BrandHeader is mandatory.
/// Headings/names must use semantic wrappers (no raw `Text()` for headings).
class AppScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool extendBody;
  final bool useBasePage;

  /// Sätt true där du *inte* vill visa back (t.ex. på Home).
  final bool disableBack;

  /// Maxbredd för centralt innehåll. Justera per sida vid behov.
  final double maxContentWidth;

  /// Standardpadding runt innehållet.
  final EdgeInsetsGeometry contentPadding;

  /// Neutral bakgrund: ingen gradient, ljus/ren yta för t.ex. login.
  final bool neutralBackground;

  /// Valfri full-bleed bakgrund (t.ex. bild) som fyller hela skärmen.
  final Widget? background;

  /// Låt innehållet/bakgrunden gå bakom appbaren (för herosidor).
  final bool extendBodyBehindAppBar;

  /// Gör appbaren helt transparent (använd tillsammans med `extendBodyBehindAppBar`).
  final bool transparentAppBar;

  /// Valfri färg för appbarens ikon/text (annars beräknas från temat).
  final Color? appBarForegroundColor;

  /// Justerbar storlek på loggan i [BasePage].
  final double logoSize;
  final bool showHomeAction;

  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.extendBody = false,
    this.useBasePage = true,
    this.disableBack = false,
    this.maxContentWidth = 860,
    this.contentPadding = const EdgeInsets.fromLTRB(16, 12, 16, 16),
    this.neutralBackground = false,
    this.background,
    this.extendBodyBehindAppBar = false,
    this.transparentAppBar = true,
    this.appBarForegroundColor,
    this.logoSize = 150,
    this.showHomeAction = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showBack = !disableBack;
    final fg = appBarForegroundColor ?? theme.colorScheme.onSurface;
    final computedActions = <Widget>[
      if (actions != null) ...actions!,
      if (showHomeAction) _HomeActionButton(color: fg),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      extendBody: extendBody,
      body: Stack(
        children: [
          if (neutralBackground)
            const Positioned.fill(child: ColoredBox(color: Color(0xFFFFFFFF)))
          else if (background != null)
            Positioned.fill(child: background!),
          if (!neutralBackground && background == null)
            const Positioned.fill(child: BackgroundLayer()),
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth),
              child: Column(
                children: [
                  BrandHeader(
                    title: title,
                    leading: showBack ? const GoRouterBackButton() : null,
                    actions: computedActions,
                    onBrandTap: () => context.goNamed(AppRoute.landing),
                  ),
                  Expanded(
                    child: Padding(
                      padding: contentPadding,
                      child: useBasePage
                          ? BasePage(logoSize: logoSize, child: body)
                          : body,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-bleed bakgrund i cover-läge med mjuk toppscrim (och valfri varm overlay).
class FullBleedBackground extends StatefulWidget {
  const FullBleedBackground({
    super.key,
    required this.image,
    this.alignment = Alignment.center,
    this.yOffset = 0,
    this.scale = 1.0,
    this.topOpacity = 0.0,
    this.sideVignette = 0.0,
    this.overlayColor,
    this.child,
    this.focalX,
    this.pixelNudgeX = 0.0,
  });

  final ImageProvider<Object> image;
  final Alignment alignment;
  final double yOffset;
  final double scale;
  final double topOpacity;
  final double sideVignette;
  final Color? overlayColor;
  final Widget? child;
  final double? focalX;

  /// Negativt värde flyttar motivet lite åt höger (positivt åt vänster).
  final double pixelNudgeX;

  @override
  State<FullBleedBackground> createState() => _FullBleedBackgroundState();
}

class _FullBleedBackgroundState extends State<FullBleedBackground> {
  Size? _imageSize;
  ImageStream? _imageStream;
  ImageStreamListener? _listener;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant FullBleedBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.image, widget.image)) {
      _resolveImage(force: true);
    }
  }

  @override
  void dispose() {
    _detachImageStream();
    super.dispose();
  }

  void _resolveImage({bool force = false}) {
    final config = createLocalImageConfiguration(context);
    final stream = widget.image.resolve(config);

    if (!force && identical(stream.key, _imageStream?.key)) {
      return;
    }

    _detachImageStream();
    _imageStream = stream;
    _listener = ImageStreamListener((info, _) {
      final size = Size(
        info.image.width.toDouble(),
        info.image.height.toDouble(),
      );
      if (_imageSize != size && mounted) {
        setState(() => _imageSize = size);
      }
    });
    _imageStream?.addListener(_listener!);
  }

  void _detachImageStream() {
    if (_imageStream != null && _listener != null) {
      _imageStream!.removeListener(_listener!);
    }
    _imageStream = null;
    _listener = null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (SafeMedia.enabled) {
          SafeMedia.markBackground();
        }
        final backgroundLayer = _buildBackgroundLayer(constraints);

        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            backgroundLayer,
            if (widget.sideVignette > 0) const _SideVignette(),
            if (widget.topOpacity > 0)
              IgnorePointer(
                child: Opacity(
                  opacity: widget.topOpacity.clamp(0.0, 1.0),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black54, Colors.transparent],
                      ),
                    ),
                  ),
                ),
              ),
            if (widget.overlayColor != null)
              Container(color: widget.overlayColor),
            if (widget.child != null) widget.child!,
          ],
        );
      },
    );
  }

  Widget _buildBackgroundLayer(BoxConstraints constraints) {
    final maxWidth = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : MediaQuery.of(context).size.width;
    final maxHeight = constraints.maxHeight.isFinite
        ? constraints.maxHeight
        : MediaQuery.of(context).size.height;
    final cacheWidth = SafeMedia.cacheDimension(context, maxWidth, max: 640);

    if (_imageSize == null || widget.focalX == null) {
      if (SafeMedia.enabled) {
        return Transform.translate(
          offset: Offset(0, widget.yOffset),
          child: Transform.scale(
            scale: widget.scale,
            child: Image(
              image: SafeMedia.resizedProvider(
                widget.image,
                cacheWidth: cacheWidth,
                cacheHeight: null,
              ),
              fit: BoxFit.cover,
              alignment: widget.alignment,
              filterQuality: SafeMedia.filterQuality(full: FilterQuality.high),
              gaplessPlayback: true,
            ),
          ),
        );
      }
      return Transform.translate(
        offset: Offset(0, widget.yOffset),
        child: Transform.scale(
          scale: widget.scale,
          child: DecoratedBox(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: widget.image,
                fit: BoxFit.cover,
                alignment: widget.alignment,
                filterQuality: SafeMedia.filterQuality(
                  full: FilterQuality.high,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final imgWidth = _imageSize!.width;
    final imgHeight = _imageSize!.height;
    final coverScale = math.max(maxWidth / imgWidth, maxHeight / imgHeight);
    final scaled = coverScale * widget.scale;
    final displayedWidth = imgWidth * scaled;
    final displayedHeight = imgHeight * scaled;

    final focal = widget.focalX!.clamp(0.0, 1.0);
    final dx = (maxWidth / 2) - (focal * displayedWidth) + widget.pixelNudgeX;

    return OverflowBox(
      minWidth: displayedWidth,
      maxWidth: displayedWidth,
      minHeight: displayedHeight,
      maxHeight: displayedHeight,
      alignment: Alignment.topLeft,
      child: Transform.translate(
        offset: Offset(dx, widget.yOffset),
        child: Image(
          image: SafeMedia.resizedProvider(
            widget.image,
            cacheWidth: cacheWidth,
            cacheHeight: null,
          ),
          width: displayedWidth,
          height: displayedHeight,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          filterQuality: SafeMedia.filterQuality(full: FilterQuality.high),
          gaplessPlayback: true,
        ),
      ),
    );
  }
}

class _SideVignette extends StatelessWidget {
  const _SideVignette();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.black.withValues(alpha: .10),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withValues(alpha: .10),
            ],
            stops: const [0.0, .18, .82, 1.0],
          ),
        ),
      ),
    );
  }
}

class _HomeActionButton extends StatelessWidget {
  const _HomeActionButton({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Hem',
      icon: Icon(Icons.home_outlined, color: color),
      onPressed: () => context.goNamed(AppRoute.home),
    );
  }
}
