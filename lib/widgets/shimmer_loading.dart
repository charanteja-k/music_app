import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// High-performance, zero-dependency shimmer effect that sweeps smoothly across child widgets.
class ShimmerLoading extends StatefulWidget {
  final Widget child;
  final bool isLoading;

  const ShimmerLoading({super.key, required this.child, this.isLoading = true});

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    final isTesting =
        !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
    if (!isTesting) {
      _controller.repeat();
    } else {
      _controller.value = 0.5;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLoading) return widget.child;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final double value = _controller.value;

            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const [
                Color(0xFF181818),
                Color(0xFF2E2E3E),
                Color(0xFF38384E),
                Color(0xFF2E2E3E),
                Color(0xFF181818),
              ],
              stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
              transform: _SlidingGradientTransform(slidePercent: value),
            ).createShader(bounds);
          },
          child: widget.child,
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;

  const _SlidingGradientTransform({required this.slidePercent});

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(
      bounds.width * (slidePercent * 2 - 1),
      0.0,
      0.0,
    );
  }
}

/// A dark container placeholder for shimmer placeholders
class ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry? margin;

  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 12,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Skeleton for the Featured Spotlight Billboard
class ShimmerBillboard extends StatelessWidget {
  const ShimmerBillboard({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        height: 200,
        decoration: BoxDecoration(
          color: const Color(0xFF181818),
          borderRadius: BorderRadius.circular(24),
        ),
      ),
    );
  }
}

/// Skeleton for horizontal scroll rows (e.g. Top Charts, Trending)
class ShimmerCardRow extends StatelessWidget {
  const ShimmerCardRow({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: SizedBox(
        height: 210,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: 4,
          itemBuilder: (context, index) {
            return Container(
              width: 150,
              margin: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ShimmerBox(width: 150, height: 150, borderRadius: 16),
                  const SizedBox(height: 8),
                  const ShimmerBox(width: 110, height: 14, borderRadius: 6),
                  const SizedBox(height: 4),
                  const ShimmerBox(width: 70, height: 10, borderRadius: 4),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Skeleton for vertical song list rows (e.g. Made For You)
class ShimmerSongRow extends StatelessWidget {
  const ShimmerSongRow({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Column(
        children: List.generate(4, (index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const ShimmerBox(width: 54, height: 54, borderRadius: 12),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      ShimmerBox(
                        width: double.infinity,
                        height: 14,
                        borderRadius: 6,
                      ),
                      SizedBox(height: 6),
                      ShimmerBox(width: 140, height: 10, borderRadius: 4),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const ShimmerBox(width: 28, height: 28, borderRadius: 14),
              ],
            ),
          );
        }),
      ),
    );
  }
}

/// Skeleton for Left Sidebar Library Items (compact or expanded mode)
class ShimmerSidebarRow extends StatelessWidget {
  final bool isCompact;

  const ShimmerSidebarRow({super.key, this.isCompact = false});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: isCompact
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 4.0),
              child: ShimmerBox(width: 44, height: 44, borderRadius: 8),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 6.0,
              ),
              child: Row(
                children: [
                  const ShimmerBox(width: 48, height: 48, borderRadius: 8),
                  const SizedBox(width: 12.0),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        ShimmerBox(width: 120, height: 13, borderRadius: 4),
                        SizedBox(height: 6.0),
                        ShimmerBox(width: 75, height: 10, borderRadius: 4),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
