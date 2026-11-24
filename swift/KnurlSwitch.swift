// KnurlSwitch.swift — Detent
// A slide switch with a machined thumb that behaves like the hardware: the thumb holds against
// its detent, then snaps over center into a hard stop with a small, dry two-part tick.
// Tap it or push the thumb. Haptics and the click sound are built in. iOS / iPadOS 17+.
//
// Usage:
//   @State private var isOn = true
//   KnurlSwitch(isOn: $isOn)
//   KnurlSwitch(isOn: $isOn, tint: .blue, width: 190)

import SwiftUI
import UIKit
import AVFoundation

public struct KnurlSwitch: View {
    @Binding private var isOn: Bool
    private let tint: Color
    private let width: CGFloat
    private let sound: Bool
    private let label: String

    public init(isOn: Binding<Bool>,
                tint: Color = Color(red: 0.96, green: 0.49, blue: 0),
                width: CGFloat = 150,
                sound: Bool = true,
                label: String = "Switch") {
        _isOn = isOn
        self.tint = tint
        self.width = width
        self.sound = sound
        self.label = label
    }

    @State private var give: CGFloat = 0       // how far the thumb yields against its detent (0...1 of travel)
    @State private var anchor: CGFloat = 0     // finger x where the current push started
    @State private var pressed = false
    @State private var moved = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    // Geometry, all derived from the width so the switch scales as one piece.
    private var pad: CGFloat { width * 0.035 }
    private var wellW: CGFloat { width - pad * 2 }
    private var wellH: CGFloat { width * 0.47 }
    private var inset: CGFloat { wellH * 0.04 }
    private var thumbD: CGFloat { wellH * 0.92 }
    private var span: CGFloat { wellW - thumbD - inset * 2 }
    private var progress: CGFloat { (isOn ? 1 : 0) + (isOn ? -give : give) }
    private let hold: CGFloat = 0.3             // push this far against the detent and it snaps over center
    // Over center, the detent spring throws the slider: it accelerates and stops dead. No overshoot.
    private var snap: Animation? { reduceMotion ? nil : .timingCurve(0.55, 0, 1, 1, duration: 0.11) }

    public var body: some View {
        ZStack {
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.7), Color(white: 0.92), Color(white: 0.98), .white],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().strokeBorder(.white.opacity(0.9), lineWidth: 1).blendMode(.overlay))
                .shadow(color: .black.opacity(0.28), radius: 14, y: 12)
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            well
                .frame(width: wellW, height: wellH)
        }
        .frame(width: width, height: wellH + pad * 2)
        .contentShape(Capsule())
        .gesture(dragGesture)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
        .accessibilityAction { set(!isOn) }
    }

    private var well: some View {
        ZStack(alignment: .leading) {
            // Off: a dark recess with an embossed ring on the right.
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.36), Color(white: 0.46)], startPoint: .top, endPoint: .bottom))
            Circle()
                .strokeBorder(Color(white: 0.3), lineWidth: 2)
                .frame(width: wellW * 0.17, height: wellW * 0.17)
                .offset(x: wellW * (1 - 0.12 - 0.17))

            // On: the tint is revealed up to the thumb's center, so it follows your finger.
            Capsule()
                .fill(LinearGradient(colors: [tint, tint.opacity(0.88)], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.55))
                        .frame(width: wellW * 0.035, height: wellH * 0.24)
                        .shadow(color: .white.opacity(isOn ? 0.8 : 0), radius: 4)
                        .offset(x: wellW * 0.13)
                }
                .mask(alignment: .leading) {
                    Rectangle().frame(width: max(0, inset + progress * span + thumbD / 2 + progress * (thumbD / 2 + inset)))
                }

            // The recess shadow sits above both fills.
            Capsule()
                .strokeBorder(.black.opacity(0.55), lineWidth: 7)
                .blur(radius: 5)
                .offset(y: 3)
                .mask(Capsule())
                .allowsHitTesting(false)
            Capsule().strokeBorder(.black.opacity(0.3), lineWidth: 1)

            thumb
                .frame(width: thumbD, height: thumbD)
                .scaleEffect(pressed ? 0.985 : 1)              // a finger presses it in a hair; it never lifts
                .shadow(color: .black.opacity(0.45), radius: pressed ? 4 : 7, y: pressed ? 4 : 6)
                .offset(x: inset + progress * span, y: pressed ? 0.6 : 0)
        }
        .clipShape(Capsule())
    }

    private var thumb: some View {
        let face = thumbD * 0.82
        // A polished bezel: the light stays put while the metal turns, like the web version.
        return ZStack {
            Circle().fill(AngularGradient(colors: [Color(white: 0.99), Color(white: 0.8), Color(white: 0.96), Color(white: 0.73),
                                                   Color(white: 0.98), Color(white: 0.83), Color(white: 0.99)],
                                          center: .center, angle: .degrees(200)))
            KnurlFace()
                .frame(width: face, height: face)
                .clipShape(Circle())
                .overlay(Circle().fill(RadialGradient(colors: [.white.opacity(0.38), .clear, .black.opacity(0.18)],
                                                      center: UnitPoint(x: 0.5, y: 0.28), startRadius: 0, endRadius: face * 0.6)))
                .overlay(Circle().strokeBorder(.black.opacity(0.18), lineWidth: 1.5).blur(radius: 1).offset(y: 1).mask(Circle()))
        }
        .compositingGroup()
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if !pressed {
                    withAnimation(.easeOut(duration: 0.05)) { pressed = true }
                    anchor = g.startLocation.x
                    Feedback.shared.prepare()
                }
                let dx = g.location.x - anchor
                if !moved && abs(dx) < 3 { return }
                moved = true
                let push = (isOn ? -dx : dx) / span       // > 0 means toward the other end
                if push >= hold {
                    anchor = g.location.x                  // re-anchor so it can be pushed back
                    set(!isOn)
                } else {
                    give = max(0, push) * 0.22             // the thumb only yields a little against the detent
                }
            }
            .onEnded { _ in
                let tap = !moved
                withAnimation(.easeOut(duration: 0.09)) { pressed = false; give = 0 }   // detent spring pushes it home
                moved = false
                if tap { set(!isOn) }
            }
    }

    private func set(_ value: Bool) {
        guard isEnabled, value != isOn else { return }
        withAnimation(snap) { isOn = value; give = 0 }
        Feedback.shared.snap(sound: sound, on: value)
    }
}

