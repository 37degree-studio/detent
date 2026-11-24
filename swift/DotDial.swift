// DotDial.swift — Detent
// A touch wheel with a ring of dots and a dot-matrix readout, drawn the way Nothing draws: flat, monochrome, one
// red dot for the current position, dot-matrix type only for the number. There are no moving parts: you slide a
// finger around the ring, and each step makes the tiny electronic tick of a touch wheel's clicker. Dots switch
// instantly. iOS / iPadOS 17+. The readout uses a monospaced system font; pass readoutFont for a dot-matrix face.
//
// Usage:
//   @State private var level = 72.0
//   DotDial(value: $level, label: "Level")
//   DotDial(value: $level, size: 200, head: .orange, tone: .light)

import SwiftUI
import UIKit
import AVFoundation

public struct DotDial: View {
    public enum Tone { case auto, light, dark }

    @Binding private var value: Double          // 0...100
    private let label: String
    private let size: CGFloat
    private let head: Color
    private let tone: Tone
    private let sound: Bool
    private let readoutFont: Font?

    public init(value: Binding<Double>,
                label: String = "Level",
                size: CGFloat = 240,
                head: Color = Color(red: 0.9, green: 0.14, blue: 0.16),
                tone: Tone = .auto,
                sound: Bool = true,
                readoutFont: Font? = nil) {
        _value = value
        self.label = label
        self.size = size
        self.head = head
        self.tone = tone
        self.sound = sound
        self.readoutFont = readoutFont
    }

    @State private var lastAngle: Double?
    @State private var atEdge = 0
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    private let count = 40
    private var dark: Bool { tone == .dark || (tone == .auto && scheme == .dark) }
    private var lit: Int { Int((value / 100 * Double(count - 1)).rounded()) }

    public var body: some View {
        ZStack {
            Circle()
                .fill(dark ? Color(white: 0.043) : Color(red: 0.925, green: 0.922, blue: 0.902))
                .overlay(Circle().strokeBorder(dark ? Color.white.opacity(0.07) : Color.black.opacity(0.08), lineWidth: 1))
            ring
            VStack(spacing: 8) {
                readout
                Text(label)
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(1.8)
                    .textCase(.uppercase)
                    .foregroundStyle(Color(white: dark ? 0.49 : 0.54))
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(turnGesture)
        .focusable()
        .focused($focused)
        .onKeyPress(keys: [.upArrow, .rightArrow, .downArrow, .leftArrow]) { press in
            set(value + (press.key == .upArrow || press.key == .rightArrow ? 1 : -1))
            return .handled
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value.rounded()))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(value + 5)
            case .decrement: set(value - 5)
            @unknown default: break
            }
        }
    }

    // Dots switch instantly: no fades, so no animation here.
    private var ring: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let on = i < lit, isHead = i == lit
                Circle()
                    .fill(isHead ? head : on ? (dark ? Color(white: 0.95) : Color(white: 0.106)) : (dark ? Color(white: 0.15) : Color(red: 0.84, green: 0.835, blue: 0.81)))
                    .frame(width: size * 0.036, height: size * 0.036)
                    .offset(y: -size * 0.41)
                    .rotationEffect(.degrees(-150 + Double(i) * 300 / Double(count - 1)))
            }
        }
        .transaction { $0.animation = nil }
    }

    // Unused leading digits stay as unlit segments.
    private var readout: some View {
        let digits = String(format: "%03d", Int(value.rounded()))
        let leading = digits.prefix { $0 == "0" }.count
        let lead = String(digits.prefix(min(leading, 2)))
        let rest = String(digits.dropFirst(min(leading, 2)))
        let litColor = dark ? Color(white: 0.95) : Color(white: 0.106)
        let unlit = dark ? Color(white: 0.18) : Color(red: 0.85, green: 0.847, blue: 0.82)
        return (Text(lead).foregroundStyle(unlit) + Text(rest).foregroundStyle(litColor))
            .font(readoutFont ?? .system(size: size * 0.2, weight: .heavy, design: .monospaced))
            .contentTransition(.identity)
    }

    // A touch wheel follows the finger exactly: no give, no detents to push past, no momentum.
    private var turnGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let dx = g.location.x - size / 2, dy = g.location.y - size / 2
                guard hypot(dx, dy) > 8 else { return }
                let a = atan2(dy, dx) * 180 / .pi
                if lastAngle == nil { Feedback.shared.prepare() }
                if let last = lastAngle {
                    var d = a - last
                    if d > 180 { d -= 360 } else if d < -180 { d += 360 }
                    set(value + d / 3)
                }
                lastAngle = a
            }
            .onEnded { _ in lastAngle = nil }
    }

    private func set(_ v: Double) {
        let next = min(100, max(0, v))
        guard next != value else { return }
        let before = lit
        value = next
        // The clicker ticks once per dot. The ends are virtual: one dull tick, then nothing.
        if lit != before && next > 0 && next < 100 { Feedback.shared.tick(sound: sound) }
        let edge = next <= 0 ? -1 : next >= 100 ? 1 : 0
        if edge != 0 && atEdge != edge { Feedback.shared.stop(sound: sound) }
        if edge != 0 { atEdge = edge } else if (atEdge < 0 && next > 3) || (atEdge > 0 && next < 97) { atEdge = 0 }
    }
}

/// A light, crisp tap per dot, like a touch wheel's clicker, and a firmer one at the ends.
@MainActor private final class Feedback {
    static let shared = Feedback()
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let synth = ClickSynth()

    func prepare() { rigid.prepare() }
    func tick(sound: Bool) {
        rigid.impactOccurred(intensity: 0.4)
        rigid.prepare()
        if sound { synth.play(.tick) }
    }
    func stop(sound: Bool) {
        rigid.impactOccurred(intensity: 0.6)
        if sound { synth.play(.stop) }
    }
}

/// A clicker's tick: a tiny part ringing for a millisecond or two at a few high body modes.
private final class ClickSynth {
    enum Voice: CaseIterable { case tick, stop }
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffers: [Voice: AVAudioPCMBuffer] = [:]
    private var ready = false

    init() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        for voice in Voice.allCases { buffers[voice] = Self.render(voice, format: format) }
        // Ambient: respects the silent switch and mixes with the user's music.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        ready = (try? engine.start()) != nil
    }

    func play(_ voice: Voice) {
        guard ready, let buffer = buffers[voice] else { return }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    private static let modes: [(Float, Float, Float)] = [(1900, 0.0024, 1), (3400, 0.0015, 0.55), (6100, 0.0008, 0.3)]

    private static func render(_ voice: Voice, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let (level, tune): (Float, Float) = voice == .tick ? (0.05, 1.55) : (0.09, 0.85)
        let rate = Float(format.sampleRate)
        let frames = AVAudioFrameCount(rate * 0.02)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let out = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            let t = Float(i) / rate
            var tick: Float = 0
            for (hz, decay, gain) in modes { tick += gain * sinf(2 * .pi * hz * tune * t) * expf(-t / decay) }
            tick += Float.random(in: -1...1) * 0.5 * expf(-t / 0.0003)
            out[i] = tick * level * 2.2
        }
        return buffer
    }
}

#Preview {
    struct Demo: View {
        @State private var a = 72.0
        @State private var b = 30.0
        var body: some View {
            HStack(spacing: 24) {
                DotDial(value: $a, size: 200, tone: .light)
                DotDial(value: $b, size: 200, tone: .dark)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: 0.5))
        }
    }
    return Demo()
}
