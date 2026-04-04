class ParserConfig {
  const ParserConfig({
    required this.version,
    required this.endpointUrl,
    required this.formFields,
    required this.balanceSelector,
    required this.transactionSelector,
    required this.transactionFields,
  });

  final int version;
  final String endpointUrl;
  final ParserFormFields formFields;
  final String balanceSelector;
  final String transactionSelector;
  final ParserTransactionFields transactionFields;

  factory ParserConfig.fromJson(Map<String, dynamic> json) {
    return ParserConfig(
      version: json['version'] as int,
      endpointUrl: json['endpointUrl'] as String,
      formFields: ParserFormFields.fromJson(
        json['formFields'] as Map<String, dynamic>,
      ),
      balanceSelector: json['balanceSelector'] as String,
      transactionSelector: json['transactionSelector'] as String,
      transactionFields: ParserTransactionFields.fromJson(
        json['transactionFields'] as Map<String, dynamic>,
      ),
    );
  }
}

class ParserFormFields {
  const ParserFormFields({
    required this.cardNumber,
    required this.expiryMonth,
    required this.expiryYear,
    required this.cvv,
    required this.pin,
  });

  final String cardNumber;
  final String expiryMonth;
  final String expiryYear;
  final String cvv;
  final String pin;

  factory ParserFormFields.fromJson(Map<String, dynamic> json) {
    return ParserFormFields(
      cardNumber: json['cardNumber'] as String,
      expiryMonth: json['expiryMonth'] as String,
      expiryYear: json['expiryYear'] as String,
      cvv: json['cvv'] as String,
      pin: json['pin'] as String,
    );
  }
}

class ParserTransactionFields {
  const ParserTransactionFields({
    required this.date,
    required this.description,
    required this.amount,
  });

  final String date;
  final String description;
  final String amount;

  factory ParserTransactionFields.fromJson(Map<String, dynamic> json) {
    return ParserTransactionFields(
      date: json['date'] as String,
      description: json['description'] as String,
      amount: json['amount'] as String,
    );
  }
}
