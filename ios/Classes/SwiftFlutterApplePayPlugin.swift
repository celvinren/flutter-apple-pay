import Flutter
import UIKit
import Foundation
import PassKit
import Stripe



public class SwiftFlutterApplePayPlugin: NSObject, FlutterPlugin, PKPaymentAuthorizationViewControllerDelegate {
   
    
    var pkrequest = PKPaymentRequest()
    var flutterResult: FlutterResult!
    
    var completionHandler: ((Any) -> Void)! // PKPaymentAuthorizationStatus || PKPaymentAuthorizationResult > ios 11
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_apple_pay", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(SwiftFlutterApplePayPlugin(), channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "getStripeToken" {
            
            do {
            flutterResult = result;
            let parameters = NSMutableDictionary()
            var items = [PKPaymentSummaryItem]()
            let arguments = call.arguments as! NSDictionary
            
            guard let paymentNeworks = arguments["paymentNetworks"] as? [String] else { throw PaymentError.input(error: "No payment networks provided") }
            guard let countryCode = arguments["countryCode"] as? String else { throw PaymentError.input(error: "No country code provided") }
            guard let currencyCode = arguments["currencyCode"] as? String else { throw PaymentError.input(error: "No currency code provided") }
            guard let stripePublishedKey = arguments["stripePublishedKey"] as? String else { throw PaymentError.input(error: "No Stripe key provided") }
            guard let paymentItems = arguments["paymentItems"] as? [NSDictionary], paymentItems.count > 0 else { throw PaymentError.input(error: "No payment items provided") }
            guard let merchantIdentifier = arguments["merchantIdentifier"] as? String else { throw PaymentError.input(error: "No merchant identifier provided") }
            guard let merchantName = arguments["merchantName"] as? String else { throw PaymentError.input(error: "No merchant name provided") }
                
            let isPending = arguments["isPending"] as? Bool ?? false
            let shippingFields = arguments["shippingFields"] as? [String] ?? []
            
            let financialStatus = isPending ? PKPaymentSummaryItemType.pending : PKPaymentSummaryItemType.final
            
                
            var totalPrice: Double = 0.0
            for dictionary in paymentItems {
                guard let label = dictionary["label"] as? String else {return}
                guard let price = dictionary["amount"] as? Double else {return}

                totalPrice += price
                
                items.append(PKPaymentSummaryItem(label: label, amount: NSDecimalNumber(floatLiteral: price), type: financialStatus))
            }
            
            Stripe.setDefaultPublishableKey(stripePublishedKey)
            
            let total = PKPaymentSummaryItem(label: merchantName, amount: NSDecimalNumber(floatLiteral:totalPrice), type: financialStatus)
            items.append(total)
            
            let paymentNetworkList: [PKPaymentNetwork] = try paymentNeworks.compactMap { system in
                
                guard let paymentSystem = PaymentSystem(rawValue: system) else {
                    throw PaymentError.input(error: "No payment type found")
                }
                
                return paymentSystem.paymentNetwork
            }
            parameters["paymentNetworks"] = paymentNetworkList
            


            if #available(iOS 11.0, *) {

                let shipping:[PKContactField] = try shippingFields.compactMap { field in
                
                    guard let shippingField = ShippingField(rawValue: field) else {
                        throw PaymentError.input(error: "No shipping field type found")
                    }
                
                    return shippingField.field
                }
                parameters["requiredShippingContactFields"] = Set(shipping)
            }
            parameters["merchantCapabilities"] = PKMerchantCapability.capability3DS // optional
            
            parameters["merchantIdentifier"] = merchantIdentifier
            parameters["countryCode"] = countryCode
            parameters["currencyCode"] = currencyCode
            
            parameters["paymentSummaryItems"] = items
            
