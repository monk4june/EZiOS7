import Dispatch
import Foundation.NSDate

/**
 ```
 after(1).then {
     //…
 }
 ```

 - Returns: A new promise that resolves after the specified duration.
 - Parameter duration: The duration in seconds to wait before this promise is resolve.
*/
public func after(delay: NSTimeInterval) -> Promise<Void> {
    return Promise { fulfill, _ in
        let delta = delay * NSTimeInterval(NSEC_PER_SEC)
        let when = dispatch_time(DISPATCH_TIME_NOW, Int64(delta))
        dispatch_after(when, dispatch_get_global_queue(0, 0), fulfill)
    }
}
import Foundation.NSError

@objc(AnyPromise) public class AnyPromise: NSObject {

    private var state: State

    /**
     - Returns: A new AnyPromise bound to a Promise<T?>.
     The two promises represent the same task, any changes to either will instantly reflect on both.
    */
    public init<T: AnyObject>(bound: Promise<T?>) {
        var resolve: ((AnyObject?) -> Void)!
        state = State(resolver: &resolve)
        bound.pipe { resolution in
            switch resolution {
            case .Fulfilled(let value):
                resolve(value)
            case .Rejected(let error, let token):
                let nserror = error as NSError
                unconsume(error: nserror, reusingToken: token)
                resolve(nserror)
            }
        }
    }

    /**
     - Returns: A new AnyPromise bound to a Promise<T>.
     The two promises represent the same task, any changes to either will instantly reflect on both.
    */
    convenience public init<T: AnyObject>(bound: Promise<T>) {
        // FIXME efficiency. Allocating the extra promise for conversion sucks.
        self.init(bound: bound.then(on: zalgo){ Optional.Some($0) })
    }

    /**
     - Returns: A new `AnyPromise` bound to a `Promise<[T]>`.
     The two promises represent the same task, any changes to either will instantly reflect on both.
     The value is converted to an NSArray so Objective-C can use it.
    */
    convenience public init<T: AnyObject>(bound: Promise<[T]>) {
        self.init(bound: bound.then(on: zalgo) { NSArray(array: $0) })
    }

    /**
     - Returns: A new AnyPromise bound to a `Promise<[T:U]>`.
     The two promises represent the same task, any changes to either will instantly reflect on both.
     The value is converted to an NSDictionary so Objective-C can use it.
    */
    convenience public init<T: AnyObject, U: AnyObject>(bound: Promise<[T:U]>) {
        self.init(bound: bound.then(on: zalgo) { NSDictionary(dictionary: $0) })
    }

    /**
     - Returns: A new AnyPromise bound to a `Promise<Int>`.
     The two promises represent the same task, any changes to either will instantly reflect on both.
     The value is converted to an NSNumber so Objective-C can use it.
    */
    convenience public init(bound: Promise<Int>) {
        self.init(bound: bound.then(on: zalgo) { NSNumber(integer: $0) })
    }

    /**
     - Returns: A new AnyPromise bound to a `Promise<Void>`.
     The two promises represent the same task, any changes to either will instantly reflect on both.
    */
    convenience public init(bound: Promise<Void>) {
        self.init(bound: bound.then(on: zalgo) { Optional<AnyObject>.None })
    }

    @objc init(@noescape bridge: ((AnyObject?) -> Void) -> Void) {
        var resolve: ((AnyObject?) -> Void)!
        state = State(resolver: &resolve)
        bridge { result in
            if let next = result as? AnyPromise {
                next.pipe(resolve)
            } else {
                resolve(result)
            }
        }
    }

    @objc func pipe(body: (AnyObject?) -> Void) {
        state.get { seal in
            switch seal {
            case .Pending(let handlers):
                handlers.append(body)
            case .Resolved(let value):
                body(value)
            }
        }
    }

    @objc var __value: AnyObject? {
        return state.get() ?? nil
    }

    /**
     A promise starts pending and eventually resolves.
     - Returns: `true` if the promise has not yet resolved.
    */
    @objc public var pending: Bool {
        return state.get() == nil
    }

    /**
     A promise starts pending and eventually resolves.
     - Returns: `true` if the promise has resolved.
    */
    @objc public var resolved: Bool {
        return !pending
    }

    /**
     A fulfilled promise has resolved successfully.
     - Returns: `true` if the promise was fulfilled.
    */
    @objc public var fulfilled: Bool {
        switch state.get() {
        case .Some(let obj) where obj is NSError:
            return false
        case .Some:
            return true
        case .None:
            return false
        }
    }

    /**
     A rejected promise has resolved without success.
     - Returns: `true` if the promise was rejected.
    */
    @objc public var rejected: Bool {
        switch state.get() {
        case .Some(let obj) where obj is NSError:
            return true
        default:
            return false
        }
    }

