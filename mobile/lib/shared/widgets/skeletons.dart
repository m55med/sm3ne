import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'package:bisawtak/config/design_tokens.dart';

/// Shimmer-based loading skeletons used in place of bare
/// `CircularProgressIndicator`s on list-style screens. They convey
/// "content is on its way" rather than "the app is busy".

class _ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const _ShimmerBox({
    required this.width,
    required this.height,
    this.radius = AppRadius.sm,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _Shimmer extends StatelessWidget {
  final Widget child;
  const _Shimmer({required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Shimmer.fromColors(
      baseColor: scheme.surfaceContainerHighest,
      highlightColor: scheme.surfaceContainerHigh,
      period: const Duration(milliseconds: 1400),
      child: child,
    );
  }
}

/// Skeleton tile that mirrors a row in the transcription list.
class TranscriptionTileSkeleton extends StatelessWidget {
  const TranscriptionTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const _Shimmer(
      child: Card(
        margin: EdgeInsets.only(bottom: AppSpacing.sm),
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              _ShimmerBox(width: 40, height: 40, radius: AppRadius.pill),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ShimmerBox(width: double.infinity, height: 14),
                    SizedBox(height: AppSpacing.sm),
                    _ShimmerBox(width: 120, height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton card that mirrors a plan card on the plans screen.
class PlanCardSkeleton extends StatelessWidget {
  const PlanCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.lg),
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _ShimmerBox(width: 120, height: 22),
            SizedBox(height: AppSpacing.md),
            _ShimmerBox(width: 80, height: 32),
            SizedBox(height: AppSpacing.lg),
            _ShimmerBox(width: double.infinity, height: 14),
            SizedBox(height: AppSpacing.sm),
            _ShimmerBox(width: 200, height: 14),
            SizedBox(height: AppSpacing.lg),
            _ShimmerBox(width: double.infinity, height: 44, radius: AppRadius.md),
          ],
        ),
      ),
    );
  }
}

/// Skeleton block for a generic header (profile, settings).
class HeaderSkeleton extends StatelessWidget {
  const HeaderSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const _Shimmer(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Row(
          children: [
            _ShimmerBox(width: 64, height: 64, radius: AppRadius.pill),
            SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ShimmerBox(width: 160, height: 18),
                  SizedBox(height: AppSpacing.sm),
                  _ShimmerBox(width: 120, height: 14),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Convenience builder that renders [count] shimmer tiles inside a
/// scrollable column — drop-in replacement for a loading spinner on the
/// transcription list.
class TranscriptionListSkeleton extends StatelessWidget {
  final int count;
  const TranscriptionListSkeleton({super.key, this.count = 6});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      itemCount: count,
      itemBuilder: (_, __) => const TranscriptionTileSkeleton(),
    );
  }
}

/// Three plan cards stacked vertically. Use as the loading state for the
/// plans screen.
class PlansSkeleton extends StatelessWidget {
  const PlansSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          PlanCardSkeleton(),
          PlanCardSkeleton(),
          PlanCardSkeleton(),
        ],
      ),
    );
  }
}
