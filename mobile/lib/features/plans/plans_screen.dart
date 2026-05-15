import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bisawtak/config/design_tokens.dart';
import 'package:bisawtak/core/analytics/analytics_service.dart';
import 'package:bisawtak/core/auth/auth_provider.dart';
import 'package:bisawtak/data/repositories/plans_repository.dart';
import 'package:bisawtak/shared/utils/error_messages.dart';
import 'package:bisawtak/shared/utils/haptics.dart';
import 'package:bisawtak/shared/widgets/confirm_dialog.dart';
import 'package:bisawtak/shared/widgets/skeletons.dart';

/// Current subscription + plan + today's usage. The screen is built entirely
/// around this — there are no purchase flows in the app: paid plans are
/// unlocked ONLY by redeeming a coupon (the app itself is 100% free).
final currentSubscriptionProvider =
    FutureProvider.autoDispose<CurrentSubscription?>((ref) async {
  return ref.read(plansRepositoryProvider).currentSubscription();
});

String planLabel(String name) {
  switch (name) {
    case 'free':
      return 'المجانية';
    case 'monthly':
      return 'الشهرية';
    case 'annual':
      return 'السنوية';
    default:
      return name;
  }
}

class PlansScreen extends ConsumerStatefulWidget {
  const PlansScreen({super.key});

  @override
  ConsumerState<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends ConsumerState<PlansScreen> {
  final _couponCtrl = TextEditingController();
  bool _couponBusy = false;
  bool _cancelBusy = false;
  String? _couponError;

  @override
  void dispose() {
    _couponCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(currentSubscriptionProvider);
    await ref.read(currentSubscriptionProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final subAsync = ref.watch(currentSubscriptionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('باقتي')),
      body: subAsync.when(
        loading: () => const PlansSkeleton(),
        error: (e, _) => _PlansError(
          message: friendlyErrorMessage(e),
          onRetry: _refresh,
        ),
        data: (sub) {
          final hasPlan = sub != null && sub.hasActiveSubscription;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: hasPlan
                  ? _CurrentPlanView(
                      sub: sub,
                      cancelBusy: _cancelBusy,
                      onCancel: _cancelSubscription,
                    )
                  : _RedeemView(
                      sub: sub,
                      controller: _couponCtrl,
                      busy: _couponBusy,
                      errorText: _couponError,
                      onChanged: () {
                        if (_couponError != null) {
                          setState(() => _couponError = null);
                        }
                      },
                      onApply: _applyCoupon,
                    ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _applyCoupon() async {
    final code = _couponCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _couponError = 'أدخل رمز الكوبون أولاً');
      return;
    }
    if (_couponBusy) return;
    setState(() {
      _couponBusy = true;
      _couponError = null;
    });
    try {
      await ref.read(plansRepositoryProvider).applyCoupon(code);
      Haptics.success();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تفعيل الكوبون بنجاح! 🎉')),
        );
        _couponCtrl.clear();
      }
      await ref.read(authProvider.notifier).checkAuth();
      await _refresh();
      // Analytics: which plan a coupon unlocked (read after refresh).
      final sub = ref.read(currentSubscriptionProvider).valueOrNull;
      await ref.read(analyticsProvider).couponRedeemed(sub?.planName ?? 'unknown');
    } catch (e) {
      Haptics.error();
      if (mounted) setState(() => _couponError = couponErrorMessage(e));
    } finally {
      if (mounted) setState(() => _couponBusy = false);
    }
  }

  Future<void> _cancelSubscription() async {
    if (_cancelBusy) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'إلغاء الباقة؟',
      message:
          'سيتم إرجاعك إلى الباقة المجانية فوراً. لو كانت باقتك مفعّلة بكوبون، '
          'الكوبون لا يُسترَد.',
      confirmLabel: 'إلغاء الباقة',
      cancelLabel: 'تراجع',
      destructive: true,
    );
    if (!confirmed) return;

    setState(() => _cancelBusy = true);
    try {
      await ref.read(plansRepositoryProvider).cancelSubscription();
      Haptics.success();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إلغاء الباقة')),
        );
      }
      await ref.read(authProvider.notifier).checkAuth();
      await _refresh();
      await ref.read(analyticsProvider).subscriptionCancelled();
    } catch (e) {
      Haptics.error();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cancelBusy = false);
    }
  }
}

// ============================================================================
// Has-a-plan view: current plan card + today's usage + cancel button
// ============================================================================
class _CurrentPlanView extends StatelessWidget {
  final CurrentSubscription sub;
  final bool cancelBusy;
  final VoidCallback onCancel;

