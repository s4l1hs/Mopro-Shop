class CheckoutRequestDto {
  const CheckoutRequestDto({
    required this.buyerName,
    required this.buyerSurname,
    this.addressId,
    this.returnUrl = 'mopro://checkout/result',
  });

  final String buyerName;
  final String buyerSurname;
  final int? addressId; // selected delivery address (OR-02); snapshotted on the order
  final String returnUrl;

  Map<String, dynamic> toJson() => {
        'buyer_name': buyerName,
        'buyer_surname': buyerSurname,
        'buyer_email': '',
        if (addressId != null) 'address_id': addressId,
        'return_url': returnUrl,
      };
}
