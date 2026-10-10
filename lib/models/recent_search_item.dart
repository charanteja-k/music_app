class RecentSearchItem {
  final String query;
  final int timestamp;
  final String type; // 'query', 'artist', 'track', 'album', 'category'

  const RecentSearchItem({
    required this.query,
    required this.timestamp,
    this.type = 'query',
  });

  Map<String, dynamic> toJson() => {
    'query': query,
    'timestamp': timestamp,
    'type': type,
  };

  factory RecentSearchItem.fromJson(Map<String, dynamic> json) =>
      RecentSearchItem(
        query: json['query'] as String? ?? '',
        timestamp:
            json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        type: json['type'] as String? ?? 'query',
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecentSearchItem &&
          runtimeType == other.runtimeType &&
          query.toLowerCase() == other.query.toLowerCase();

  @override
  int get hashCode => query.toLowerCase().hashCode;
}