/// The diamond knurl: rows of tiny four-sided pyramids, each face lit differently.
private struct KnurlFace: View {
    var body: some View {
        Canvas { ctx, size in
            let cell: CGFloat = 5
            let shades: [Color] = [Color(white: 0.99), Color(white: 0.8), Color(white: 0.69), Color(white: 0.9)] // top, right, bottom, left
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    let c = CGPoint(x: x + cell / 2, y: y + cell / 2)
                    let corners = [CGPoint(x: x, y: y), CGPoint(x: x + cell, y: y),
                                   CGPoint(x: x + cell, y: y + cell), CGPoint(x: x, y: y + cell)]
                    for i in 0..<4 {
                        var tri = Path()
                        tri.move(to: corners[i]); tri.addLine(to: corners[(i + 1) % 4]); tri.addLine(to: c); tri.closeSubpath()
                        ctx.fill(tri, with: .color(shades[i]))
                    }
                    x += cell
                }
                y += cell
            }
        }
    }
}

/// One firm, short haptic at the snap, plus the click. Nothing on touch-down: a real switch is silent until it moves.
@MainActor private final class Feedback {
    static let shared = Feedback()
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let synth = ClickSynth()

    func prepare() { rigid.prepare() }
    func snap(sound: Bool, on: Bool) {
        rigid.impactOccurred(intensity: 0.75)
        if sound { synth.play(on ? .on : .off) }
    }
}

/// Small hard parts can't make a pitched thump: they ring for a millisecond or two at a few high body modes.
/// A slide switch makes two of those: the slider leaving its detent (quiet), then landing on the stop.
private final class ClickSynth {
    enum Voice: CaseIterable { case on, off }
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

    // Body modes of a small ABS slider and its contact leaf: (Hz, decay seconds, gain)
    private static let modes: [(Float, Float, Float)] = [(1900, 0.0024, 1), (3400, 0.0015, 0.55), (6100, 0.0008, 0.3)]

    private static func render(_ voice: Voice, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let pitch: Float = voice == .on ? 1.04 : 0.96
        let rate = Float(format.sampleRate)
        let frames = AVAudioFrameCount(rate * 0.04)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let out = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        // (start time, level, tuning) for the release tick and the landing tick
        let ticks: [(Float, Float, Float)] = [(0, 0.07, 1.08 * pitch), (0.009, 0.16, pitch)]
        for i in 0..<Int(frames) {
            let t = Float(i) / rate
            var sample: Float = 0
            for (start, level, tune) in ticks where t >= start {
                let local = t - start
                var tick: Float = 0
                for (hz, decay, gain) in modes {
                    tick += gain * sinf(2 * .pi * hz * tune * local) * expf(-local / decay)
                }
                tick += Float.random(in: -1...1) * 0.5 * expf(-local / 0.0003)   // the contact itself
                sample += tick * level
            }
            out[i] = sample * 2.2
        }
        return buffer
    }
}

#Preview {
    struct Demo: View {
        @State private var a = true
        @State private var b = false
        @State private var c = true
        var body: some View {
            VStack(spacing: 28) {
                HStack(spacing: 24) {
                    KnurlSwitch(isOn: $a)
                    KnurlSwitch(isOn: $b)
                }
                KnurlSwitch(isOn: $c, tint: .blue, width: 190)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LinearGradient(colors: [Color(white: 0.96), Color(white: 0.84)], startPoint: .top, endPoint: .bottom))
        }
    }
    return Demo()
}
