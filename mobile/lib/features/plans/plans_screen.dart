import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bisawtak/core/api/api_client.dart';
import 'package:bisawtak/core/auth/auth_provider.dart';
import 'package:bisawtak/data/models/plan.dart';
import 'package:bisawtak/shared/utils/error_messages.dart';

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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyErrorMessage(e))),
        data: (planList) {
          // Mark the most-discounted paid plan as primary. Falls back to the
          // largest-tier plan when no discounts exist.
          final primaryId = _pickPrimary(planList);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                ...planList.map((plan) => _PlanCard(
                      plan: plan,
                      isPrimary: plan.id == primaryId,
                      busy: _busyPlanId == plan.id,
                      disabled: _busyPlanId != null && _busyPlanId != plan.id,
                      onSubscribe: () => _subscribe(plan.id),
                    )),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                Text('لديك كوبون؟', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _couponCtrl,
                        decoration: const InputDecoration(hintText: 'أدخل رمز الكوبون'),
                        enabled: !_couponBusy,
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _couponBusy ? null : _applyCoupon,
                      child: _couponBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
    // Prefer the most-discounted plan.
    paid.sort((a, b) => b.discountPercent.compareTo(a.discountPercent));
    if (paid.first.hasDiscount) return paid.first.id;
    // Otherwise: largest tier (by maxAudioSeconds, with -1 meaning unlimited).
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
      await ref.read(apiClientProvider).dio.post('/plans/subscribe', data: {'plan_id': planId});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم الاشتراك بنجاح!')),
        );
      }
      // Refresh user so profile shows the new plan immediately.
      await ref.read(authProvider.notifier).checkAuth();
      ref.invalidate(plansProvider);
    } on DioException catch (e) {
      if (e.response?.statusCode == 402) {
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('باقة تتطلب كوبون'),
              content: const Text('هذه الباقة تتطلب كوبون. تواصل معنا لشراء الباقة.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('تم'),
                ),
              ],
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyErrorMessage(e)), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busyPlanId = null);
    }
  }

  Future<void> _applyCoupon() async {
    final code = _couponCtrl.text.trim();
    if (code.isEmpty || _couponBusy) return;
    setState(() => _couponBusy = true);
    try {
      await ref.read(apiClientProvider).dio.post('/plans/coupon', data: {'code': code});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تطبيق الكوبون بنجاح!')),
        );
        _couponCtrl.clear();
      }
      // Refresh user / plan list.
      await ref.read(authProvider.notifier).checkAuth();
      ref.invalidate(plansProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _couponBusy = false);
    }
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
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPrimary ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
          width: isPrimary ? 2 : 1,
        ),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _planName(plan.name),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (plan.hasDiscount) ...[
                      Text(
                        '${plan.originalPrice.toInt()}',
                        style: TextStyle(
                          decoration: TextDecoration.lineThrough,
                          color: Colors.grey.shade500,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      plan.isFree ? 'مجاني' : '${plan.price.toInt()}',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    if (!plan.isFree)
                      Text(
                        plan.name == 'monthly' ? ' /شهرياً' : ' /سنوياً',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _Feature(icon: Icons.timer, text: plan.isUnlimited ? 'بلا حدود في مدة الصوت' : 'حد أقصى ${plan.maxAudioSeconds} ثانية'),
                _Feature(icon: Icons.block, text: plan.isFree ? 'يحتوي على إعلانات' : 'بدون إعلانات'),
                const SizedBox(height: 16),
                if (!plan.isFree)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (busy || disabled) ? null : onSubscribe,
                      child: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('اشترك الآن'),
                    ),
                  ),
              ],
            ),
          ),
          if (plan.hasDiscount)
            Positioned(
              top: 0, left: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Text(
                  'خصم ${plan.discountPercent.toInt()}%',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _planName(String name) {
    switch (name) {
      case 'free': return 'مجانية';
      case 'monthly': return 'شهرية';
      case 'annual': return 'سنوية';
      default: return name;
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(text),
        ],
      ),
    );
  }
}