  const _CurrentPlanView({
    required this.sub,
    required this.cancelBusy,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- Current plan card -------------------------------------------
        Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: scheme.primary, width: 2),
            color: scheme.primaryContainer.withValues(alpha: 0.25),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.workspace_premium, color: scheme.primary, size: 28),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'باقتك ${planLabel(sub.planName)}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _ExpiryChip(sub: sub),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        // --- Usage today --------------------------------------------------
        Text('استهلاكك اليوم',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        _UsageBar(
          used: sub.requestsToday,
          limit: sub.dailyLimit,
        ),
        const SizedBox(height: AppSpacing.lg),
        _InfoRow(
          icon: Icons.timer_outlined,
          label: 'الحد الأقصى لمدة الصوت',
          value: sub.maxAudioSeconds == -1
              ? 'بلا حدود'
              : '${sub.maxAudioSeconds} ثانية',
        ),
        const SizedBox(height: AppSpacing.xxl),

        // --- Cancel -------------------------------------------------------
        OutlinedButton.icon(
          onPressed: cancelBusy ? null : onCancel,
          style: OutlinedButton.styleFrom(
            foregroundColor: scheme.error,
            side: BorderSide(color: scheme.error),
            minimumSize: const Size(0, 52),
          ),
          icon: cancelBusy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cancel_outlined),
          label: const Text('إلغاء الباقة'),
        ),
      ],
    );
  }
}

class _ExpiryChip extends StatelessWidget {
  final CurrentSubscription sub;
  const _ExpiryChip({required this.sub});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final IconData icon;
    final String text;
    final Color color;

    if (sub.isPermanent) {
      icon = Icons.all_inclusive;
      text = 'باقة دائمة — لا تنتهي';
      color = scheme.primary;
    } else if (sub.expiresAt != null) {
      final exp = DateTime.tryParse(sub.expiresAt!);
      if (exp != null) {
        final days = exp.difference(DateTime.now()).inDays;
        icon = Icons.event_available;
        text = days >= 0
            ? 'تنتهي بعد $days يوم'
            : 'منتهية';
        color = days <= 3 ? scheme.error : scheme.onSurfaceVariant;
      } else {
        icon = Icons.event;
        text = 'فعّالة';
        color = scheme.onSurfaceVariant;
      }
    } else {
      icon = Icons.check_circle_outline;
      text = 'فعّالة';
      color = scheme.onSurfaceVariant;
    }

    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppSpacing.sm),
        Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _UsageBar extends StatelessWidget {
  final int used;
  final int limit; // -1 = unlimited
  const _UsageBar({required this.used, required this.limit});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unlimited = limit == -1;
    final ratio = unlimited || limit == 0
        ? 0.0
        : (used / limit).clamp(0.0, 1.0);
    final nearLimit = !unlimited && ratio >= 0.8;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              unlimited ? '$used طلب' : '$used من $limit طلب',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (unlimited)
              Text('بلا حدود',
                  style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LinearProgressIndicator(
            value: unlimited ? 0.0 : ratio,
            minHeight: 10,
            backgroundColor: scheme.surfaceContainerHighest,
            color: nearLimit ? scheme.error : scheme.primary,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: scheme.primary),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// ============================================================================
// No-plan view: explain premium is coupon-unlocked, show coupon redemption.
// NO prices, NO purchase buttons — the app is free; coupons are the only path.
// ============================================================================
class _RedeemView extends StatelessWidget {
  final CurrentSubscription? sub;
  final TextEditingController controller;
  final bool busy;
  final String? errorText;
  final VoidCallback onChanged;
  final VoidCallback onApply;

  const _RedeemView({
    required this.sub,
    required this.controller,
    required this.busy,
    required this.errorText,
    required this.onChanged,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Current (free) usage so the user still sees where they stand.
        if (sub != null) ...[
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('باقتك الحالية: المجانية',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.md),
                _UsageBar(
                  used: sub!.requestsToday,
                  limit: sub!.dailyLimit,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],

        // Hero: premium is unlocked by a coupon.
        Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            color: scheme.primaryContainer.withValues(alpha: 0.3),
          ),
          child: Column(
            children: [
              Icon(Icons.card_giftcard, size: 48, color: scheme.primary),
              const SizedBox(height: AppSpacing.md),
              Text(
                'فعّل المزايا المتقدمة بكوبون',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'لو معاك رمز كوبون، أدخله هنا عشان تفعّل الباقة المدفوعة '
                'بمزاياها كاملة — مجاناً.',
                style: TextStyle(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        // Coupon input
        TextField(
          controller: controller,
          enabled: !busy,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: 'رمز الكوبون',
            hintText: 'HEARING-XXXXX',
            errorText: errorText,
            prefixIcon: const Icon(Icons.confirmation_number_outlined),
          ),
          onChanged: (_) => onChanged(),
          onSubmitted: (_) => onApply(),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton(
          onPressed: busy ? null : onApply,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('تفعيل الكوبون'),
        ),
        const SizedBox(height: AppSpacing.xl),
        // Help link: deaf users sometimes get coupons via support, so a
        // direct "contact us" hook lives here on the redeem view.
        Center(
          child: TextButton.icon(
            onPressed: () => context.push('/contact'),
            icon: const Icon(Icons.help_outline, size: 18),
            label: const Text('تحتاج إلى مساعدة؟'),
          ),
        ),
      ],
    );
  }
}

class _PlansError extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _PlansError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 64, color: scheme.onSurfaceVariant),
            const SizedBox(height: AppSpacing.lg),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('حاول مرة أخرى'),
            ),
          ],
        ),
      ),
    );
  }
}
