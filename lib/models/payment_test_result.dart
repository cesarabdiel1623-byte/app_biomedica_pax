enum PaymentTestResult { success, pending, failure }

class PaymentReturnData {
  const PaymentReturnData({this.orderId, this.status, this.externalReference});

  final String? orderId;
  final String? status;
  final String? externalReference;
}
