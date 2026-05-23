class CheckoutRequestDto {
  const CheckoutRequestDto({
    required this.addressId,
    required this.paymentMethod,
  });

  final int addressId;
  final String paymentMethod;

  Map<String, dynamic> toJson() => {
        'address_id': addressId,
        'payment_method': paymentMethod,
      };
}
