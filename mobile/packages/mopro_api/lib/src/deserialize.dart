import 'package:mopro_api/src/model/add_cart_item_request.dart';
import 'package:mopro_api/src/model/address.dart';
import 'package:mopro_api/src/model/address_input.dart';
import 'package:mopro_api/src/model/banner.dart';
import 'package:mopro_api/src/model/brand_suggestion.dart';
import 'package:mopro_api/src/model/cart.dart';
import 'package:mopro_api/src/model/cart_item.dart';
import 'package:mopro_api/src/model/cashback_payment.dart';
import 'package:mopro_api/src/model/cashback_plan.dart';
import 'package:mopro_api/src/model/cashback_preview.dart';
import 'package:mopro_api/src/model/category.dart';
import 'package:mopro_api/src/model/category_commission.dart';
import 'package:mopro_api/src/model/category_promo_slot.dart';
import 'package:mopro_api/src/model/change_password_request.dart';
import 'package:mopro_api/src/model/checkout_request.dart';
import 'package:mopro_api/src/model/checkout_request_payment_method.dart';
import 'package:mopro_api/src/model/checkout_response.dart';
import 'package:mopro_api/src/model/checkout_response_payment.dart';
import 'package:mopro_api/src/model/create_order_request.dart';
import 'package:mopro_api/src/model/create_product_request.dart';
import 'package:mopro_api/src/model/cursor_pagination_meta.dart';
import 'package:mopro_api/src/model/delete_me_request.dart';
import 'package:mopro_api/src/model/delivery_address.dart';
import 'package:mopro_api/src/model/delivery_eta.dart';
import 'package:mopro_api/src/model/device.dart';
import 'package:mopro_api/src/model/error_envelope.dart';
import 'package:mopro_api/src/model/error_envelope_error.dart';
import 'package:mopro_api/src/model/facet.dart';
import 'package:mopro_api/src/model/facet_value.dart';
import 'package:mopro_api/src/model/field_error.dart';
import 'package:mopro_api/src/model/get_category_facets200_response.dart';
import 'package:mopro_api/src/model/list_addresses200_response.dart';
import 'package:mopro_api/src/model/list_banners200_response.dart';
import 'package:mopro_api/src/model/list_cashback_payments200_response.dart';
import 'package:mopro_api/src/model/list_cashback_plans200_response.dart';
import 'package:mopro_api/src/model/list_categories200_response.dart';
import 'package:mopro_api/src/model/list_orders200_response.dart';
import 'package:mopro_api/src/model/list_products200_response.dart';
import 'package:mopro_api/src/model/list_recommendations200_response.dart';
import 'package:mopro_api/src/model/list_returns200_response.dart';
import 'package:mopro_api/src/model/list_wallet_transactions200_response.dart';
import 'package:mopro_api/src/model/model_return.dart';
import 'package:mopro_api/src/model/order.dart';
import 'package:mopro_api/src/model/order_item.dart';
import 'package:mopro_api/src/model/pagination_meta.dart';
import 'package:mopro_api/src/model/product.dart';
import 'package:mopro_api/src/model/product_attribute.dart';
import 'package:mopro_api/src/model/product_summary.dart';
import 'package:mopro_api/src/model/recommendation.dart';
import 'package:mopro_api/src/model/refresh_token_request.dart';
import 'package:mopro_api/src/model/refund_order_request.dart';
import 'package:mopro_api/src/model/register_device_request.dart';
import 'package:mopro_api/src/model/release_cart_request.dart';
import 'package:mopro_api/src/model/request_otp_request.dart';
import 'package:mopro_api/src/model/reservation.dart';
import 'package:mopro_api/src/model/return_request.dart';
import 'package:mopro_api/src/model/return_request_items_inner.dart';
import 'package:mopro_api/src/model/search_trending200_response.dart';
import 'package:mopro_api/src/model/seller_binding.dart';
import 'package:mopro_api/src/model/seller_order_breakdown.dart';
import 'package:mopro_api/src/model/seller_order_breakdown_items_inner.dart';
import 'package:mopro_api/src/model/seller_order_breakdown_totals.dart';
import 'package:mopro_api/src/model/step_up_request.dart';
import 'package:mopro_api/src/model/step_up_token_response.dart';
import 'package:mopro_api/src/model/suggest_response.dart';
import 'package:mopro_api/src/model/token_pair.dart';
import 'package:mopro_api/src/model/update_me_request.dart';
import 'package:mopro_api/src/model/user.dart';
import 'package:mopro_api/src/model/variant.dart';
import 'package:mopro_api/src/model/verify_otp_request.dart';
import 'package:mopro_api/src/model/wallet_balance.dart';
import 'package:mopro_api/src/model/wallet_transaction.dart';

