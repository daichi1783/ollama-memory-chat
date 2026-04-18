// VoiceInputService.swift
// Memoria for iPhone - On-device Speech Recognition Service
// Phase 4: Voice Input using Apple's SFSpeechRecognizer

import Foundation
import Speech
import AVFoundation
import Combine

// MARK: - Voice Input State

enum VoiceInputState: Equatable {
    case idle
    case requesting     // Requesting permissions
    case listening      // Actively recording
    case processing     // Processing final result
    case error(String)

    static func == (lhs: VoiceInputState, rhs: VoiceInputState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.requesting, .requesting),
             (.listening, .listening), (.processing, .processing):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - VoiceInputService

@MainActor
class VoiceInputService: ObservableObject {
    static let shared = VoiceInputService()

    @Published var state: VoiceInputState = .idle
    @Published var transcribedText: String = ""
    @Published var isAvailable: Bool = false

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // Support Japanese, English, Spanish (matching LocalizationService)
    private var currentLocale: Locale = Locale(identifier: "ja-JP")

    private init() {
        setupRecognizer()
    }

    // MARK: - Setup

    private func setupRecognizer() {
        speechRecognizer = SFSpeechRecognizer(locale: currentLocale)
        isAvailable = speechRecognizer?.isAvailable ?? false

        // Observe availability changes
        speechRecognizer?.delegate = nil // We check on demand instead
    }

    // MARK: - Language

    func setLanguage(_ locale: Locale) {
        let supported = ["ja-JP", "en-US", "es-ES"]
        let identifier = locale.identifier
        guard supported.contains(identifier) else { return }

        // Stop any active session first
        if state == .listening {
            stopListening()
        }

        currentLocale = locale
        setupRecognizer()
    }

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        state = .requesting

        // Request speech recognition authorization
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            state = .error(permissionErrorMessage(for: speechStatus))
            return false
        }

        // Request microphone permission
        let micGranted: Bool
        if #available(iOS 17.0, *) {
            micGranted = await AVAudioApplication.requestRecordPermission()
        } else {
            micGranted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }

        guard micGranted else {
            state = .error("マイクへのアクセスが拒否されました。設定アプリから許可してください。")
            return false
        }

        state = .idle
        isAvailable = true
        return true
    }

    private func permissionErrorMessage(for status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .denied:
            return "音声認識へのアクセスが拒否されました。設定アプリから許可してください。"
        case .restricted:
            return "このデバイスでは音声認識が制限されています。"
        case .notDetermined:
            return "音声認識の権限がまだ確認されていません。"
        default:
            return "音声認識を利用できません。"
        }
    }

    // MARK: - Check Permission Status

    private var hasPermissions: Bool {
        let speechAuth = SFSpeechRecognizer.authorizationStatus()
        let micAuth = AVAudioApplication.shared.recordPermission
        return speechAuth == .authorized && micAuth == .granted
    }

    // MARK: - Start Listening

    func startListening() async {
        // アプリの現在言語に合わせて音声認識ロケールを自動同期
        let appLanguage = LocalizationService.shared.currentLanguage
        let localeForAppLang: Locale
        switch appLanguage {
        case .english:  localeForAppLang = Locale(identifier: "en-US")
        case .spanish:  localeForAppLang = Locale(identifier: "es-ES")
        case .japanese: localeForAppLang = Locale(identifier: "ja-JP")
        }
        if currentLocale.identifier != localeForAppLang.identifier {
            currentLocale = localeForAppLang
            setupRecognizer()
        }

        // Check permissions first
        if !hasPermissions {
            let granted = await requestPermissions()
            if !granted { return }
        }

        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            state = .error("音声認識が利用できません。")
            return
        }

        // Cancel any existing task
        stopRecognitionTask()

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            state = .error("オーディオセッションの設定に失敗しました: \(error.localizedDescription)")
            return
        }

        // Create recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // requiresOnDeviceRecognition は端末が対応している場合のみ有効化
        // 非対応端末で true にすると認識タスク生成時にクラッシュする
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        // For iOS 16+, we can add task hints
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }

        recognitionRequest = request
        transcribedText = ""
        state = .listening

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if let result = result {
                    self.transcribedText = result.bestTranscription.formattedString

                    if result.isFinal {
                        self.state = .idle
                        self.cleanupAudioEngine()
                    }
                }

                if let error = error {
                    // Don't overwrite if we already stopped intentionally
                    if self.state == .listening {
                        let nsError = error as NSError
                        // Error code 1110 = no speech detected, not a real error
                        if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                            self.state = .idle
                        } else {
                            self.state = .error("認識エラー: \(error.localizedDescription)")
                        }
                    }
                    self.cleanupAudioEngine()
                }
            }
        }

        // Install audio tap
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        // Start audio engine
        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            state = .error("録音の開始に失敗しました: \(error.localizedDescription)")
            cleanupAudioEngine()
        }
    }

    // MARK: - Stop Listening

    func stopListening() {
        guard state == .listening else { return }

        state = .processing

        // End the recognition request (triggers final result)
        recognitionRequest?.endAudio()
        cleanupAudioEngine()

        // After a short delay, if still processing, go back to idle
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            if state == .processing {
                state = .idle
            }
        }
    }

    // MARK: - Toggle

    func toggleListening() async {
        switch state {
        case .listening:
            stopListening()
        case .idle, .error:
            await startListening()
        default:
            break
        }
    }

    // MARK: - Cleanup

    private func stopRecognitionTask() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }

    private func cleanupAudioEngine() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        // エンジン停止済みでもタップが残っている場合があるため常に removeTap を呼ぶ
        // removeTap はタップが存在しない場合は no-op なので安全
        audioEngine.inputNode.removeTap(onBus: 0)
        stopRecognitionTask()
    }

    // Called when service is no longer needed
    func cleanup() {
        cleanupAudioEngine()
        state = .idle
        transcribedText = ""

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }
}
