import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_apple_pay/flutter_apple_pay.dart';

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
  }

  Future<void> makePayment() async {
    dynamic paymentToken;
    PaymentItem paymentItems = PaymentItem(label: "Item Name", amount: 100.0);
    try {
      await Future.delayed(Duration(milliseconds: 100));

      // wait because apple pay will put whole app in pause
      paymentToken = await FlutterApplePay.getStripeToken(
        stripePublishedKey: "pk_test_00000000000000000000000000",
        countryCode: "US",
        currencyCode: "USD",
        paymentNetworks: [
          PaymentNetwork.visa,
          PaymentNetwork.mastercard,
          PaymentNetwork.amex,
          PaymentNetwork.quicPay,
          PaymentNetwork.discover
        ],
        shippingFields: [
          ShippingField.emailAddress,
          ShippingField.name,
          ShippingField.phoneNumber,
          ShippingField.emailAddress,
        ],
        merchantIdentifier: "com.example.exampleapp",
        paymentItems: [paymentItems],
        merchantName: "Example",
      );

      if (paymentToken is String) {
        await FlutterApplePay.closeApplePaySheet(isSuccess: true);

        /**
           * Apple pay & stripe purchase complete
           */

      } else {
        await FlutterApplePay.closeApplePaySheet(isSuccess: false);
      }
    } on PlatformException {
      throw Exception('Failed to get platform version.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Apple Pay Test'),
        ),
        body: Center(
            child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('Waiting for Apple Pay modal.'),
            ElevatedButton(
              child: Text('Call payment'),
              onPressed: () => makePayment(),
            )
          ],
        )),
      ),
    );
  }
}