    /**
     Continue a Promise<T> chain from an AnyPromise.
    */
    public func then<T>(on q: dispatch_queue_t = dispatch_get_main_queue(), body: (AnyObject?) throws -> T) -> Promise<T> {
        return Promise(sealant: { resolve in
            pipe { object in
                if let error = object as? NSError {
                    resolve(.Rejected(error, error.token))
                } else {
                    contain_zalgo(q, rejecter: resolve) {
                        resolve(.Fulfilled(try body(self.valueForKey("value"))))
                    }
                }
            }
        })
    }

    private class State: UnsealedState<AnyObject?> {
        required init(inout resolver: ((AnyObject?) -> Void)!) {
            var preresolve: ((AnyObject?) -> Void)!
            super.init(resolver: &preresolve)
            resolver = { obj in
                if let error = obj as? NSError { unconsume(error: error) }
                preresolve(obj)
            }
        }
    }
}


extension AnyPromise {
    override public var description: String {
        return "AnyPromise: \(state)"
    }
}
import Dispatch
import Foundation.NSError

/**
 ```
 dispatch_promise {
     try md5(input)
 }.then { md5 in
     //…
 }
 ```

 - Parameter on: The queue on which to dispatch `body`.
 - Parameter body: The closure that resolves this promise.
 - Returns: A new promise resolved by the provided closure.
*/
public func dispatch_promise<T>(on queue: dispatch_queue_t = dispatch_get_global_queue(0, 0), body: () throws -> T) -> Promise<T> {
    return Promise(sealant: { resolve in
        contain_zalgo(queue, rejecter: resolve) {
            resolve(.Fulfilled(try body()))
        }
    })
}
import Dispatch
import Foundation.NSError
import Foundation.NSURLError

public enum Error: ErrorType {
    /**
     The ErrorType for a rejected `when`.
     - Parameter 0: The index of the promise that was rejected.
     - Parameter 1: The error from the promise that rejected this `when`.
    */
    case When(Int, ErrorType)

    /**
     The ErrorType for a rejected `join`.
     - Parameter 0: The promises passed to this `join` that did not *all* fulfill.
     - Note: The array is untyped because Swift generics are fussy with enums.
    */
    case Join([AnyObject])

    /**
     The closure with form (T?, ErrorType?) was called with (nil, nil)
     This is invalid as per the calling convention.
    */
    case DoubleOhSux0r
}


//////////////////////////////////////////////////////////// Cancellation
private struct ErrorPair: Hashable {
    let domain: String
    let code: Int
    init(_ d: String, _ c: Int) {
        domain = d; code = c
    }
    var hashValue: Int {
        return "\(domain):\(code)".hashValue
    }
}

private func ==(lhs: ErrorPair, rhs: ErrorPair) -> Bool {
    return lhs.domain == rhs.domain && lhs.code == rhs.code
}

extension NSError {
    @objc class func cancelledError() -> NSError {
        let info: [NSObject: AnyObject] = [NSLocalizedDescriptionKey: "The operation was cancelled"]
        return NSError(domain: PMKErrorDomain, code: PMKOperationCancelled, userInfo: info)
    }

    /**
      - Warning: You may only call this method on the main thread.
     */
    @objc public class func registerCancelledErrorDomain(domain: String, code: Int) {
        cancelledErrorIdentifiers.insert(ErrorPair(domain, code))
    }
}

public protocol CancellableErrorType: ErrorType {
    var cancelled: Bool { get }
}

extension NSError: CancellableErrorType {
    /**
     - Warning: You may only call this method on the main thread.
    */
    @objc public var cancelled: Bool {
        if !NSThread.isMainThread() { NSLog("PromiseKit: Warning: `cancelled` called on background thread.") }

        return cancelledErrorIdentifiers.contains(ErrorPair(domain, code))
    }
}


////////////////////////////////////////// Predefined Cancellation Errors
private var cancelledErrorIdentifiers = Set([
    ErrorPair(PMKErrorDomain, PMKOperationCancelled),
    ErrorPair(NSURLErrorDomain, NSURLErrorCancelled)
])

extension NSURLError: CancellableErrorType {
    public var cancelled: Bool {
        return self == .Cancelled
    }
}


//////////////////////////////////////////////////////// Unhandled Errors
/**
 The unhandled error handler.

 If a promise is rejected and no catch handler is called in its chain,
 the provided handler is called. The default handler logs the error.

     PMKUnhandledErrorHandler = { error in
         mylogf("Unhandled error: \(error)")
     }

 - Warning: *Important* The handler is executed on an undefined queue.
 - Warning: *Important* Don’t use promises in your handler, or you risk an infinite error loop.
 - Returns: The previous unhandled error handler.
*/
public var PMKUnhandledErrorHandler = { (error: ErrorType) -> Void in
    dispatch_async(dispatch_get_main_queue()) {
        let cancelled = (error as? CancellableErrorType)?.cancelled ?? false
                                                       // ^-------^ must be called on main queue
        if !cancelled {
            NSLog("PromiseKit: Unhandled Error: %@", "\(error)")
        }
    }
}

