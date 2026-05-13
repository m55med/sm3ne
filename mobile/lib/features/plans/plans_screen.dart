import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bisawtak/config/design_tokens.dart';
import 'package:bisawtak/core/api/api_client.dart';
import 'package:bisawtak/core/auth/auth_provider.dart';
import 'package:bisawtak/data/models/plan.dart';
import 'package:bisawtak/shared/utils/error_messages.dart';
import 'package:bisawtak/shared/utils/haptics.dart';
import 'package:bisawtak/shared/widgets/skeletons.dart';

final plansProvider = FutureProvider<List<Plan>>((ref) async {
  final resp = await ref.read(apiClientProvider).dio.get('/plans');
  return (resp.data as List).map((j) => Plan.fromJson(j)).toList();
});

class PlansScreen extends ConsumerStatefulWidget {
  const PlansScreen({super.key});

  @override
  ConsumerState<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends ConsumerState<PlansScreen> {
  final _couponCtrl = TextEditingController();
  int? _busyPlanId; // plan currently being subscribed to
  bool _couponBusy = false;
  String? _couponError; // inline error shown under the coupon field

  @override
  void dispose() {
    _couponCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(plansProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('الباقات')),
      body: plans.when(
        loading: () => const PlansSkeleton(),
        error: (e, _) => _PlansError(
          message: friendlyErrorMessage(e),
          onRetry: () => ref.invalidate(plansProvider),
        ),
        data: (planList) {
          final primaryId = _pickPrimary(planList);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: [
                ...planList.map((plan) => _PlanCard(
                      plan: plan,
                      isPrimary: plan.id == primaryId,
                      busy: _busyPlanId == plan.id,
                      disabled: _busyPlanId != null && _busyPlanId != plan.id,
                      onSubscribe: () => _subscribe(plan.id),
                    )),
                const SizedBox(height: AppSpacing.xl),
                const Divider(),
                const SizedBox(height: AppSpacing.lg),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    'لديك كوبون؟',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _couponCtrl,
                        decoration: InputDecoration(
                          hintText: 'أدخل رمز الكوبون',
                          errorText: _couponError,
                        ),
                        enabled: !_couponBusy,
                        textInputAction: TextInputAction.done,
                        onChanged: (_) {
                          if (_couponError != null) {
                            setState(() => _couponError = null);
                          }
                        },
                        onSubmitted: (_) => _applyCoupon(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    FilledButton(
                      onPressed: _couponBusy ? null : _applyCoupon,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 52),
                      ),
                      child: _couponBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('تطبيق'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  int? _pickPrimary(List<Plan> plans) {
    final paid = plans.where((p) => !p.isFree).toList();
    if (paid.isEmpty) return null;
    paid.sort((a, b) => b.discountPercent.compareTo(a.discountPercent));
    if (paid.first.hasDiscount) return paid.first.id;
    paid.sort((a, b) {
      final aSec = a.maxAudioSeconds == -1 ? 1 << 31 : a.maxAudioSeconds;
      final bSec = b.maxAudioSeconds == -1 ? 1 << 31 : b.maxAudioSeconds;
      return bSec.compareTo(aSec);
    });
    return paid.first.id;
  }

  Future<void> _subscribe(int planId) async {
    if (_busyPlanId != null) return;
    setState(() => _busyPlanId = planId);
    try {
      await ref.read(apiClientProvider).dio.post(
        '/plans/subscribe',
        data: {'plan_id': planId},
      );
      Haptics.success();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم الاشتراك بنجاح!')),
        );
      }
      await ref.read(authProvider.notifier).checkAuth();
      ref.invalidate(plansProvider);
    } on DioException catch (e) {
      Haptics.error();
      if (!mounted) return;
      if (e.response?.statusCode == 402) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('باقة تتطلب كوبون'),
            content: const Text(
              'هذه الباقة تتطلب كوبوناً للاشتراك. تواصل معنا للحصول على كوبون.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('حسناً'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
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
      if (mounted) setState(() => _busyPlanId = null);
    }
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
      await ref.read(apiClientProvider).dio.post(
        '/plans/coupon',
        data: {'code': code},
      );
      Haptics.success();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تطبيق الكوبون بنجاح!')),
        );
        _couponCtrl.clear();
      }
      await ref.read(authProvider.notifier).checkAuth();
      ref.invalidate(plansProvider);
    } catch (e) {
      Haptics.error();
      // Show the coupon-specific reason inline rather than as a snackbar —
      // the context is right next to the field, which is much clearer.
      if (mounted) {
        setState(() => _couponError = couponErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _couponBusy = false);
    }
  }
}

class _PlansError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
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

class _PlanCard extends StatelessWidget {
  final Plan plan;
  final bool isPrimary;
  final bool busy;
  final bool disabled;
  final VoidCallback onSubscribe;

  const _PlanCard({
    required this.plan,
    required this.isPrimary,
    required this.busy,
    required this.disabled,
    required this.onSubscribe,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isPrimary ? scheme.primary : scheme.outlineVariant,
          width: isPrimary ? 2 : 1,
        ),
        color: scheme.surface,
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _planName(plan.name),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (plan.hasDiscount) ...[
                      Text(
                        '${plan.originalPrice.toInt()}',
                        style: TextStyle(
                          decoration: TextDecoration.lineThrough,
                          color: scheme.onSurfaceVariant,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Text(
                      plan.isFree ? 'مجاني' : '${plan.price.toInt()}',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: scheme.primary,
                          ),
                    ),
                    if (!plan.isFree)
                      Text(
                        plan.name == 'monthly' ? ' /شهرياً' : ' /سنوياً',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _Feature(
                  icon: Icons.timer,
                  text: plan.isUnlimited
                      ? 'بلا حدود في مدة الصوت'
                      : 'حد أقصى ${plan.maxAudioSeconds} ثانية',
                ),
                _Feature(
                  icon: Icons.block,
                  text: plan.isFree ? 'يحتوي على إعلانات' : 'بدون إعلانات',
                ),
                const SizedBox(height: AppSpacing.lg),
                if (!plan.isFree)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (busy || disabled) ? null : onSubscribe,
                      child: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('اشترك الآن'),
                    ),
                  ),
              ],
            ),
          ),
          if (plan.hasDiscount)
            PositionedDirectional(
              top: 0,
              start: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: context.brand.discountBadge,
                  borderRadius: const BorderRadiusDirectional.only(
                    topStart: Radius.circular(AppRadius.lg),
                    bottomEnd: Radius.circular(AppRadius.md),
                  ),
                ),
                child: Text(
                  'خصم ${plan.discountPercent.toInt()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _planName(String name) {
    switch (name) {
      case 'free':
        return 'مجانية';
      case 'monthly':
        return 'شهرية';
      case 'annual':
        return 'سنوية';
      default:
        return name;
    }
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Feature({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
