class RuleItem {
  final String type;
  final String payload;
  final String proxy;

  const RuleItem({
    required this.type,
    required this.payload,
    required this.proxy,
  });

  factory RuleItem.fromJson(Map<String, dynamic> json) {
    return RuleItem(
      type: json['type'] as String? ?? '',
      payload: json['payload'] as String? ?? '',
      proxy: json['proxy'] as String? ?? '',
    );
  }
}
