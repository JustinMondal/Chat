//
// Recorder.swift (FIXED for voice recording)
// Replace Sources/ExyteChat/Views/Recording/Recorder.swift in your fork:
// https://github.com/JustinMondal/Chat
//
// Fixes: (1) AVEncoderBitRateKey must be bits/sec (128000 for AAC), not 128.
//        (2) Do not pass PCM-only keys when format is AAC — causes no audio.
//

import Foundation
@preconcurrency import AVFoundation

final actor Recorder {

    // duration and waveform samples
    typealias ProgressHandler = @Sendable (Double, [CGFloat]) -> Void

    private let audioSession = AVAudioSession()
    private var audioRecorder: AVAudioRecorder?
    private var audioTimer: Timer?

    private var soundSamples: [CGFloat] = []
    private var recorderSettings = RecorderSettings()

    var isAllowedToRecordAudio: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    var isRecording: Bool {
        audioRecorder?.isRecording ?? false
    }

    func setRecorderSettings(_ recorderSettings: RecorderSettings) {
        self.recorderSettings = recorderSettings
    }

    func startRecording(durationProgressHandler: @escaping ProgressHandler) async -> URL? {
        if !isAllowedToRecordAudio {
            let granted = await audioSession.requestRecordPermission()
            if granted {
                return startRecordingInternal(durationProgressHandler)
            }
            return nil
        } else {
            return startRecordingInternal(durationProgressHandler)
        }
    }

    private func startRecordingInternal(_ durationProgressHandler: @escaping ProgressHandler) -> URL? {
        let formatID = recorderSettings.audioFormatID

        // Only include format-appropriate keys. PCM keys are invalid for AAC and can cause no audio.
        var settings: [String: Any] = [
            AVFormatIDKey: Int(formatID),
            AVSampleRateKey: recorderSettings.sampleRate,
            AVNumberOfChannelsKey: recorderSettings.numberOfChannels,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        if formatID == kAudioFormatLinearPCM {
            settings[AVLinearPCMBitDepthKey] = recorderSettings.linearPCMBitDepth
            settings[AVLinearPCMIsFloatKey] = recorderSettings.linearPCMIsFloatKey
            settings[AVLinearPCMIsBigEndianKey] = recorderSettings.linearPCMIsBigEndianKey
            settings[AVLinearPCMIsNonInterleaved] = recorderSettings.linearPCMIsNonInterleaved
        } else {
            // AAC and other encoded formats: bit rate in bits per second (e.g. 128000), not 128.
            let bitRate = recorderSettings.encoderBitRateKey
            let bitsPerSecond = (bitRate <= 0 || bitRate > 1_000_000) ? 128_000 : (bitRate < 1000 ? bitRate * 1000 : bitRate)
            settings[AVEncoderBitRateKey] = bitsPerSecond
        }

        soundSamples = []
        guard let fileExt = fileExtension(for: formatID) else {
            return nil
        }
        let recordingUrl = FileManager.tempDirPath.appendingPathComponent(UUID().uuidString + fileExt)

        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
            audioRecorder = try AVAudioRecorder(url: recordingUrl, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            durationProgressHandler(0.0, [])

            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task {
                    await self?.onTimer(durationProgressHandler)
                }
            }
            audioTimer = timer
            Task { @MainActor in
                RunLoop.main.add(timer, forMode: .common)
            }

            return recordingUrl
        } catch {
            stopRecording()
            return nil
        }
    }

    func onTimer(_ durationProgressHandler: @escaping ProgressHandler) {
        audioRecorder?.updateMeters()
        if let power = audioRecorder?.averagePower(forChannel: 0) {
            // power from 0 db (max) to -60 db (roughly min)
            let adjustedPower = 1 - (max(power, -60) / 60 * -1)
            soundSamples.append(CGFloat(adjustedPower))
        }
        if let time = audioRecorder?.currentTime {
            durationProgressHandler(time, soundSamples)
        }
    }

    func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        audioTimer?.invalidate()
        audioTimer = nil
    }

    private func fileExtension(for formatID: AudioFormatID) -> String? {
        switch formatID {
        case kAudioFormatMPEG4AAC:
            return ".m4a"
        case kAudioFormatLinearPCM:
            return ".wav"
        case kAudioFormatMPEGLayer3:
            return ".mp3"
        case kAudioFormatAppleLossless:
            return ".m4a"
        case kAudioFormatOpus:
            return ".opus"
        case kAudioFormatAC3:
            return ".ac3"
        case kAudioFormatFLAC:
            return ".flac"
        case kAudioFormatAMR:
            return ".amr"
        case kAudioFormatMIDIStream:
            return ".midi"
        case kAudioFormatULaw:
            return ".ulaw"
        case kAudioFormatALaw:
            return ".alaw"
        case kAudioFormatAMR_WB:
            return ".awb"
        case kAudioFormatEnhancedAC3:
            return ".eac3"
        case kAudioFormatiLBC:
            return ".ilbc"
        default:
            return nil
        }
    }
}

public struct RecorderSettings: Codable, Hashable {
    var audioFormatID: AudioFormatID
    var sampleRate: CGFloat
    var numberOfChannels: Int
    /// For AAC: pass 128 for 128 kbps (stored as 128000 internally). For PCM, unused.
    var encoderBitRateKey: Int
    // pcm
    var linearPCMBitDepth: Int
    var linearPCMIsFloatKey: Bool
    var linearPCMIsBigEndianKey: Bool
    var linearPCMIsNonInterleaved: Bool

    public init(audioFormatID: AudioFormatID = kAudioFormatMPEG4AAC,
                sampleRate: CGFloat = 44100,
                numberOfChannels: Int = 1,
                encoderBitRateKey: Int = 128,
                linearPCMBitDepth: Int = 16,
                linearPCMIsFloatKey: Bool = false,
                linearPCMIsBigEndianKey: Bool = false,
                linearPCMIsNonInterleaved: Bool = false) {
        self.audioFormatID = audioFormatID
        self.sampleRate = sampleRate
        self.numberOfChannels = numberOfChannels
        self.encoderBitRateKey = encoderBitRateKey
        self.linearPCMBitDepth = linearPCMBitDepth
        self.linearPCMIsFloatKey = linearPCMIsFloatKey
        self.linearPCMIsBigEndianKey = linearPCMIsBigEndianKey
        self.linearPCMIsNonInterleaved = linearPCMIsNonInterleaved
    }
}

extension AVAudioSession {
    func requestRecordPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
