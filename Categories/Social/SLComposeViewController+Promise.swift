import Social.SLComposeViewController
import UIKit.UIViewController
#if !COCOAPODS
#endif

/**
 To import this `UIViewController` category:

    use_frameworks!
    pod "PromiseKit/Social"

 And then in your sources:

*/
extension UIViewController {
    public func promiseViewController(vc: SLComposeViewController, animated: Bool = true, completion: (() -> Void)? = nil) -> Promise<Void> {
        presentViewController(vc, animated: animated, completion: completion)
        return Promise { fulfill, reject in
            vc.completionHandler = { result in
                if result == .Cancelled {
                    reject(SLComposeViewController.Error.Cancelled)
                } else {
                    fulfill()
                }
            }
        }
    }
}

extension SLComposeViewController {
    public enum Error: CancellableErrorType {
        case Cancelled

        public var cancelled: Bool {
            switch self { case .Cancelled: return true }
        }
    }
}
