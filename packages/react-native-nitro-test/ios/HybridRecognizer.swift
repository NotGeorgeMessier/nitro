import Foundation
import NitroModules
import AVFoundation
import Speech
import os.log

class HybridRecognizer: HybridRecognizerSpec {
    var onResult: ((String) -> Void)?
    var rec: HybridRecognizerSpec?
    
    override init() {
        if #available(iOS 26.0, *) {
            self.rec = HybridRecognizer26()
        }
        super.init()
    }

    func start() {
        self.rec?.onResult = { data in
            self.onResult?(data)
        }
        do {
            try self.rec?.start()
        } catch {
            return
        }
    }


    func stop() {
        do {
            try self.rec?.stop()
        } catch {
            return
        }
    }
}
