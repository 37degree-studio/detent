// IndexKnob.swift — Detent
// A rotary selector switch: a matte black knob with an inlaid pointer line and a dark finger cup.
// Each position has a spring detent: the knob gives a little, snaps over center into the next
// position with a click, and stops hard at both ends. Haptics and sound are built in. iOS / iPadOS 17+.
//
// Usage:
//   @State private var power = 4
//   IndexKnob(value: $power, steps: 5, label: "PWR")
//   IndexKnob(value: $mode, steps: 3, label: "TCS", size: 140, line: .orange)

import SwiftUI
import UIKit
import AVFoundation

public struct IndexKnob: View {
    @Binding private var value: Int             // 1...steps
    private let steps: Int
    private let label: String
    private let size: CGFloat
    private let line: Color
    private let sound: Bool

    public init(value: Binding<Int>,
                steps: Int = 5,
                label: String = "PWR",
                size: CGFloat = 170,
                line: Color = Color(red: 0.83, green: 0.87, blue: 0.23),
                sound: Bool = true) {
        _value = value
        self.steps = max(2, steps)
        self.label = label
        self.size = size
        self.line = line
        self.sound = sound
    }

    @State private var acc: Double = 0          // degrees pushed past the current position
    @State private var pushDir: Double = 0
    @State private var lastAngle: Double?
    @State private var pressed = false
    @State private var atEdge = 0
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var gap: Double { 270 / Double(steps - 1) }
    private func angleOf(_ i: Int) -> Double { -135 + Double(i - 1) * gap }
    // After a snap the knob is ahead of the finger, so it only shows give while it's actually being pushed.
    private var give: Double { acc.sign == pushDir.sign && pushDir != 0 ? acc * 0.25 : 0 }
    private var discD: CGFloat { size * 0.82 }
    // Over center, the detent spring throws the knob: it accelerates and stops dead. No overshoot.
    private var snap: Animation? { reduceMotion ? nil : .timingCurve(0.55, 0, 1, 1, duration: 0.07) }

    public var body: some View {
        VStack(spacing: 14) {
            ZStack {
                marks
                disc
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(turnGesture)
            Text("\(label):\(value)")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Color(white: 0.6))
                .monospacedDigit()
        }
        .focusable()
        .focused($focused)
        .onKeyPress(keys: [.upArrow, .rightArrow, .downArrow, .leftArrow]) { press in
            nudge(press.key == .upArrow || press.key == .rightArrow ? 1 : -1)
            return .handled
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(value) of \(steps)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudge(1)
            case .decrement: nudge(-1)
            @unknown default: break
            }
        }
    }

    // Printed position marks: they belong to the panel, so they never change.
    private var marks: some View {
        ForEach(1...steps, id: \.self) { i in
            Circle()
                .fill(Color(white: 0.66))
                .frame(width: 4, height: 4)
                .offset(y: -size * 0.48)
                .rotationEffect(.degrees(angleOf(i)))
        }
    }

    // Matte soft-touch black, lit from above, sitting on the panel with a contact shadow.
    private var disc: some View {
        let body = RadialGradient(colors: [Color(white: 0.14), Color(white: 0.086), Color(white: 0.063)],
                                  center: UnitPoint(x: 0.5, y: 0.28), startRadius: 0, endRadius: discD * 0.7)
        return ZStack {
            Circle().fill(body)
            Circle().strokeBorder(.white.opacity(0.1), lineWidth: 1).mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
            ZStack {
                // The pointer: a thin inlaid stripe.
                Capsule()
                    .fill(line)
                    .frame(width: discD * 0.02, height: discD * 0.4)
                    .offset(y: -discD * 0.22)
                // The finger cup: a dimple pressed into the same black, on the opposite side. It shows only by
                // its shaded upper wall and the light catching its lower edge.
                Circle()
                    .fill(RadialGradient(colors: [Color(white: 0.11), Color(white: 0.07), Color(white: 0.047)],
                                         center: UnitPoint(x: 0.5, y: 0.65), startRadius: 0, endRadius: discD * 0.07))
                    .overlay(Circle().strokeBorder(.black.opacity(0.85), lineWidth: 2).blur(radius: 1).offset(y: 1.2).mask(Circle()))
                    .overlay(Circle().strokeBorder(.white.opacity(0.1), lineWidth: 0.8).offset(y: 0.6)
                        .mask(LinearGradient(colors: [.clear, .white], startPoint: .center, endPoint: .bottom)))
                    .frame(width: discD * 0.128, height: discD * 0.128)
                    .offset(y: discD * 0.36)
            }
            .rotationEffect(.degrees(angleOf(value) + give))
        }
        .frame(width: discD, height: discD)
        .shadow(color: .black.opacity(0.45), radius: pressed ? 0.6 : 0.9, y: pressed ? 0.5 : 1)
        .shadow(color: .black.opacity(0.25), radius: pressed ? 2.5 : 4, y: pressed ? 2 : 4)
        .shadow(color: .black.opacity(0.35), radius: pressed ? 7 : 11, y: pressed ? 7 : 12)
        .scaleEffect(pressed ? 0.994 : 1)                 // a finger presses it in a hair; it never lifts
        .offset(y: pressed ? 0.5 : 0)
    }

    private var turnGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let dx = g.location.x - size / 2, dy = g.location.y - size / 2
                guard hypot(dx, dy) > 8 else { return }
                let a = atan2(dy, dx) * 180 / .pi
                if !pressed {
                    withAnimation(.easeOut(duration: 0.05)) { pressed = true }
                    acc = 0
                    Feedback.shared.prepare()
                }
                if let last = lastAngle {
                    var d = a - last
                    if d > 180 { d -= 360 } else if d < -180 { d += 360 }
                    push(d)
                }
                lastAngle = a
            }
            .onEnded { _ in
                lastAngle = nil
                // Let go between positions and the detent pulls the knob back into place.
                withAnimation(reduceMotion ? nil : .timingCurve(0.2, 0, 0.3, 1, duration: 0.08)) { pressed = false; acc = 0; pushDir = 0 }
            }
    }

    // It only gives a little until it passes halfway to the next position, then the detent throws it over.
    private func push(_ d: Double) {
        pushDir = d < 0 ? -1 : 1
        acc += d
        while abs(acc) > gap / 2 {
            let dir = acc < 0 ? -1 : 1
            let n = value + dir
            if n < 1 || n > steps {                     // hard end stop: no give at all
                acc = 0
                hitStop(n)
                break
            }
            acc -= Double(dir) * gap
            set(n)
        }
    }

    private func nudge(_ dir: Int) {
        let n = value + dir
        if n < 1 || n > steps { hitStop(n); return }
        set(n)
    }

    private func set(_ n: Int) {
        guard n != value else { return }
        withAnimation(snap) { value = n }
        Feedback.shared.click(sound: sound)
        if (atEdge < 0 && n > 1) || (atEdge > 0 && n < steps) { atEdge = 0 }
    }

    // End stops sound once on arrival and stay silent while you keep pushing.
    private func hitStop(_ n: Int) {
        let side = n < 1 ? -1 : 1
        guard atEdge != side else { return }
        atEdge = side
        Feedback.shared.stop(sound: sound)
    }
}

