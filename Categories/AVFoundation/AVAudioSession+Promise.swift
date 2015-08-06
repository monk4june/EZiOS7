import AVFoundation.AVAudioSession
import Foundation
#if !COCOAPODS
#endif

/**
 To import the `AVAudioSession` category:

    use_frameworks!
    pod "PromiseKit/AVFoundation"

 And then in your sources:

*/
extension AVAudioSession {
    public func requestRecordPermission() -> Promise<Bool> {
        return Promise { fulfill, _ in
            requestRecordPermission(fulfill)
        }.then(on: zalgo) { $0.boolValue }
    }
}
