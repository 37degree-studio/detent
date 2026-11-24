// MachinedDial.swift — Detent
// A turned-aluminum knob sitting in a recessed, brushed bowl. It turns like a detented rotary
// encoder: pulled into each notch with a tiny click, and stopped dead at both ends.
// detents: 0 makes it a smooth, silent potentiometer. Haptics and sound are built in. iOS / iPadOS 17+.
//
// Usage:
//   @State private var level = 40.0
//   MachinedDial(value: $level)
//   MachinedDial(value: $level, size: 280, accent: .red, detents: 24)

import SwiftUI
import UIKit
import AVFoundation

public struct MachinedDial: View {
    @Binding private var value: Double          // 0...100
    private let size: CGFloat
    private let accent: Color
    private let detents: Int
    private let sound: Bool
    private let label: String

    public init(value: Binding<Double>,
                size: CGFloat = 240,
                accent: Color = Color(red: 0.95, green: 0.39, blue: 0.12),
                detents: Int = 60,
                sound: Bool = true,
                label: String = "Level") {
        _value = value
        self.size = size
        self.accent = accent
        self.detents = max(0, detents)
        self.sound = sound
        self.label = label
    }

    @State private var raw: Double?             // unsnapped position while a finger turns it
    @State private var lastAngle: Double?
    @State private var pressed = false
    @State private var atEdge = 0               // -1 / 1 while resting on an end stop, so it ticks only once
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var step: Double { detents > 0 ? 100 / Double(detents) : 0 }
    private var marks: Int { detents > 0 ? detents : 60 }
    // Between notches the detent spring holds the knob, so it only gives a little until it clicks over.
    private var shown: Double {
        guard let raw, step > 0 else { return value }
        return value + (raw - value) * 0.3
    }
    private var angle: Angle { .degrees(-135 + shown * 2.7) }
    private var capD: CGFloat { size * 0.56 }

    public var body: some View {
        ZStack {
            Scale(marks: marks, lit: value, accent: accent)
            bowl.padding(size * 0.11)
            cap
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(turnGesture)
        .focusable()
        .focused($focused)
        .onKeyPress(keys: [.upArrow, .rightArrow, .downArrow, .leftArrow]) { press in
            nudge(press.key == .upArrow || press.key == .rightArrow ? 1 : -1)
            return .handled
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value.rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudge(1)
            case .decrement: nudge(-1)
            @unknown default: break
            }
        }
    }

    // The bowl is a recess cut into the panel, brushed in a circle. Light comes from above, so the upper
    // inner wall sits in shadow. Its highlights belong to the room, so they never turn.
    private var bowl: some View {
        let metal: [Color] = [w(0.98), w(0.6), w(0.91), w(0.36), w(0.85), w(0.98), w(0.54), w(0.95), w(0.98)]
        return Circle()
            .fill(AngularGradient(colors: metal, center: .center, angle: .degrees(210)))
            .overlay(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 6).blur(radius: 4).offset(y: 3).mask(Circle()))
            .overlay(Circle().strokeBorder(.black.opacity(0.14), lineWidth: 1))
    }

    // The cap: a short cylinder. Its chamfered rim catches the top light; the flat face is lathe-turned.
    private var cap: some View {
        let face = capD * 0.948
        return ZStack {
            Circle().fill(LinearGradient(colors: [w(0.985), w(0.85), w(0.725)], startPoint: .top, endPoint: .bottom))
            ZStack {
                Circle().fill(RadialGradient(colors: [w(0.985), w(0.925), w(0.87)], center: UnitPoint(x: 0.46, y: 0.32),
                                             startRadius: 0, endRadius: face * 0.7))
                // Lathe rings, faded out toward the center, and the fan-shaped sheen of a turned face.
                LatheRings()
                    .mask(RadialGradient(colors: [.clear, .black], center: .center, startRadius: face * 0.09, endRadius: face * 0.3))
                Circle().fill(AngularGradient(colors: [.clear, .white.opacity(0.35), .clear, .clear, .clear,
                                                       .clear, .white.opacity(0.28), .clear, .clear, .clear],
                                              center: .center, angle: .degrees(120)))
            }
            .frame(width: face, height: face)
            .clipShape(Circle())
            // The indicator: a short groove cut into the face and filled with paint, flush with the surface.
            Capsule()
                .fill(accent)
                .overlay(Capsule().strokeBorder(.black.opacity(0.22), lineWidth: 0.8).offset(y: 0.5).mask(Capsule()))
                .frame(width: capD * 0.036, height: capD * 0.17)
                .offset(y: -capD * 0.325)
                .rotationEffect(angle)
        }
        .frame(width: capD, height: capD)
        // A contact shadow where it meets the bowl, then a soft cast shadow below. It never lifts.
        .shadow(color: .black.opacity(0.35), radius: pressed ? 0.6 : 0.9, y: pressed ? 0.5 : 1)
        .shadow(color: .black.opacity(0.2), radius: pressed ? 1.5 : 2.5, y: pressed ? 1.5 : 3)
        .shadow(color: .black.opacity(0.25), radius: pressed ? 4 : 7, y: pressed ? 5 : 8)
        .scaleEffect(pressed ? 0.994 : 1)
        .offset(y: pressed ? 0.5 : 0)
    }

    private var turnGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let dx = g.location.x - size / 2, dy = g.location.y - size / 2
                guard hypot(dx, dy) > 8 else { return }          // too close to the axis to read an angle
                let a = atan2(dy, dx) * 180 / .pi
                if raw == nil {
                    raw = value
                    withAnimation(.easeOut(duration: 0.05)) { pressed = true }
                    Feedback.shared.prepare()
                }
                if let last = lastAngle {
                    var d = a - last
                    if d > 180 { d -= 360 } else if d < -180 { d += 360 }
                    turn(by: d * 100 / 270)
                }
                lastAngle = a
            }
            .onEnded { _ in
                lastAngle = nil
                // Let go between notches and it drops into the nearest one. Nothing keeps spinning.
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.06)) { raw = nil; pressed = false }
            }
    }

    private func turn(by dv: Double) {
        // The end stops are hard: past them the knob simply doesn't turn, and the finger slips.
        let r = min(100, max(0, (raw ?? value) + dv))
        raw = r
        commit(snap(r))
    }

    private func nudge(_ n: Int) {
        let v = snap(value + Double(n) * (step > 0 ? step : 1))
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.06)) { commit(v) }
    }

    private func snap(_ v: Double) -> Double {
        let c = min(100, max(0, v))
        return step > 0 ? (c / step).rounded() * step : c
    }

    private func commit(_ v: Double) {
        guard v != value else { return }
        value = v
        if atEdge == 0, v <= 0 || v >= 100 {
            atEdge = v <= 0 ? -1 : 1
            Feedback.shared.stop(sound: sound)
        } else if (atEdge < 0 && v > 3) || (atEdge > 0 && v < 97) {
            atEdge = 0
        }
        if step > 0, v > 0, v < 100 { Feedback.shared.detent(sound: sound) }
    }

    private func w(_ white: Double) -> Color { Color(white: white) }
}