final _regList = RegExp(r'^List<(.*)>$');
final _regSet = RegExp(r'^Set<(.*)>$');
final _regMap = RegExp(r'^Map<String,(.*)>$');

  ReturnType deserialize<ReturnType, BaseType>(dynamic value, String targetType, {bool growable= true}) {
      switch (targetType) {
        case 'String':
          return '$value' as ReturnType;
        case 'int':
          return (value is int ? value : int.parse('$value')) as ReturnType;
        case 'bool':
          if (value is bool) {
            return value as ReturnType;
          }
          final valueString = '$value'.toLowerCase();
          return (valueString == 'true' || valueString == '1') as ReturnType;
        case 'double':
          return (value is double ? value : double.parse('$value')) as ReturnType;
        case 'AddCartItemRequest':
          return AddCartItemRequest.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'Address':
          return Address.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'AddressInput':
          return AddressInput.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'Banner':
          return Banner.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'BrandSuggestion':
          return BrandSuggestion.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'Cart':
          return Cart.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'CartItem':
          return CartItem.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'CashbackPayment':
          return CashbackPayment.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'CashbackPlan':
          return CashbackPlan.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'CashbackPreview':
          return CashbackPreview.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'Category':
          return Category.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'CategoryCommission':
          return CategoryCommission.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'CategoryPromoSlot':
          return CategoryPromoSlot.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'ChangePasswordRequest':
          return ChangePasswordRequest.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'CheckoutRequest':
          return CheckoutRequest.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'CheckoutRequestPaymentMethod':
          return CheckoutRequestPaymentMethod.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'CheckoutResponse':
          return CheckoutResponse.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'CheckoutResponsePayment':
          return CheckoutResponsePayment.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'CreateOrderRequest':
          return CreateOrderRequest.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'CreateProductRequest':
          return CreateProductRequest.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'CursorPaginationMeta':
          return CursorPaginationMeta.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'DeleteMeRequest':
          return DeleteMeRequest.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'DeliveryAddress':
          return DeliveryAddress.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'DeliveryEta':
          return DeliveryEta.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'Device':
          return Device.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'ErrorEnvelope':
          return ErrorEnvelope.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'ErrorEnvelopeError':
          return ErrorEnvelopeError.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'Facet':
          return Facet.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'FacetValue':
          return FacetValue.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'FieldError':
          return FieldError.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'GetCategoryFacets200Response':
          return GetCategoryFacets200Response.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'ListAddresses200Response':
          return ListAddresses200Response.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'ListBanners200Response':
          return ListBanners200Response.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'ListCashbackPayments200Response':
          return ListCashbackPayments200Response.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'ListCashbackPlans200Response':
          return ListCashbackPlans200Response.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'ListCategories200Response':
          return ListCategories200Response.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'ListOrders200Response':
          return ListOrders200Response.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'ListProducts200Response':
          return ListProducts200Response.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'ListRecommendations200Response':
          return ListRecommendations200Response.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'ListReturns200Response':
          return ListReturns200Response.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'ListWalletTransactions200Response':
          return ListWalletTransactions200Response.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'ModelReturn':
          return ModelReturn.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'Order':
          return Order.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'OrderItem':
          return OrderItem.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'PaginationMeta':
          return PaginationMeta.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'Product':
          return Product.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'ProductAttribute':
          return ProductAttribute.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'ProductSummary':
          return ProductSummary.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'Recommendation':
          return Recommendation.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'RefreshTokenRequest':
          return RefreshTokenRequest.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'RefundOrderRequest':
          return RefundOrderRequest.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'RegisterDeviceRequest':
          return RegisterDeviceRequest.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'ReleaseCartRequest':
          return ReleaseCartRequest.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'RequestOtpRequest':
          return RequestOtpRequest.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'Reservation':
          return Reservation.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'ReturnRequest':
          return ReturnRequest.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'ReturnRequestItemsInner':
          return ReturnRequestItemsInner.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'SearchTrending200Response':
          return SearchTrending200Response.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'SellerBinding':
          return SellerBinding.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'SellerOrderBreakdown':
          return SellerOrderBreakdown.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'SellerOrderBreakdownItemsInner':
          return SellerOrderBreakdownItemsInner.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'SellerOrderBreakdownTotals':
          return SellerOrderBreakdownTotals.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'StepUpRequest':
          return StepUpRequest.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'StepUpTokenResponse':
          return StepUpTokenResponse.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'SuggestResponse':
          return SuggestResponse.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'TokenPair':
          return TokenPair.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'UpdateMeRequest':
          return UpdateMeRequest.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'User':
          return User.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'Variant':
          return Variant.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'VerifyOtpRequest':
          return VerifyOtpRequest.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'WalletBalance':
          return WalletBalance.fromJson(value as Map<String, dynamic>) as ReturnType;
        case 'WalletTransaction':
          return WalletTransaction.fromJson(value as Map<String, dynamic>) as ReturnType;
        default:
          RegExpMatch? match;

          if (value is List && (match = _regList.firstMatch(targetType)) != null) {
            targetType = match![1]!; // ignore: parameter_assignments
            return value
              .map<BaseType>((dynamic v) => deserialize<BaseType, BaseType>(v, targetType, growable: growable))
              .toList(growable: growable) as ReturnType;
          }
          if (value is Set && (match = _regSet.firstMatch(targetType)) != null) {
            targetType = match![1]!; // ignore: parameter_assignments
            return value
              .map<BaseType>((dynamic v) => deserialize<BaseType, BaseType>(v, targetType, growable: growable))
              .toSet() as ReturnType;
          }
          if (value is Map && (match = _regMap.firstMatch(targetType)) != null) {
            targetType = match![1]!.trim(); // ignore: parameter_assignments
            return Map<String, BaseType>.fromIterables(
              value.keys as Iterable<String>,
              value.values.map((dynamic v) => deserialize<BaseType, BaseType>(v, targetType, growable: growable)),
            ) as ReturnType;
          }
          break;
    }
    throw Exception('Cannot deserialize');
  }