class ErrorConsumptionToken {
    var consumed = false
    let error: ErrorType!

    init(_ error: ErrorType) {
        self.error = error
    }

    init(_ error: NSError) {
        self.error = error.copy() as! NSError
    }

    deinit {
        if !consumed {
            PMKUnhandledErrorHandler(error)
        }
    }
}

private var handle: UInt8 = 0

extension NSError {
    @objc func pmk_consume() {
        if let token = objc_getAssociatedObject(self, &handle) as? ErrorConsumptionToken {
            token.consumed = true
        }
    }

    var token: ErrorConsumptionToken! {
        return objc_getAssociatedObject(self, &handle) as? ErrorConsumptionToken
    }
}

func unconsume(error error: NSError, var reusingToken token: ErrorConsumptionToken? = nil) {
    if token != nil {
        objc_setAssociatedObject(error, &handle, token, .OBJC_ASSOCIATION_RETAIN)
    } else {
        token = objc_getAssociatedObject(error, &handle) as? ErrorConsumptionToken
        if token == nil {
            token = ErrorConsumptionToken(error)
            objc_setAssociatedObject(error, &handle, token, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    token!.consumed = false
}
import Dispatch

/**
 Waits on all provided promises.

 `when` rejects as soon as one of the provided promises rejects. `join` waits on all provided promises, then rejects if any of those promises rejected, otherwise it fulfills with values from the provided promises.

     join(promise1, promise2, promise3).then { results in
         //…
     }.report { error in
         switch error {
         case Error.Join(let promises):
             //…
         }
     }

 - Returns: A new promise that resolves once all the provided promises resolve.
*/
public func join<T>(promises: Promise<T>...) -> Promise<[T]> {
    var countdown = promises.count
    let barrier = dispatch_queue_create("org.promisekit.barrier.join", DISPATCH_QUEUE_CONCURRENT)
    var rejected = false

    return Promise { fulfill, reject in
        for promise in promises {
            promise.pipe { resolution in
                dispatch_barrier_sync(barrier) {
                    if case .Rejected(_, let token) = resolution {
                        token.consumed = true  // the parent Error.Join consumes all
                        rejected = true
                    }

                    if --countdown == 0 {
                        if rejected {
                            reject(Error.Join(promises))
                        } else {
                            fulfill(promises.map{ $0.value! })
                        }
                    }
                }
            }
        }
    }
}
import Foundation

public enum JSONError: ErrorType {
    case UnexpectedRootNode(AnyObject)
}

private func b0rkedEmptyRailsResponse() -> NSData {
    return NSData(bytes: " ", length: 1)
}

public func NSJSONFromData(data: NSData) throws -> NSArray {
    if data == b0rkedEmptyRailsResponse() {
        return NSArray()
    } else {
        let json = try NSJSONSerialization.JSONObjectWithData(data, options: .AllowFragments)
        guard let dict = json as? NSArray else { throw JSONError.UnexpectedRootNode(json) }
        return dict
    }
}

public func NSJSONFromData(data: NSData) throws -> NSDictionary {
    if data == b0rkedEmptyRailsResponse() {
        return NSDictionary()
    } else {
        let json = try NSJSONSerialization.JSONObjectWithData(data, options: .AllowFragments)
        guard let dict = json as? NSDictionary else { throw JSONError.UnexpectedRootNode(json) }
        return dict
    }
}
extension Promise {
    /**
     - Returns: The error with which this promise was rejected; `nil` if this promise is not rejected.
    */
    public var error: ErrorType? {
        switch state.get() {
        case .None:
            return nil
        case .Some(.Fulfilled):
            return nil
        case .Some(.Rejected(let error, _)):
            return error
        }
    }

    /**
     - Returns: `true` if the promise has not yet resolved.
    */
    public var pending: Bool {
        return state.get() == nil
    }

    /**
     - Returns: `true` if the promise has resolved.
    */
    public var resolved: Bool {
        return !pending
    }

    /**
     - Returns: `true` if the promise was fulfilled.
    */
    public var fulfilled: Bool {
        return value != nil
    }

    /**
     - Returns: `true` if the promise was rejected.
    */
    public var rejected: Bool {
        return error != nil
    }

    /**
     - Returns: The value with which this promise was fulfilled or `nil` if this promise is pending or rejected.
    */
    public var value: T? {
        switch state.get() {
        case .None:
            return nil
        case .Some(.Fulfilled(let value)):
            return value
        case .Some(.Rejected):
            return nil
        }
    }
}
import Dispatch
import Foundation.NSError

/**
 A *promise* represents the future value of a task.

 To obtain the value of a promise we call `then`.

 Promises are chainable: `then` returns a promise, you can call `then` on
 that promise, which returns a promise, you can call `then` on that
 promise, et cetera.

 Promises start in a pending state and *resolve* with a value to become
 *fulfilled* or with an `ErrorType` to become rejected.

 - SeeAlso: [PromiseKit `then` Guide](http://promisekit.org/then/)
 - SeeAlso: [PromiseKit Chaining Guide](http://promisekit.org/chaining/)
*/
public class Promise<T> {
    let state: State<Resolution<T>>

    /**
     Create a new pending promise.

     Use this method when wrapping asynchronous systems that do *not* use
     promises so that they can be involved in promise chains.

     Don’t use this method if you already have promises! Instead, just return
     your promise!

     The closure you pass is executed immediately on the calling thread.

         func fetchKitten() -> Promise<UIImage> {
             return Promise { fulfill, reject in
                 KittenFetcher.fetchWithCompletionBlock({ img, err in
                     if err == nil {
                         if img.size.width > 0 {
                             fulfill(img)
                         } else {
                             reject(Error.ImageTooSmall)
                         }
                     } else {
                         reject(err)
                     }
                 })
             }
         }

     - Parameter resolvers: The provided closure is called immediately.
     Inside, execute your asynchronous system, calling fulfill if it suceeds
     and reject for any errors.

     - Returns: return A new promise.

     - Note: If you are wrapping a delegate-based system, we recommend
     to use instead: Promise.pendingPromise()

     - SeeAlso: http://promisekit.org/sealing-your-own-promises/
     - SeeAlso: http://promisekit.org/wrapping-delegation/
     - SeeAlso: init(resolver:)
    */
    public convenience init(@noescape resolvers: (fulfill: (T) -> Void, reject: (ErrorType) -> Void) throws -> Void) {
        self.init(sealant: { resolve in
            var counter: Int32 = 0  // can’t use `pending` as we are still initializing
            try resolvers(fulfill: { resolve(.Fulfilled($0)) }, reject: { error in
                if OSAtomicIncrement32(&counter) == 1 {
                    resolve(.Rejected(error, ErrorConsumptionToken(error)))
                } else {
                    NSLog("PromiseKit: Warning: reject called on already rejected Promise: %@", "\(error)")
                }
            })
        })
    }

    /**
     Create a new pending promise.

     This initializer is convenient when wrapping asynchronous systems that
     use common patterns. For example:

         func fetchKitten() -> Promise<UIImage> {
             return Promise { resolve in
                 KittenFetcher.fetchWithCompletionBlock(resolve)
             }
         }

     - SeeAlso: init(resolvers:)
    */
    public convenience init(@noescape resolver: ((T?, NSError?) -> Void) throws -> Void) {
        self.init(sealant: { resolve in
            try resolver { obj, err in
                if let obj = obj {
                    resolve(.Fulfilled(obj))
                } else if let err = err {
                    resolve(.Rejected(err, ErrorConsumptionToken(err as ErrorType)))
                } else {
                    resolve(.Rejected(Error.DoubleOhSux0r, ErrorConsumptionToken(Error.DoubleOhSux0r)))
                }
            }
        })
    }

    /**
     Create a new pending promise.

     This initializer is convenient when wrapping asynchronous systems that
     use common patterns. For example:

         func fetchKitten() -> Promise<UIImage> {
             return Promise { resolve in
                 KittenFetcher.fetchWithCompletionBlock(resolve)
             }
         }

     - SeeAlso: init(resolvers:)
    */
    public convenience init(@noescape resolver: ((T, NSError?) -> Void) throws -> Void) {
        self.init(sealant: { resolve in
            try resolver { obj, err in
                if let err = err {
                    resolve(.Rejected(err, ErrorConsumptionToken(err as ErrorType)))
                } else {
                    resolve(.Fulfilled(obj))
                }
            }
        })
    }

    /**
     Create a new fulfilled promise.
    */
    public init(_ value: T) {
        state = SealedState(resolution: .Fulfilled(value))
    }

    /**
     Create a new rejected promise.
    */
    public init(_ error: ErrorType) {
        state = SealedState(resolution: .Rejected(error, ErrorConsumptionToken(error)))
    }

    init(@noescape sealant: ((Resolution<T>) -> Void) throws -> Void) {
        var resolve: ((Resolution<T>) -> Void)!
        state = UnsealedState(resolver: &resolve)
        do {
            try sealant(resolve)
        } catch {
            resolve(.Rejected(error, ErrorConsumptionToken(error)))
        }
    }

    /**
     Making promises that wrap asynchronous delegation systems or other larger asynchronous systems without a simple completion handler is easier with pendingPromise.

         class Foo: BarDelegate {
             let (promise, fulfill, reject) = Promise<Int>.pendingPromise()
    
             func barDidFinishWithResult(result: Int) {
                 fulfill(result)
             }
    
             func barDidError(error: NSError) {
                 reject(error)
             }
         }

     - Returns: A tuple consisting of: 
       1) A promise
       2) A function that fulfills that promise
       3) A function that rejects that promise
    */
    public class func pendingPromise() -> (promise: Promise, fulfill: (T) -> Void, reject: (ErrorType) -> Void) {
        var fulfill: ((T) -> Void)!
        var reject: ((ErrorType) -> Void)!
        let promise = Promise { fulfill = $0; reject = $1 }
        return (promise, fulfill, reject)
    }

    func pipe(body: (Resolution<T>) -> Void) {
        state.get { seal in
            switch seal {
            case .Pending(let handlers):
                handlers.append(body)
            case .Resolved(let resolution):
                body(resolution)
            }
        }
    }

    private convenience init<U>(when: Promise<U>, body: (Resolution<U>, (Resolution<T>) -> Void) -> Void) {
        self.init { resolve in
            when.pipe { resolution in
                body(resolution, resolve)
            }
        }
    }

    /**
     The provided closure is executed when this Promise is resolved.

     - Parameter on: The queue on which body should be executed.
     - Parameter body: The closure that is executed when this Promise is fulfilled.
     - Returns: A new promise that is resolved with the value returned from the provided closure. For example:

           NSURLConnection.GET(url).then { (data: NSData) -> Int in
               //…
               return data.length
           }.then { length in
               //…
           }

     - SeeAlso: `thenInBackground`
    */
    public func then<U>(on q: dispatch_queue_t = dispatch_get_main_queue(), _ body: (T) throws -> U) -> Promise<U> {
        return Promise<U>(when: self) { resolution, resolve in
            switch resolution {
            case .Rejected(let error):
                resolve(.Rejected(error))
            case .Fulfilled(let value):
                contain_zalgo(q, rejecter: resolve) {
                    resolve(.Fulfilled(try body(value)))
                }
            }
        }
    }

    /**
     The provided closure is executed when this Promise is resolved.

     - Parameter on: The queue on which body should be executed.
     - Parameter body: The closure that is executed when this Promise is fulfilled.
     - Returns: A new promise that is resolved when the Promise returned from the provided closure resolves. For example:

           NSURLSession.GET(url1).then { (data: NSData) -> Promise<NSData> in
               //…
               return NSURLSession.GET(url2)
           }.then { data in
               //…
           }

     - SeeAlso: `thenInBackground`
    */
    public func then<U>(on q: dispatch_queue_t = dispatch_get_main_queue(), _ body: (T) throws -> Promise<U>) -> Promise<U> {
        return Promise<U>(when: self) { resolution, resolve in
            switch resolution {
            case .Rejected(let error):
                resolve(.Rejected(error))
            case .Fulfilled(let value):
                contain_zalgo(q, rejecter: resolve) {
                    try body(value).pipe(resolve)
                }
            }
        }
    }

    /**
     The provided closure is executed when this Promise is resolved.

     - Parameter on: The queue on which body should be executed.
     - Parameter body: The closure that is executed when this Promise is fulfilled.
     - Returns: A new promise that is resolved when the AnyPromise returned from the provided closure resolves. For example:

           NSURLSession.GET(url).then { (data: NSData) -> AnyPromise in
               //…
               return SCNetworkReachability()
           }.then { _ in
               //…
           }

     - SeeAlso: `thenInBackground`
    */
    public func then(on q: dispatch_queue_t = dispatch_get_main_queue(), body: (T) throws -> AnyPromise) -> Promise<AnyObject?> {
        return Promise<AnyObject?>(when: self) { resolution, resolve in
            switch resolution {
            case .Rejected(let error):
                resolve(.Rejected(error))
            case .Fulfilled(let value):
                contain_zalgo(q, rejecter: resolve) {
                    let anypromise = try body(value)
                    anypromise.pipe { obj in
                        if let error = obj as? NSError {
                            resolve(.Rejected(error, ErrorConsumptionToken(error as ErrorType)))
                        } else {
                            // possibly the value of this promise is a PMKManifold, if so
                            // calling the objc `value` method will return the first item.
                            let obj: AnyObject? = anypromise.valueForKey("value")
                            resolve(.Fulfilled(obj))
                        }
                    }
                }
            }
        }
    }

    /**
     The provided closure is executed on the default background queue when this Promise is fulfilled.

     This method is provided as a convenience for `then`.

     - SeeAlso: `then`
    */
    public func thenInBackground<U>(body: (T) throws -> U) -> Promise<U> {
        return then(on: dispatch_get_global_queue(0, 0), body)
    }

    /**
     The provided closure is executed on the default background queue when this Promise is fulfilled.

     This method is provided as a convenience for `then`.

     - SeeAlso: `then`
    */
    public func thenInBackground<U>(body: (T) throws -> Promise<U>) -> Promise<U> {
        return then(on: dispatch_get_global_queue(0, 0), body)
    }

    /**
     The provided closure is executed when this promise is rejected.

     Rejecting a promise cascades: rejecting all subsequent promises (unless
     recover is invoked) thus you will typically place your catch at the end
     of a chain. Often utility promises will not have a catch, instead
     delegating the error handling to the caller.

     The provided closure always runs on the main queue.

     - Parameter policy: The default policy does not execute your handler for cancellation errors. See registerCancellationError for more documentation.
     - Parameter body: The handler to execute if this promise is rejected.
     - SeeAlso: `registerCancellationError`
    */
    public func report(policy policy: ErrorPolicy = .AllErrorsExceptCancellation, _ body: (ErrorType) -> Void) {
        
        func consume(error: ErrorType, _ token: ErrorConsumptionToken) {
            token.consumed = true
            body(error)
        }

        pipe { resolution in
            switch (resolution, policy) {
            case (let .Rejected(error as CancellableErrorType, token), .AllErrorsExceptCancellation):
                dispatch_async(dispatch_get_main_queue()) {
                    if !error.cancelled {     // cancelled must be called main
                        consume(error, token)
                    }
                }
            case (let .Rejected(error, token), _):
                dispatch_async(dispatch_get_main_queue()) {
                    consume(error, token)
                }
            case (.Fulfilled, _):
                break
            }
        }
    }

    /**
     The provided closure is executed when this promise is rejected giving you
     an opportunity to recover from the error and continue the promise chain.
    */
    public func recover(on q: dispatch_queue_t = dispatch_get_main_queue(), _ body: (ErrorType) -> Promise) -> Promise {
        return Promise(when: self) { resolution, resolve in
            switch resolution {
            case .Rejected(let error, let token):
                contain_zalgo(q) {
                    token.consumed = true
                    body(error).pipe(resolve)
                }
            case .Fulfilled:
                resolve(resolution)
            }
        }
    }

    public func recover(on q: dispatch_queue_t = dispatch_get_main_queue(), _ body: (ErrorType) throws -> T) -> Promise {
        return Promise(when: self) { resolution, resolve in
            switch resolution {
            case .Rejected(let error, let token):
                contain_zalgo(q, rejecter: resolve) {
                    token.consumed = true
                    resolve(.Fulfilled(try body(error)))
                }
            case .Fulfilled:
                resolve(resolution)
            }
        }
    }

    /**
     The provided closure is executed when this Promise is resolved.

         UIApplication.sharedApplication().networkActivityIndicatorVisible = true
         somePromise().then {
             //…
         }.ensure {
             UIApplication.sharedApplication().networkActivityIndicatorVisible = false
         }

     - Parameter on: The queue on which body should be executed.
     - Parameter body: The closure that is executed when this Promise is resolved.
    */
    public func ensure(on q: dispatch_queue_t = dispatch_get_main_queue(), _ body: () -> Void) -> Promise {
        return Promise(when: self) { resolution, resolve in
            contain_zalgo(q) {
                body()
                resolve(resolution)
            }
        }
    }

    @available(*, unavailable, renamed="ensure")
    public func finally(on: dispatch_queue_t = dispatch_get_main_queue(), body: () -> Void) -> Promise { return Promise { _, _ in } }

    @available(*, unavailable, renamed="report")
    public func catch_(policy policy: ErrorPolicy = .AllErrorsExceptCancellation, body: () -> Void) -> Promise { return Promise { _, _ in } }
}


/**
 Zalgo is dangerous.

 Pass as the `on` parameter for a `then`. Causes the handler to be executed
 as soon as it is resolved. That means it will be executed on the queue it
 is resolved. This means you cannot predict the queue.

 In the case that the promise is already resolved the handler will be
 executed immediately.

 zalgo is provided for libraries providing promises that have good tests
 that prove unleashing zalgo is safe. You can also use it in your
 application code in situations where performance is critical, but be
 careful: read the essay at the provided link to understand the risks.

 - SeeAlso: http://blog.izs.me/post/59142742143/designing-apis-for-asynchrony
*/
public let zalgo: dispatch_queue_t = dispatch_queue_create("Zalgo", nil)

/**
 Waldo is dangerous.

 Waldo is zalgo, unless the current queue is the main thread, in which case
 we dispatch to the default background queue.

 If your block is likely to take more than a few milliseconds to execute,
 then you should use waldo: 60fps means the main thread cannot hang longer
 than 17 milliseconds. Don’t contribute to UI lag.

 Conversely if your then block is trivial, use zalgo: GCD is not free and
 for whatever reason you may already be on the main thread so just do what
 you are doing quickly and pass on execution.

 It is considered good practice for asynchronous APIs to complete onto the
 main thread. Apple do not always honor this, nor do other developers.
 However, they *should*. In that respect waldo is a good choice if your
 then is going to take a while and doesn’t interact with the UI.

 Please note (again) that generally you should not use zalgo or waldo. The
 performance gains are neglible and we provide these functions only out of
 a misguided sense that library code should be as optimized as possible.
 If you use zalgo or waldo without tests proving their correctness you may
 unwillingly introduce horrendous, near-impossible-to-trace bugs.

 - SeeAlso: zalgo
*/
public let waldo: dispatch_queue_t = dispatch_queue_create("Waldo", nil)

func contain_zalgo(q: dispatch_queue_t, block: () -> Void) {
    if q === zalgo {
        block()
    } else if q === waldo {
        if NSThread.isMainThread() {
            dispatch_async(dispatch_get_global_queue(0, 0), block)
        } else {
            block()
        }
    } else {
        dispatch_async(q, block)
    }
}

func contain_zalgo<T>(q: dispatch_queue_t, rejecter resolve: (Resolution<T>) -> Void, block: () throws -> Void) {
    contain_zalgo(q) {
        do {
            try block()
        } catch {
            resolve(.Rejected(error, ErrorConsumptionToken(error)))
        }
    }
}


extension Promise {
    /**
     Void promises are less prone to generics-of-doom scenarios.
     - SeeAlso: when.swift contains enlightening examples of using `Promise<Void>` to simplify your code.
    */
    public func asVoid() -> Promise<Void> {
        return then(on: zalgo) { _ in return }
    }
}


extension Promise: CustomStringConvertible {
    public var description: String {
        return "Promise: \(state)"
    }
}

/**
 `firstly` can make chains more readable.

 Compare:

     NSURLConnection.GET(url1).then {
         NSURLConnection.GET(url2)
     }.then {
         NSURLConnection.GET(url3)
     }

 With:

     firstly {
         NSURLConnection.GET(url1)
     }.then {
         NSURLConnection.GET(url2)
     }.then {
         NSURLConnection.GET(url3)
     }
*/
public func firstly<T>(promise: () throws -> Promise<T>) -> Promise<T> {
    do {
        return try promise()
    } catch {
        return Promise(error)
    }
}


public enum ErrorPolicy {
    case AllErrors
    case AllErrorsExceptCancellation
}

/**
 Resolves with the first resolving promise from a set of promises.

 ```
 race(promise1, promise2, promise3).then { winner in
     //…
 }
 ```

 - Returns: A new promise that resolves when the first promise in the provided promises resolves.
 - Warning: If any of the provided promises reject, the returned promise is rejected.
*/
public func race<T>(promises: Promise<T>...) -> Promise<T> {
    return Promise(sealant: { resolve in
        for promise in promises {
            promise.pipe(resolve)
        }
    })
}
import Dispatch
import Foundation  // NSLog

enum Seal<R> {
    case Pending(Handlers<R>)
    case Resolved(R)
}

enum Resolution<T> {
    case Fulfilled(T)
    case Rejected(ErrorType, ErrorConsumptionToken)
}

// would be a protocol, but you can't have typed variables of “generic”
// protocols in Swift 2. That is, I couldn’t do var state: State<R> when
// it was a protocol. There is no work around.
class State<R> {
    func get() -> R? { fatalError("Abstract Base Class") }
    func get(body: (Seal<R>) -> Void) { fatalError("Abstract Base Class") }
}

class UnsealedState<R>: State<R> {
    private let barrier = dispatch_queue_create("org.promisekit.barrier", DISPATCH_QUEUE_CONCURRENT)
    private var seal: Seal<R>

    /**
     Quick return, but will not provide the handlers array because
     it could be modified while you are using it by another thread.
     If you need the handlers, use the second `get` variant.
    */
    override func get() -> R? {
        var result: R?
        dispatch_sync(barrier) {
            if case .Resolved(let resolution) = self.seal {
                result = resolution
            }
        }
        return result
    }

    override func get(body: (Seal<R>) -> Void) {
        var sealed = false
        dispatch_sync(barrier) {
            switch self.seal {
            case .Resolved:
                sealed = true
            case .Pending:
                sealed = false
            }
        }
        if !sealed {
            dispatch_barrier_sync(barrier) {
                switch (self.seal) {
                case .Pending:
                    body(self.seal)
                case .Resolved:
                    sealed = true  // welcome to race conditions
                }
            }
        }
        if sealed {
            body(seal)
        }
    }

    required init(inout resolver: ((R) -> Void)!) {
        seal = .Pending(Handlers<R>())
        super.init()
        resolver = { resolution in
            var handlers: Handlers<R>?
            dispatch_barrier_sync(self.barrier) {
                if case .Pending(let hh) = self.seal {
                    self.seal = .Resolved(resolution)
                    handlers = hh
                }
            }
            if let handlers = handlers {
                for handler in handlers {
                    handler(resolution)
                }
            }
        }
    }

    deinit {
        if case .Pending = seal {
            NSLog("PromiseKit: Pending Promise deallocated! This is usually a bug")
        }
    }
}

class SealedState<R>: State<R> {
    private let resolution: R
    
    init(resolution: R) {
        self.resolution = resolution
    }
    
    override func get() -> R? {
        return resolution
    }

    override func get(body: (Seal<R>) -> Void) {
        body(.Resolved(resolution))
    }
}


class Handlers<R>: SequenceType {
    var bodies: [(R)->Void] = []

    func append(body: (R)->Void) {
        bodies.append(body)
    }

    func generate() -> IndexingGenerator<[(R)->Void]> {
        return bodies.generate()
    }

    var count: Int {
        return bodies.count
    }
}


extension Resolution: CustomStringConvertible {
    var description: String {
        switch self {
        case .Fulfilled(let value):
            return "Fulfilled with value: \(value)"
        case .Rejected(let error):
            return "Rejected with error: \(error)"
        }
    }
}

extension UnsealedState: CustomStringConvertible {
    var description: String {
        var rv: String!
        get { seal in
            switch seal {
            case .Pending(let handlers):
                rv = "Pending with \(handlers.count) handlers"
            case .Resolved(let resolution):
                rv = "\(resolution)"
            }
        }
        return "UnsealedState: \(rv)"
    }
}

extension SealedState: CustomStringConvertible {
    var description: String {
        return "SealedState: \(resolution)"
    }
}
import Foundation.NSProgress

private func when<T>(promises: [Promise<T>]) -> Promise<Void> {
    guard promises.count > 0 else { return Promise() }

#if !PMKDisableProgress
    let progress = NSProgress(totalUnitCount: Int64(promises.count))
    progress.cancellable = false
    progress.pausable = false
#else
    var progress: (completedUnitCount: Int, totalUnitCount: Int) = (0, 0)
#endif
    var countdown = promises.count
    let barrier = dispatch_queue_create("org.promisekit.barrier.when", DISPATCH_QUEUE_CONCURRENT)

    let (rootPromise, fulfill, reject) = Promise<Void>.pendingPromise()

    for (index, promise) in promises.enumerate() {
        promise.pipe { resolution in
            dispatch_barrier_sync(barrier) {
                switch resolution {
                case .Rejected(let error, let token):
                    token.consumed = true  // all errors are consumed by the parent Error.When
                    if rootPromise.pending {
                        progress.completedUnitCount = progress.totalUnitCount
                        reject(Error.When(index, error))
                    }
                case .Fulfilled:
                    guard rootPromise.pending else { return }

                    progress.completedUnitCount++
                    if --countdown == 0 {
                        fulfill()
                    }
                }
            }
        }
    }

    return rootPromise
}

/**
 Wait for all promises in a set to resolve.

 For example:

     when(promise1, promise2).then { results in
         //…
     }.report { error in
         switch error {
         case Error.When(let index, NSURLError.NoConnection):
             //…
         case Error.When(let index, CLError.NotAuthorized):
             //…
         }
     }

 - Warning: If *any* of the provided promises reject, the returned promise is immediately rejected with that promise’s rejection. The error’s `userInfo` object is supplemented with `PMKFailingPromiseIndexKey`.
 - Warning: In the event of rejection the other promises will continue to resolve and, as per any other promise, will either fulfill or reject. This is the right pattern for `getter` style asynchronous tasks, but often for `setter` tasks (eg. storing data on a server), you most likely will need to wait on all tasks and then act based on which have succeeded and which have failed, in such situations use `join`.
 - Parameter promises: The promies upon which to wait before the returned promise resolves.
 - Returns: A new promise that resolves when all the provided promises fulfill or one of the provided promises rejects.
 - SeeAlso: `join()`
*/
public func when<T>(promises: [Promise<T>]) -> Promise<[T]> {
    return when(promises).then(on: zalgo) { promises.map{ $0.value! } }
}

public func when<T>(promises: Promise<T>...) -> Promise<[T]> {
    return when(promises)
}

public func when(promises: Promise<Void>...) -> Promise<Void> {
    return when(promises)
}

public func when<U, V>(pu: Promise<U>, _ pv: Promise<V>) -> Promise<(U, V)> {
    return when(pu.asVoid(), pv.asVoid()).then(on: zalgo) { (pu.value!, pv.value!) }
}

public func when<U, V, X>(pu: Promise<U>, _ pv: Promise<V>, _ px: Promise<X>) -> Promise<(U, V, X)> {
    return when(pu.asVoid(), pv.asVoid(), px.asVoid()).then(on: zalgo) { (pu.value!, pv.value!, px.value!) }
}
let PMKErrorDomain = "PMKErrorDomain"
let PMKFailingPromiseIndexKey = "PMKFailingPromiseIndexKey"
let PMKURLErrorFailingURLResponseKey = "PMKURLErrorFailingURLResponseKey"
let PMKURLErrorFailingDataKey = "PMKURLErrorFailingDataKey"
let PMKURLErrorFailingStringKey = "PMKURLErrorFailingStringKey"
let PMKJSONErrorJSONObjectKey = "PMKJSONErrorJSONObjectKey"
let PMKJoinPromisesKey = "PMKJoinPromisesKey"
let PMKUnexpectedError = 1
let PMKUnknownError = 2
let PMKInvalidUsageError = 3
let PMKAccessDeniedError = 4
let PMKOperationCancelled = 5
let PMKNotFoundError = 6
let PMKJSONError = 7
let PMKOperationFailed = 8
let PMKTaskError = 9
let PMKJoinError = 10