            makePaymentRequest(parameters: parameters)
            }
            catch (let e) {
                if let e = e as? PaymentError {
                    let error: NSDictionary = ["message": e.description, "code": "402"]
                    flutterResult(error)
                }
                else {
                    flutterResult(e)
                }
            }
        }
        else if call.method == "closeApplePaySheetWithSuccess" {
            closeApplePaySheetWithSuccess()
        }
        else if call.method == "closeApplePaySheetWithError" {
            closeApplePaySheetWithError()
        }  else {
            flutterResult("Flutter method not implemented on iOS")
        }
    }
    
    func authorizationCompletion(_ payment: String) {
        flutterResult(payment)
    }
    
    func authorizationViewControllerDidFinish(_ error : NSDictionary) {
        //error
        flutterResult(error)
    }
    
    enum ShippingField: String {
        case name
        case postalAddress
        case emailAddress
        case phoneNumber
        case phoneticName
        
        var field: PKContactField? {
            
            switch self {
                default:
                if #available(iOS 11.0, *) {
                    if self == .name {
                        return PKContactField.name
                    }
                    if self == .postalAddress {
                        return PKContactField.postalAddress
                    }
                    if self == .emailAddress {
                        return PKContactField.emailAddress
                    }
                    if self == .phoneNumber {
                        return PKContactField.phoneNumber
                    }
                    if self == .phoneticName {
                        return PKContactField.phoneticName
                    }
                }
                return nil
            }
        }
    }

    enum PaymentSystem: String {
        case visa
        case mastercard
        case amex
        case quicPay
        case chinaUnionPay
        case discover
        case interac
        case privateLabel
        
        var paymentNetwork: PKPaymentNetwork? {
            
            switch self {
                case .mastercard: return PKPaymentNetwork.masterCard
                case .visa: return PKPaymentNetwork.visa
                case .amex: return PKPaymentNetwork.amex
                case .chinaUnionPay: return PKPaymentNetwork.chinaUnionPay
                case .discover: return PKPaymentNetwork.discover
                case .interac: return PKPaymentNetwork.interac
                case .privateLabel: return PKPaymentNetwork.privateLabel
            default:
                if #available(iOS 10.3, *) {
                    if self == .quicPay {
                        return PKPaymentNetwork.quicPay
                    }
                }
                return nil
            }
        }
    }
    
    enum PaymentError: Error{
        case input( error: String)
        
        var description: String {
            switch self {
            case .input(let error):
                return error
            }
        }
    }
    
    
    func makePaymentRequest(parameters: NSDictionary) {
        guard let paymentNetworks               = parameters["paymentNetworks"]                 as? [PKPaymentNetwork] else {return}
        
        let requiredShippingContactFields = parameters["requiredShippingContactFields"]   as? Set<PKContactField> ?? Set()
        let merchantCapabilities : PKMerchantCapability = parameters["merchantCapabilities"]    as? PKMerchantCapability ?? .capability3DS
        
        guard let merchantIdentifier            = parameters["merchantIdentifier"]              as? String else {return}
        guard let countryCode                   = parameters["countryCode"]                     as? String else {return}
        guard let currencyCode                  = parameters["currencyCode"]                    as? String else {return}
        
        guard let paymentSummaryItems           = parameters["paymentSummaryItems"]             as? [PKPaymentSummaryItem] else {return}
        
        
        // Cards that should be accepted
        if PKPaymentAuthorizationViewController.canMakePayments(usingNetworks: paymentNetworks) {
            
            pkrequest.merchantIdentifier = merchantIdentifier
            pkrequest.countryCode = countryCode
            pkrequest.currencyCode = currencyCode
            pkrequest.supportedNetworks = paymentNetworks
            if #available(iOS 11.0, *) {
                pkrequest.requiredShippingContactFields = requiredShippingContactFields
            }
            // This is based on using Stripe
            pkrequest.merchantCapabilities = merchantCapabilities
            
            pkrequest.paymentSummaryItems = paymentSummaryItems
            
            let authorizationViewController = PKPaymentAuthorizationViewController(paymentRequest: pkrequest)
            
            if let viewController = authorizationViewController {
                viewController.delegate = self
                guard let currentViewController = UIApplication.shared.keyWindow?.topMostViewController() else {
                    return
                }
                currentViewController.present(viewController, animated: true)
            }
        } else {
            let error: NSDictionary = ["message": "User can not make payments", "code": "404"]
            authorizationViewControllerDidFinish(error)
         }
    }
    
    @available(iOS 11.0, *)
    public func paymentAuthorizationViewController(_ controller: PKPaymentAuthorizationViewController, didAuthorizePayment payment: PKPayment, handler completion: @escaping (PKPaymentAuthorizationResult) -> Void) {
        
        STPAPIClient.shared().createToken(with: payment) { (stripeToken, error) in
            guard error == nil, let stripeToken = stripeToken else {
                print(error!)
                completion(PKPaymentAuthorizationResult(status: .failure, errors: nil))
                return
            }
            
            self.authorizationCompletion(stripeToken.stripeID)
            self.completionHandler = completion as? ((Any) -> Void)
        }
    }
    
    public func paymentAuthorizationViewController(_ controller: PKPaymentAuthorizationViewController, didAuthorizePayment payment: PKPayment, completion: @escaping (PKPaymentAuthorizationStatus) -> Void) {
        
        STPAPIClient.shared().createToken(with: payment) { (stripeToken, error) in
            guard error == nil, let stripeToken = stripeToken else {
                print(error!)
                completion(PKPaymentAuthorizationStatus.failure)
                return
            }
            
            self.authorizationCompletion(stripeToken.stripeID)
            self.completionHandler = completion as? ((Any) -> Void)
        }
    }

    public func closeApplePaySheetWithSuccess() {
        if (self.completionHandler != nil) {
            if #available(iOS 11.0, *) {
                self.completionHandler(PKPaymentAuthorizationResult(status: .success, errors: nil))
            }
            else {
                self.completionHandler(PKPaymentAuthorizationStatus.success)
            }
        }
        else {
            UIApplication.shared.keyWindow?.topMostViewController()?.dismiss(animated: true, completion: nil)
        }
    }

    public func closeApplePaySheetWithError() {
        if (self.completionHandler != nil) {
            if #available(iOS 11.0, *) {
                self.completionHandler(PKPaymentAuthorizationResult(status: .failure, errors: nil))
            }
            else {
                self.completionHandler(PKPaymentAuthorizationStatus.failure)
            }
        }
        else {
            UIApplication.shared.keyWindow?.topMostViewController()?.dismiss(animated: true, completion: nil)
        }
    }
    
    public func paymentAuthorizationViewControllerDidFinish(_ controller: PKPaymentAuthorizationViewController) {
        // Dismiss the Apple Pay UI
        guard let currentViewController = UIApplication.shared.keyWindow?.topMostViewController() else {
            return
        }
        currentViewController.dismiss(animated: true, completion: nil)
        let error: NSDictionary = ["message": "User closed apple pay", "code": "400"]
        authorizationViewControllerDidFinish(error)
    }
    
    func makePaymentSummaryItems(itemsParameters: Array<Dictionary <String, Any>>) -> [PKPaymentSummaryItem]? {
        var items = [PKPaymentSummaryItem]()
        var totalPrice:Decimal = 0.0
        
        for dictionary in itemsParameters {
            
            guard let label = dictionary["label"] as? String else {return nil}
            guard let amount = dictionary["amount"] as? NSDecimalNumber else {return nil}
            guard let type = dictionary["type"] as? PKPaymentSummaryItemType else {return nil}
            
            totalPrice += amount.decimalValue
            
            items.append(PKPaymentSummaryItem(label: label, amount: amount, type: type))
        }
        
        let total = PKPaymentSummaryItem(label: "Total", amount: NSDecimalNumber(decimal:totalPrice), type: .final)
        items.append(total)
        print(items)
        return items
    }
    
}

extension UIWindow {
    func topMostViewController() -> UIViewController? {
        guard let rootViewController = self.rootViewController else {
            return nil
        }
        return topViewController(for: rootViewController)
    }
    
    func topViewController(for rootViewController: UIViewController?) -> UIViewController? {
        guard let rootViewController = rootViewController else {
            return nil
        }
        guard let presentedViewController = rootViewController.presentedViewController else {
            return rootViewController
        }
        switch presentedViewController {
        case is UINavigationController:
            let navigationController = presentedViewController as! UINavigationController
            return topViewController(for: navigationController.viewControllers.last)
        case is UITabBarController:
            let tabBarController = presentedViewController as! UITabBarController
            return topViewController(for: tabBarController.selectedViewController)
        default:
            return topViewController(for: presentedViewController)
        }
    }
}
