import Foundation
import AVFoundation
import MediaPlayer

/// 系统语音朗读的封装。
///
/// 三条约束来自产品前提：
/// 1. 只允许本地系统语音，不联网、不上传正文——所以只用 AVSpeechSynthesizer。
/// 2. 要能锁屏继续播，因此必须配好 audio session 与后台音频模式。
/// 3. 念完一句要能通知外面接着念下一句，所以对外只暴露"一句念完了"这个回调。
final class SpeechEngine: NSObject, ObservableObject {
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false

    /// 一句念完（正常结束，不含被打断）
    var onFinishUtterance: (() -> Void)?
    var onRemotePlay: (() -> Void)?
    var onRemotePause: (() -> Void)?
    var onRemoteNext: (() -> Void)?
    var onRemotePrevious: (() -> Void)?

    private let synthesizer = AVSpeechSynthesizer()

    /// 存储键。语速与音色是"这个人耳朵的习惯"，必须跨启动记住。
    private enum Key {
        static let rate = "speech.rate"
        static let voice = "speech.voiceIdentifier"
    }

    /// 语速，0.4–0.7 之间比较适合中文。默认比系统默认稍慢一点。
    /// didSet 直接落盘，滑块每动一格都记住。
    @Published var rate: Float = SpeechEngine.storedRate() {
        didSet { UserDefaults.standard.set(rate, forKey: Key.rate) }
    }

    @Published var voiceIdentifier: String? = UserDefaults.standard.string(forKey: Key.voice) {
        didSet { UserDefaults.standard.set(voiceIdentifier, forKey: Key.voice) }
    }

    /// 当前是否处于"用户希望它读"的状态。
    ///
    /// 这不是 `isSpeaking`：`stopSpeaking` 之后的 `didFinish` 回调可能已经排在主队列上，
    /// 只靠 `isSpeaking` 判断，回调仍会去拿下一章然后重新开口——"退出到书架还在读"就是这么来的。
    private var isPlaybackRequested = false

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
        configureRemoteCommands()
    }

    private static func storedRate() -> Float {
        let fallback = AVSpeechUtteranceDefaultSpeechRate * 0.94
        let stored = UserDefaults.standard.float(forKey: Key.rate)
        guard stored > 0 else { return fallback }
        return min(max(stored, 0.3), 0.75)
    }

    // MARK: 播放控制

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isPlaybackRequested = true

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        activateAudioSession()

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.rate = rate
        utterance.pitchMultiplier = 1.0
        utterance.postUtteranceDelay = 0.04
        if let identifier = voiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            utterance.voice = voice
        } else {
            utterance.voice = Self.defaultChineseVoice()
        }

        synthesizer.speak(utterance)
        isSpeaking = true
        isPaused = false
        updateNowPlaying()
    }

    func pause() {
        guard synthesizer.isSpeaking, !synthesizer.isPaused else { return }
        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
        updateNowPlaying()
    }

    func resume() {
        guard synthesizer.isPaused else { return }
        synthesizer.continueSpeaking()
        isPaused = false
        updateNowPlaying()
    }

    func stop() {
        // 先关掉"应该继续读"的开关，再停声音。顺序反了的话，
        // 排队中的 didFinish 会看到开关还开着，接着去念下一章。
        isPlaybackRequested = false
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: 音色

    static func chineseVoices() -> [AVSpeechSynthesisVoice] {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("zh") }
        // 质量高的排前面：premium > enhanced > default
        return voices.sorted { lhs, rhs in
            if lhs.quality.rawValue != rhs.quality.rawValue {
                return lhs.quality.rawValue > rhs.quality.rawValue
            }
            return lhs.name < rhs.name
        }
    }

    static func defaultChineseVoice() -> AVSpeechSynthesisVoice? {
        let voices = chineseVoices()
        return voices.first { $0.language == "zh-CN" } ?? voices.first
    }

    // MARK: 音频会话与锁屏

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    }

    private func activateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// 锁屏与控制中心上的信息。没有它，锁屏只显示"正在播放"和一个空白卡片。
    private func updateNowPlaying() {
        guard isSpeaking else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: nowPlayingTitle,
            MPMediaItemPropertyArtist: nowPlayingSubtitle,
            MPNowPlayingInfoPropertyPlaybackRate: isPaused ? 0.0 : 1.0,
            MPNowPlayingInfoPropertyIsLiveStream: true
        ]
        if let artwork = nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private var nowPlayingTitle: String = "私阅读"
    private var nowPlayingSubtitle: String = "朗读中"
    var nowPlayingArtwork: MPMediaItemArtwork?

    func updateMetadata(title: String, subtitle: String) {
        nowPlayingTitle = title
        nowPlayingSubtitle = subtitle
        updateNowPlaying()
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true

        center.playCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.onRemotePlay?() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.onRemotePause?() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.isPaused { self.onRemotePlay?() } else { self.onRemotePause?() }
            }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.onRemoteNext?() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.onRemotePrevious?() }
            return .success
        }
    }
}

extension SpeechEngine: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = true
            self.isPaused = false
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            // 已经 stop 过就不要再接下一句。退出阅读器时最怕这个：
            // 用户已经回到书架，声音却从下一章重新冒出来。
            guard self.isPlaybackRequested else { return }
            self.onFinishUtterance?()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.isPaused = false
        }
    }
}
