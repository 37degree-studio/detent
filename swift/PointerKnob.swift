// PointerKnob.swift — Detent
// A guitar-pedal potentiometer knob. It turns smoothly with your finger, with a fine tick every
// twentieth of its sweep, and stops hard at both ends. centerDetent adds the bump at 12 o'clock that pedal EQ knobs have. The value readout rolls
// like an odometer while you turn; double-tap turns it back to where it started. iOS / iPadOS 17+.
//
// Usage:
//   @State private var gain = 5.0
//   PointerKnob(value: $gain, label: "Gain")
//   PointerKnob(value: $bass, in: -12...12, label: "Bass", centerDetent: true)

import SwiftUI
import UIKit
import AVFoundation

public struct PointerKnob: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let label: String
    private let size: CGFloat
    private let knob: Color
    private let tick: Color
    private let centerDetent: Bool
    private let sound: Bool
    private let initial: Double

    public init(value: Binding<Double>,
                in range: ClosedRange<Double> = 0...10,
                label: String = "Value",
                size: CGFloat = 110,
                knob: Color = Color(white: 0.29),
                tick: Color = .white,
                centerDetent: Bool = false,
                sound: Bool = true) {
        _value = value
        self.range = range
        self.label = label
        self.size = size
        self.knob = knob
        self.tick = tick
        self.centerDetent = centerDetent
        self.sound = sound
        self.initial = value.wrappedValue
    }

    @State private var raw: Double?
    @State private var lastAngle: Double?
    @State private var pressed = false
    @State private var held = false
    @State private var atEdge = 0
    @State private var notch = 0
    @State private var hovering = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var span: Double { range.upperBound - range.lowerBound }
    private var mid: Double { (range.lowerBound + range.upperBound) / 2 }
    private var angle: Angle { .degrees(-150 + (value - range.lowerBound) / span * 300) }
    private var showValue: Bool { pressed || hovering || focused }

    public var body: some View {
        VStack(spacing: 12) {
            ZStack {
                seat
                cap
            }
            .frame(width: size + 12, height: size + 12)
            .gesture(turnGesture)
                .onTapGesture(count: 2) { reset() }
            ZStack {
                Text(label)
                    .opacity(showValue ? 0 : 1)
                // The readout rolls like an odometer, blurred along the motion while it moves.
                Text(value, format: .number.precision(.fractionLength(1)))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .contentTransition(.numericText(value: value))
                    .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: value)
                    .opacity(showValue ? 1 : 0)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color(white: 0.17))
            .animation(.easeOut(duration: 0.15), value: showValue)
        }
        .onHover { hovering = $0 }
        .focusable()
        .focused($focused)
        .onKeyPress(keys: [.upArrow, .rightArrow, .downArrow, .leftArrow]) { press in
            nudge(press.key == .upArrow || press.key == .rightArrow ? span * 0.01 : -span * 0.01)
            return .handled
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(value.formatted(.number.precision(.fractionLength(1))))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudge(span * 0.05)
            case .decrement: nudge(-span * 0.05)
            @unknown default: break
            }
        }
    }

    // Matte plastic cap, lit from above, sitting on the panel with a contact shadow. A printed pointer line.
    // The seat: a shallow recess in the panel the knob sits in. Always there; the knob sinks into it, the seat never moves.
    private var seat: some View {
        Circle()
            .fill(.black.opacity(0.06))
            .overlay(Circle().strokeBorder(.black.opacity(0.16), lineWidth: 2).blur(radius: 1).offset(y: 1).mask(Circle()))
            .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1).offset(y: 1)
                .mask(LinearGradient(colors: [.clear, .white], startPoint: .center, endPoint: .bottom)))
            .frame(width: size + 12, height: size + 12)
    }

    private var cap: some View {
        let light = RadialGradient(colors: [.white.opacity(0.09), .clear, .black.opacity(0.18)],
                                   center: UnitPoint(x: 0.5, y: 0.28), startRadius: 0, endRadius: size * 0.6)
        return ZStack {
            Circle().fill(knob)
            Circle().fill(light)
            Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1)
                .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
            Capsule()
                .fill(tick)
                .frame(width: 2, height: size * 0.16)
                .offset(y: -size * 0.34)
                .rotationEffect(angle)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .shadow(color: .black.opacity(0.3), radius: pressed ? 0.6 : 0.9, y: pressed ? 0.5 : 1)
        .shadow(color: .black.opacity(0.2), radius: pressed ? 2 : 3, y: pressed ? 2 : 3)
        .shadow(color: .black.opacity(0.28), radius: pressed ? 5 : 8, y: pressed ? 5 : 8)
        .scaleEffect(pressed ? 0.994 : 1)                // a finger presses it in a hair; it never lifts
        .offset(y: pressed ? 0.5 : 0)
    }

    private var turnGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let c = (size + 12) / 2                           // the gesture lives on the seat, 6pt larger all round
                let dx = g.location.x - c, dy = g.location.y - c
                guard hypot(dx, dy) > 8 else { return }
                let a = atan2(dy, dx) * 180 / .pi
                if raw == nil {
                    raw = value
                    withAnimation(.easeOut(duration: 0.05)) { pressed = true }
                    Feedback.shared.prepare()
                }
                if let last = lastAngle {
                    var d = a - last
                    if d > 180 { d -= 360 } else if d < -180 { d += 360 }
                    turn(by: d / 300 * span)
                }
                lastAngle = a
            }
            .onEnded { _ in
                lastAngle = nil
                raw = nil
                withAnimation(.easeOut(duration: 0.05)) { pressed = false }
            }
    }

    private func turn(by dv: Double) {
        // Hard end stops: past them the knob simply doesn't turn.
        let r = min(range.upperBound, max(range.lowerBound, (raw ?? value) + dv))
        raw = r
        var v = r
        if centerDetent {
            // The center detent holds the knob at 12 o'clock until you push a little past it.
            let inside = abs(r - mid) < span * 0.03
            if inside { v = mid }
            if inside && !held { Feedback.shared.detent(sound: sound) }
            held = inside
        }
        commit(v)
    }

    private func nudge(_ dv: Double) {
        raw = value
        turn(by: dv)
        raw = nil
    }

    // Double-tap: someone turns it back by hand. Quick, no bounce.
    private func reset() {
        withAnimation(reduceMotion ? nil : .timingCurve(0.4, 0, 0.2, 1, duration: 0.22)) { value = initial }
    }

    // A fine tick every twentieth of the sweep, a dull one at the end stops.
    private func commit(_ v: Double) {
        guard v != value else { return }
        value = v
        let n = Int(((v - range.lowerBound) / span * 20).rounded())
        if v > range.lowerBound, v < range.upperBound, n != notch, !(centerDetent && v == mid) { Feedback.shared.tick(sound: sound) }
        notch = n
        let edge = v <= range.lowerBound ? -1 : v >= range.upperBound ? 1 : 0
        if edge != 0 && atEdge != edge { Feedback.shared.stop(sound: sound) }
        if edge != 0 { atEdge = edge }
        else if (atEdge < 0 && v > range.lowerBound + span * 0.03) || (atEdge > 0 && v < range.upperBound - span * 0.03) { atEdge = 0 }
    }
}

