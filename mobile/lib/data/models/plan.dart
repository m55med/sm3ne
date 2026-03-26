class Plan {
  final int id;
  final String name;
  final double price;
  final double originalPrice;
  final int maxAudioSeconds;

  Plan({
    required this.id,
    required this.name,
    required this.price,
    required this.originalPrice,
    required this.maxAudioSeconds,
  });

  factory Plan.fromJson(Map<String, dynamic> json) {
    return Plan(
      id: json['id'],
      name: json['name'],
      price: (json['price'] ?? 0).toDouble(),
      originalPrice: (json['original_price'] ?? 0).toDouble(),
      maxAudioSeconds: json['max_audio_seconds'] ?? 30,
    );
  }

  bool get isFree => name == 'free';
  bool get isUnlimited => maxAudioSeconds == -1;
  bool get hasDiscount => originalPrice > price && price > 0;
  double get discountPercent => hasDiscount ? ((originalPrice - price) / originalPrice * 100) : 0;
}
