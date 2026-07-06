import AVFoundation
import CoreKit
import Foundation
import SwiftWhisper

/// Запись с микрофона (16 кГц моно) + транскрипция через whisper.cpp.
public final class SpeechService: NSObject, Transcribing, @unchecked Sendable {
    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var samples: [Float] = []
    private var continuation: AsyncStream<TranscriptionEvent>.Continuation?
    private var modelURL: URL?
    private var language: AppLanguage = .en
    private var whisper: Whisper?
    private var cachedWhisper: Whisper?
    private var cachedKey: String?
    private var partialTask: Task<Void, Never>?
    private var transcribing = false
    /// Поколение таймера выгрузки кэша: новая запись/новый таймер инвалидирует ранее запланированную выгрузку.
    private var cacheIdleGen = 0

    override public init() { super.init() }

    public func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                cont.resume(returning: true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { granted in cont.resume(returning: granted) }
            default:
                cont.resume(returning: false)
            }
        }
    }

    public func start(modelURL: URL, language: AppLanguage) -> AsyncStream<TranscriptionEvent> {
        AsyncStream { continuation in
            lock.lock()
            self.continuation = continuation
            self.modelURL = modelURL
            self.language = language
            self.samples = []
            self.cacheIdleGen += 1
            lock.unlock()
            continuation.yield(.phase(.listening))
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                do {
                    try self.startEngine()
                    let w = self.loadWhisper(modelURL: modelURL, language: language)
                    self.lock.lock(); self.whisper = w; self.lock.unlock()
                    self.startPartialLoop()
                } catch {
                    continuation.yield(.failed("microphone"))
                    continuation.finish()
                }
            }
        }
    }

    /// Загрузить whisper-модель с кэшем по (modelURL, language): первая запись грузит (~сотни МБ),
    /// повторные переиспользуют инстанс. Lock НЕ держим во время самой загрузки (она долгая).
    private func loadWhisper(modelURL: URL, language: AppLanguage) -> Whisper {
        let key = modelURL.path + "|" + language.rawValue
        lock.lock(); let cached = cachedWhisper; let ck = cachedKey; lock.unlock()
        if let cached, ck == key { return cached }
        let w = Whisper(fromFileURL: modelURL)
        w.params.language = whisperLanguage(language)
        lock.lock(); cachedWhisper = w; cachedKey = key; lock.unlock()
        return w
    }

    /// Выгрузка whisper-кэша по простою: модель (142 МБ base … 1.5 ГБ large) не живёт в памяти
    /// между сессиями записи. Грейс 60 с — серия записей подряд по-прежнему без перезагрузки (Ит.52).
    private func scheduleCacheUnload() {
        lock.lock(); cacheIdleGen += 1; let gen = cacheIdleGen; lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 60) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            if self.cacheIdleGen == gen, self.whisper == nil {
                self.cachedWhisper = nil
                self.cachedKey = nil
            }
            self.lock.unlock()
        }
    }

    /// Живое (частичное) распознавание: каждые ~2.5с прогоняем накопленный буфер.
    private func startPartialLoop() {
        partialTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if Task.isCancelled { break }
                await self?.runPartial()
            }
        }
    }

    private func runPartial() async {
        lock.lock()
        let snapshot = samples
        let w = whisper
        let cont = continuation
        let busy = transcribing
        guard !busy, snapshot.count >= 16000, let w, let cont else { lock.unlock(); return }
        transcribing = true
        lock.unlock()
        if let segs = try? await w.transcribe(audioFrames: snapshot) {
            let text = segs.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { cont.yield(.partial(text)) }
        }
        lock.lock(); transcribing = false; lock.unlock()
    }

    public func stop() async {
        partialTask?.cancel()
        partialTask = nil
        lock.lock()
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        let captured = samples
        let cont = continuation
        let w = whisper
        lock.unlock()

        guard let cont else { return }
        cont.yield(.phase(.transcribing))
        var waited = 0
        while true {
            lock.lock(); let busy = transcribing; lock.unlock()
            if !busy || waited > 200 { break }
            try? await Task.sleep(nanoseconds: 25_000_000); waited += 1
        }
        guard let w, captured.count > 1600 else {
            cont.yield(.finished(""))
            cont.finish()
            lock.lock(); whisper = nil; lock.unlock()
            scheduleCacheUnload()
            return
        }
        do {
            let segments = try await w.transcribe(audioFrames: captured)
            let text = segments.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
            cont.yield(.finished(text))
        } catch {
            cont.yield(.failed("transcribe"))
        }
        cont.finish()
        lock.lock(); whisper = nil; lock.unlock()
        scheduleCacheUnload()
    }

    // MARK: - Запись

    private func startEngine() throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw NSError(domain: "Sage.Speech", code: 1)
        }
        input.installTap(onBus: 0, bufferSize: 2048, format: inFormat) { [weak self] buffer, _ in
            self?.process(buffer, converter: converter, outFormat: outFormat)
        }
        engine.prepare()
        try engine.start()
        lock.lock(); self.engine = engine; lock.unlock()
    }

    private func process(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, outFormat: AVAudioFormat) {
        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = out.floatChannelData else { return }
        let count = Int(out.frameLength)
        guard count > 0 else { return }
        let frames = Array(UnsafeBufferPointer(start: channel[0], count: count))
        lock.lock()
        samples.append(contentsOf: frames)
        let cont = continuation
        lock.unlock()
        let rms = sqrt(frames.reduce(Float(0)) { $0 + $1 * $1 } / Float(count))
        cont?.yield(.level(min(1, rms * 8)))
    }

    private func whisperLanguage(_ language: AppLanguage) -> WhisperLanguage {
        switch language {
        case .ru: .russian
        case .en: .english
        case .zh: .chinese
        }
    }
}
