import Foundation
import NitroModules
import AVFoundation
import Speech
import os.log

func log(_ message: String, _ extra: String = "") {
  Logger(
    subsystem: "com.margelo.nitro", 
    category: "HybridRecognizer"
  ).info(
    "[HybridRecognizer] \(extra) \(message)"
  )
}

@available(iOS 26.0, *)
class HybridRecognizer26: HybridRecognizerSpec {
    var onResult: ((String) -> Void)?
    private var audioEngine: AVAudioEngine?
    
    private var inputSequence: AsyncStream<AnalyzerInput>?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var outputContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var analyzer: SpeechAnalyzer?
    private var transcriber: DictationTranscriber?
    var hardwareFormat: AVAudioFormat?
    
    private var lastBatchStartTime: Float64? = nil
    private var resultBatches: [String] = []

    private var audioProducerTask: Task<Void, Never>?
    private var recognizerTask: Task<(), Error>?

    func start() {
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
          if authStatus == .authorized {
              self?.requestMicrophonePermission()
          }
        }
    }

    private func requestMicrophonePermission() {
      AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
          Task { @MainActor in
              if granted {
                  await self?.startRecognition()
              }
          }
      }
    }

    private func startRecognition() async {
    do {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
      try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      self.clean()
      return
    }
        
    transcriber = DictationTranscriber(
        locale: Locale(identifier: "ru_RU"),
        contentHints: [.shortForm, .farField],
        transcriptionOptions: [.punctuation],
        reportingOptions: [.frequentFinalization, .volatileResults],
        attributeOptions: [.audioTimeRange]
    )
        
    guard let transcriber else { return }

    (inputSequence, inputBuilder) = AsyncStream.makeStream(of: AnalyzerInput.self)
    
    let modules = [transcriber]

    // 4. Analyzer
    guard let audioFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
        compatibleWith: modules
    ) else {
        self.clean()
        return
    }
    
    analyzer = SpeechAnalyzer(modules: modules)
    
    // 5. Supply audio
    audioProducerTask = Task {
        audioEngine = AVAudioEngine()
        hardwareFormat = audioEngine?.inputNode.outputFormat(forBus: 0)
        guard let audioEngine, let hardwareFormat else { return }
        audioEngine.inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: hardwareFormat
        ) { [weak self] buffer, _ in
            self?.outputContinuation?.yield(buffer)
        }
        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            self.clean()
            return
        }
        let stream = AsyncStream(
            AVAudioPCMBuffer.self,
            bufferingPolicy: .unbounded
        ) { continuation in
            outputContinuation = continuation
        }
        
        let needsConversion =
            hardwareFormat.commonFormat != audioFormat.commonFormat ||
            hardwareFormat.sampleRate != audioFormat.sampleRate ||
            hardwareFormat.channelCount != audioFormat.channelCount
        do {
            guard let converter = AVAudioConverter(
                from: hardwareFormat,
                to: audioFormat
            ) else {
                throw NSError()
            }
            for await pcmBuffer in stream {
                if Task.isCancelled { break }
                
                let bufferForAnalyzer: AVAudioPCMBuffer
                if needsConversion {
                    // Skip analyzing for empty buffers and
                    // Throw error if buffers are inconvertable
                    guard let convertedBuffer = try AudioBufferConverter.convertBuffer(
                        converter: converter,
                        audioFormat: audioFormat,
                        pcmBuffer: pcmBuffer
                    ) else {
                        continue
                    }
                    bufferForAnalyzer = convertedBuffer
                } else {
                    bufferForAnalyzer = pcmBuffer
                }
                
                let input = AnalyzerInput(buffer: bufferForAnalyzer)
                inputBuilder?.yield(input)
            }
        } catch {
            if Task.isCancelled {
                return
            }
            self.clean()
            return
        }
    }
    
    // 7. Handle the results
    recognizerTask = Task {
        do {
            for try await result in transcriber.results {
                self.handleBatch(
                    attrString: result.text,
                    rangeStart: result.range.start,
                    isFinal: result.isFinal
                )
            }
        } catch {
            if error is CancellationError {
                return
            }
            self.clean()
        }
    }
    
    do {
        if let inputSequence, let analyzer {
            try await analyzer.start(inputSequence: inputSequence)
        }
    } catch {
        self.clean()
        return
    }
    self.onResult?("")
    }

    func stop() {
        inputBuilder?.finish()
        Task { [weak self] in
            guard let self = self else { return }
            
            do {
                try await self.analyzer?.finalizeAndFinishThroughEndOfInput()
            } catch {
                await self.analyzer?.cancelAndFinishNow()
            }
            self.clean()
        }
    }

    private func clean() {
        if let audioEngine, audioEngine.isRunning {
          audioEngine.stop()
        }
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        inputSequence = nil
        inputBuilder = nil
        outputContinuation?.finish()
        outputContinuation = nil
        analyzer = nil
        transcriber = nil
        audioProducerTask?.cancel()
        audioProducerTask = nil
        recognizerTask?.cancel()
        recognizerTask = nil
        lastBatchStartTime = nil
        resultBatches = []
        do {
          try AVAudioSession.sharedInstance().setActive(false)
        } catch { return }
    }
    
    private func handleBatch(attrString: AttributedString, rangeStart: CMTime, isFinal: Bool) {
        var newBatch = String(attrString.characters)
        // Ignore all batches without A-z0-9
        if !newBatch.contains(/\w+/) {
            return
        }
        
        log("[1] lastBatch: \(self.resultBatches.last ?? "") | newBatch: \(newBatch)")
        if self.resultBatches.isEmpty {
            self.resultBatches.append(newBatch)
        } else if CMTimeGetSeconds(rangeStart) == self.lastBatchStartTime || isFinal {
            log("[2] replace, isFinal: \(isFinal)")
            self.resultBatches[self.resultBatches.count - 1] = newBatch
        } else {
            log("[2] add new batch")
            self.resultBatches.append(newBatch)
        }
        self.lastBatchStartTime = CMTimeGetSeconds(rangeStart)
        let tn = Thread.isMainThread ? "main" : "bg"
        log(self.resultBatches.joined(separator: ";"))
        log("\(self.onResult)", "[thread -> \(tn)]")
        self.onResult?(self.resultBatches.joined(separator: ";"))
    }
}

private final class SendablePCMBufferBox: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    
    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

enum AudioBufferConverter {
    static func convertBuffer(
        converter: AVAudioConverter,
        audioFormat: AVAudioFormat,
        pcmBuffer: AVAudioPCMBuffer
    ) throws -> AVAudioPCMBuffer? {
        let resampledCapacity = AVAudioFrameCount(
            (Double(pcmBuffer.frameLength) * (audioFormat.sampleRate / pcmBuffer.format.sampleRate)).rounded(.up)
        )
        let convertedCapacity = max(pcmBuffer.frameLength, max(1, resampledCapacity))
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: convertedCapacity) else {
            throw NSError()
        }
        
        let inputBufferBox = SendablePCMBufferBox(pcmBuffer)
        var didProvideInput = false
        var conversionError: NSError?
        let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            outStatus.pointee = .haveData
            return inputBufferBox.buffer
        }
        if let conversionError {
            throw conversionError
        }
        guard status == .haveData || status == .inputRanDry else {
            return nil
        }
        guard convertedBuffer.frameLength > 0 else {
            return nil
        }
        return convertedBuffer
    }
}

