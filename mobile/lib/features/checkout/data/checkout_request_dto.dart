class CheckoutRequestDto {
  const CheckoutRequestDto({
    required this.buyerName,
    required this.buyerSurname,
    this.returnUrl = 'mopro://checkout/result',
  });

  final String buyerName;
  final String buyerSurname;
  final String returnUrl;

  Map<String, dynamic> toJson() => {
        'buyer_name': buyerName,
        'buyer_surname': buyerSurname,
        'buyer_email': '',
        'return_url': returnUrl,
      };
}