/// A light tap per notch, a firmer one at the center detent and the end stops.
@MainActor private final class Feedback {
    static let shared = Feedback()
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let synth = ClickSynth()

    private let soft = UIImpactFeedbackGenerator(style: .soft)

    func prepare() { rigid.prepare(); soft.prepare() }
    func tick(sound: Bool) {
        soft.impactOccurred(intensity: 0.4)
        soft.prepare()
        if sound { synth.play(.tick) }
    }
    func detent(sound: Bool) {
        rigid.impactOccurred(intensity: 0.5)
        rigid.prepare()
        if sound { synth.play(.detent) }
    }
    func stop(sound: Bool) {
        rigid.impactOccurred(intensity: 0.6)
        if sound { synth.play(.stop) }
    }
}

/// Small hard parts can't make a pitched thump: they ring for a millisecond or two at a few high body modes.
private final class ClickSynth {
    enum Voice: CaseIterable { case tick, detent, stop }
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
        let rate = Float(format.sampleRate)
        let frames = AVAudioFrameCount(rate * 0.02)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let out = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        if voice == .tick {
            // The fine tick: a few milliseconds of bright, high-passed noise.
            var smooth: Float = 0
            for i in 0..<Int(frames) {
                let t = Float(i) / rate
                let white = Float.random(in: -1...1)
                smooth += (white - smooth) * 0.12
                out[i] = (white - smooth) * expf(-t / 0.0025) * 0.2
            }
            return buffer
        }
        let (level, tune): (Float, Float) = voice == .detent ? (0.05, 1.2) : (0.09, 0.85)
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
        @State private var gain = 2.0
        @State private var level = 7.5
        @State private var bass = 0.0
        var body: some View {
            HStack(spacing: 28) {
                PointerKnob(value: $gain, label: "Gain")
                PointerKnob(value: $level, label: "Level")
                PointerKnob(value: $bass, in: -12...12, label: "Bass", centerDetent: true)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.94, green: 0.94, blue: 0.93))
        }
    }
    return Demo()
}