/// The engraved scale around the bowl, backlit up to the value in the indicator color.
private struct Scale: View {
    let marks: Int
    let lit: Double
    let accent: Color
    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let long = max(1, Int((Double(marks) / 12).rounded()))
            let litUpTo = Int((lit / 100 * Double(marks)).rounded())
            for i in 0...marks {
                let a = (-135 + Double(i) * 270 / Double(marks) - 90) * .pi / 180
                let isLong = i % long == 0
                let outer = r * 0.96, inner = r * (isLong ? 0.84 : 0.88)
                var p = Path()
                p.move(to: CGPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner))
                p.addLine(to: CGPoint(x: c.x + cos(a) * outer, y: c.y + sin(a) * outer))
                let on = lit > 0 && i <= litUpTo
                ctx.stroke(p, with: .color(on ? accent : Color(white: isLong ? 0.41 : 0.5)),
                           style: StrokeStyle(lineWidth: isLong ? 1.4 : 1.2, lineCap: .round))
            }
        }
    }
}

/// Fine concentric rings left by the lathe.
private struct LatheRings: View {
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            var r: CGFloat = 1.6
            while r < size.width / 2 {
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                           with: .color(.black.opacity(0.025)), lineWidth: 0.6)
                r += 2.2
            }
        }
        .clipShape(Circle())
    }
}

/// A light, crisp haptic per notch and a firmer one at an end stop. Nothing on touch-down.
@MainActor private final class Feedback {
    static let shared = Feedback()
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let synth = ClickSynth()

    func prepare() { rigid.prepare() }
    func detent(sound: Bool) {
        rigid.impactOccurred(intensity: 0.45)
        rigid.prepare()
        if sound { synth.play(.detent) }
    }
    func stop(sound: Bool) {
        rigid.impactOccurred(intensity: 0.7)
        if sound { synth.play(.stop) }
    }
}

/// Small hard parts can't make a pitched thump: they ring for a millisecond or two at a few high body modes.
private final class ClickSynth {
    enum Voice: CaseIterable { case detent, stop }
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

    // Body modes of a small plastic/metal part: (Hz, decay seconds, gain)
    private static let modes: [(Float, Float, Float)] = [(1900, 0.0024, 1), (3400, 0.0015, 0.55), (6100, 0.0008, 0.3)]

    private static func render(_ voice: Voice, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        // The encoder notch is brighter and quieter; the end stop is a little duller.
        let (level, tune): (Float, Float) = voice == .detent ? (0.05, 1.35) : (0.09, 0.85)
        let rate = Float(format.sampleRate)
        let frames = AVAudioFrameCount(rate * 0.02)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let out = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            let t = Float(i) / rate
            var tick: Float = 0
            for (hz, decay, gain) in modes { tick += gain * sinf(2 * .pi * hz * tune * t) * expf(-t / decay) }
            tick += Float.random(in: -1...1) * 0.5 * expf(-t / 0.0003)   // the contact itself
            out[i] = tick * level * 2.2
        }
        return buffer
    }
}

#Preview {
    struct Demo: View {
        @State private var level = 40.0
        @State private var smooth = 70.0
        var body: some View {
            VStack(spacing: 32) {
                MachinedDial(value: $level)
                Text("\(Int(level))").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                MachinedDial(value: $smooth, size: 160, detents: 0)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RadialGradient(colors: [Color(white: 0.96), Color(white: 0.84)], center: .top, startRadius: 0, endRadius: 700))
        }
    }
    return Demo()
}
