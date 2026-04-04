enum CardNetwork { visa, mastercard, unknown }

enum CardSortOption { dateAddedNewest, balanceLowToHigh, balanceHighToLow, expirySoonest }

class VaultCard {
  const VaultCard({
    required this.id,
    required this.network,
    required this.last4,
    required this.expiry,
    required this.addedAt,
    this.nickname,
    this.balance,
    this.transactions = const [],
    this.lastFetchedAt,
    this.fetchFailureCount = 0,
    this.refreshBlockedUntil,
  });

  final String id;
  final String? nickname;
  final CardNetwork network;
  final String last4;
  final String expiry;
  final double? balance;
  final List<CardTransaction> transactions;
  final DateTime? lastFetchedAt;
  final int fetchFailureCount;
  final DateTime addedAt;
  final DateTime? refreshBlockedUntil;

  String get displayName => nickname?.trim().isNotEmpty == true ? nickname!.trim() : '•••• $last4';

  bool get isRefreshCoolingDown =>
      refreshBlockedUntil != null && refreshBlockedUntil!.isAfter(DateTime.now());

  VaultCard copyWith({
    String? nickname,
    CardNetwork? network,
    String? expiry,
    double? balance,
    List<CardTransaction>? transactions,
    DateTime? lastFetchedAt,
    int? fetchFailureCount,
    DateTime? refreshBlockedUntil,
  }) {
    return VaultCard(
      id: id,
      nickname: nickname ?? this.nickname,
      network: network ?? this.network,
      last4: last4,
      expiry: expiry ?? this.expiry,
      balance: balance ?? this.balance,
      transactions: transactions ?? this.transactions,
      lastFetchedAt: lastFetchedAt ?? this.lastFetchedAt,
      fetchFailureCount: fetchFailureCount ?? this.fetchFailureCount,
      addedAt: addedAt,
      refreshBlockedUntil: refreshBlockedUntil ?? this.refreshBlockedUntil,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nickname': nickname,
      'network': network.name,
      'last4': last4,
      'expiry': expiry,
      'balance': balance,
      'transactions': transactions.map((tx) => tx.toJson()).toList(),
      'lastFetchedAt': lastFetchedAt?.toIso8601String(),
      'fetchFailureCount': fetchFailureCount,
      'addedAt': addedAt.toIso8601String(),
      'refreshBlockedUntil': refreshBlockedUntil?.toIso8601String(),
    };
  }

  factory VaultCard.fromJson(Map<dynamic, dynamic> json) {
    return VaultCard(
      id: json['id'] as String,
      nickname: json['nickname'] as String?,
      network: CardNetwork.values.firstWhere(
        (value) => value.name == json['network'],
        orElse: () => CardNetwork.unknown,
      ),
      last4: json['last4'] as String,
      expiry: json['expiry'] as String,
      balance: (json['balance'] as num?)?.toDouble(),
      transactions: (json['transactions'] as List<dynamic>? ?? const [])
          .map((item) => CardTransaction.fromJson(item as Map<dynamic, dynamic>))
          .toList(),
      lastFetchedAt: json['lastFetchedAt'] == null
          ? null
          : DateTime.parse(json['lastFetchedAt'] as String),
      fetchFailureCount: (json['fetchFailureCount'] as num?)?.toInt() ?? 0,
      addedAt: DateTime.parse(json['addedAt'] as String),
      refreshBlockedUntil: json['refreshBlockedUntil'] == null
          ? null
          : DateTime.parse(json['refreshBlockedUntil'] as String),
    );
  }
}

class CardTransaction {
  const CardTransaction({
    required this.date,
    required this.description,
    required this.amount,
  });

  final DateTime date;
  final String description;
  final double amount;

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'description': description,
      'amount': amount,
    };
  }

  factory CardTransaction.fromJson(Map<dynamic, dynamic> json) {
    return CardTransaction(
      date: DateTime.parse(json['date'] as String),
      description: json['description'] as String,
      amount: (json['amount'] as num).toDouble(),
    );
  }
}
