import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bisawtak/core/api/api_client.dart';
import 'package:bisawtak/data/models/plan.dart';

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

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(plansProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('الباقات')),
      body: plans.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('خطأ: $e')),
        data: (planList) => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              ...planList.map((plan) => _PlanCard(plan: plan, onSubscribe: () => _subscribe(plan.id))),
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
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _applyCoupon,
                    child: const Text('تطبيق'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _subscribe(int planId) async {
    try {
      await ref.read(apiClientProvider).dio.post('/plans/subscribe', data: {'plan_id': planId});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الاشتراك بنجاح!')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _applyCoupon() async {
    if (_couponCtrl.text.isEmpty) return;
    try {
      await ref.read(apiClientProvider).dio.post('/plans/coupon', data: {'code': _couponCtrl.text});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تطبيق الكوبون بنجاح!')));
        _couponCtrl.clear();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('كوبون غير صالح'), backgroundColor: Colors.red));
    }
  }
}

class _PlanCard extends StatelessWidget {
  final Plan plan;
  final VoidCallback onSubscribe;

  const _PlanCard({required this.plan, required this.onSubscribe});

  @override
  Widget build(BuildContext context) {
    final isPrimary = plan.name == 'annual';

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
                      onPressed: onSubscribe,
                      child: const Text('اشترك الآن'),
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
