import Social
#if !COCOAPODS
#endif

/**
 To import the `SLRequest` category:

    use_frameworks!
    pod "PromiseKit/Social"

 And then in your sources:

*/
extension SLRequest {
    public func promise() -> URLDataPromise {
        return URLDataPromise.go(preparedURLRequest()) { completionHandler in
            performRequestWithHandler(completionHandler)
        }
    }
}