/// A firm haptic per position, like a ball dropping into a notch. Nothing on touch-down.
@MainActor private final class Feedback {
    static let shared = Feedback()
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let synth = ClickSynth()

    func prepare() { rigid.prepare() }
    func click(sound: Bool) {
        rigid.impactOccurred(intensity: 0.85)
        rigid.prepare()
        if sound { synth.play(.click) }
    }
    func stop(sound: Bool) {
        rigid.impactOccurred(intensity: 0.6)
        if sound { synth.play(.stop) }
    }
}

/// Small hard parts can't make a pitched thump: they ring for a millisecond or two at a few high body modes.
/// A selector makes two: the spring-loaded ball dropping into the notch, then the wiper settling.
private final class ClickSynth {
    enum Voice: CaseIterable { case click, stop }
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
        // (start time, level, tuning) for each tick
        let ticks: [(Float, Float, Float)] = voice == .click
            ? [(0, 0.12, 0.95), (0.006, 0.035, 1.25)]
            : [(0, 0.09, 0.85)]
        let rate = Float(format.sampleRate)
        let frames = AVAudioFrameCount(rate * 0.03)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let out = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            let t = Float(i) / rate
            var sample: Float = 0
            for (start, level, tune) in ticks where t >= start {
                let local = t - start
                var tick: Float = 0
                for (hz, decay, gain) in modes { tick += gain * sinf(2 * .pi * hz * tune * local) * expf(-local / decay) }
                tick += Float.random(in: -1...1) * 0.5 * expf(-local / 0.0003)
                sample += tick * level
            }
            out[i] = sample * 2.2
        }
        return buffer
    }
}

#Preview {
    struct Demo: View {
        @State private var power = 4
        @State private var tcs = 1
        var body: some View {
            HStack(spacing: 32) {
                IndexKnob(value: $power, steps: 5, label: "PWR")
                IndexKnob(value: $tcs, steps: 3, label: "TCS")
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.94, green: 0.94, blue: 0.93))
        }
    }
    return Demo()
}
