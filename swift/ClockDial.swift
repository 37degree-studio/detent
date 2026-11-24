// ClockDial.swift — Detent
// A frosted clock tile you set like a real clock. Drag around the face and the minute hand turns through the setting
// train: it gives a little, then a jumper spring drops it into the next minute with a tiny click, a firmer one every
// five minutes. The hour hand follows through the 12:1 gearing. The display window at 6 o'clock is digital: its digits
// switch instantly, and its orange lamp lights for PM. The A/P pusher in the case corner turns the 24-hour wheel half
// a turn. Hour indices and the minute hand carry luminous paint, which glows in dark mode. iOS / iPadOS 17+.
//
// Usage:
//   @State private var time = 4 * 60 + 45      // minutes since midnight, 0..<1440
//   ClockDial(time: $time)
//   ClockDial(time: $time, size: 200, tone: .dark)

import SwiftUI
import UIKit
import AVFoundation

public struct ClockDial: View {
    @Binding private var time: Int
    private let size: CGFloat
    private let lume: Color
    private let tone: ColorScheme?
    private let sound: Bool

    public init(time: Binding<Int>,
                size: CGFloat = 240,
                lume: Color = Color(red: 0.56, green: 0.85, blue: 0.36),
                tone: ColorScheme? = nil,
                sound: Bool = true) {
        _time = time
        self.size = size
        self.lume = lume
        self.tone = tone
        self.sound = sound
    }

    @State private var hand: Int?               // where the minute hand points, in whole minutes; never wraps
    @State private var raw: Double?             // the finger's position while it turns the train
    @State private var lastAngle: Double?
    @State private var keyDown = false
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var p: Palette { Palette(dark: (tone ?? scheme) == .dark) }
    private var minuteHand: Int { hand ?? mod(time, 720) }
    // Between minutes the jumper spring holds the train, so the hand only gives a little until it drops into the next.
    private var shown: Double {
        guard let raw else { return Double(minuteHand) }
        return Double(minuteHand) + (raw - Double(minuteHand)) * 0.3
    }
    private var u: CGFloat { size / 200 }
    private var pm: Bool { time >= 720 }

    public var body: some View {
        ZStack {
            tile
            Face(u: u, lume: lume, p: p)
            readout.offset(y: size * 0.185)
            // The hour hand is geared to the minute hand, 12:1. Shadows are added after the rotation,
            // so they always fall straight down while the hands turn.
            Hand(u: u, from: 108, to: 60, edge: 6.5, fill: 5, lume: nil, p: p)
                .rotationEffect(.degrees(shown / 2))
                .shadow(color: .black.opacity(p.drop), radius: 1.1 * u, y: 1.6 * u)
            Hand(u: u, from: 110, to: 38, edge: 7, fill: 5.5, lume: lume, p: p)
                .rotationEffect(.degrees(shown * 6))
                .shadow(color: .black.opacity(p.drop), radius: 1.1 * u, y: 1.6 * u)
            Circle().fill(p.hand).overlay(Circle().strokeBorder(p.capEdge, lineWidth: u))
                .frame(width: 12 * u, height: 12 * u)
        }
        .frame(width: size, height: size)
        .contentShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
        .gesture(turnGesture)
        .overlay(alignment: .bottomTrailing) { apKey.padding(.trailing, size * 0.07).padding(.bottom, size * 0.07) }
        .focusable()
        .focused($focused)
        .onKeyPress(keys: [.upArrow, .rightArrow, .downArrow, .leftArrow]) { press in
            nudge(press.key == .upArrow || press.key == .rightArrow ? 1 : -1)
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "apAP")) { press in
            if (press.characters.lowercased() == "a") == pm { flip() }
            return .handled
        }
        .onChange(of: time) { _, t in
            // Set from outside: move the hands to the nearest matching position.
            let h = minuteHand, r = mod(t, 720)
            if mod(h, 720) != r { hand = r + Int((Double(h - r) / 720).rounded()) * 720 }
        }
        .accessibilityElement()
        .accessibilityLabel("Time")
        .accessibilityValue(spoken)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudge(1)
            case .decrement: nudge(-1)
            @unknown default: break
            }
        }
    }

    // Frosted acrylic, lit from above: a bright top rim, a soft sheen at the top, a contact shadow and a cast shadow.
    // It never lifts.
    private var tile: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        return shape
            .fill(LinearGradient(colors: [p.tileTop, p.tileBottom], startPoint: .top, endPoint: .bottom))
            .overlay(shape.fill(RadialGradient(colors: [p.sheen, .clear], center: UnitPoint(x: 0.5, y: -0.08),
                                               startRadius: 0, endRadius: size * 0.75)))
            .overlay(shape.strokeBorder(LinearGradient(colors: [p.rim, .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
            .shadow(color: p.contact, radius: 1, y: 1)
            .shadow(color: p.cast, radius: 18, y: 16)
    }

    // A digital display window set into the dial at 6 o'clock, under the hands, like an ana-digi watch.
    // Its digits and the PM lamp switch instantly, with no animation.
    private var readout: some View {
        HStack(spacing: size * 0.024) {
            Text(String(format: "%02d", mod(time / 60, 12) == 0 ? 12 : mod(time / 60, 12))).foregroundStyle(p.dim)
            Text(String(format: "%02d", time % 60)).fontWeight(.semibold).foregroundStyle(p.ink)
            Circle()
                .fill(pm ? Color(red: 1, green: 0.58, blue: 0) : p.ledOff)
                .shadow(color: pm ? Color(red: 1, green: 0.58, blue: 0).opacity(0.6) : .clear, radius: size * 0.01)
                .frame(width: size * 0.02, height: size * 0.02)
                .padding(.leading, size * 0.014)
        }
        .font(.system(size: size * 0.068, design: .monospaced).monospacedDigit())
        .padding(.horizontal, size * 0.045)
        .frame(height: size * 0.11)
        .background(Capsule().fill(p.chip.shadow(.inner(color: .black.opacity(p.chipShadow * 1.5), radius: 1.5, y: 1))))
        .transaction { $0.animation = nil }
        .allowsHitTesting(false)
    }

    // A two-position pusher set into the case corner, clear of the dial. It latches at the bottom of its travel,
    // so it switches on the press.
    // A press sinks it a hair with a tighter shadow; nothing happens on hover.
    private var apKey: some View {
        Text(pm ? "P" : "A")
            .font(.system(size: size * 0.06, design: .monospaced))
            .foregroundStyle(p.ink)
            .frame(width: size * 0.11, height: size * 0.11)
            .background(chip.shadow(color: .black.opacity(keyDown ? 0.06 : 0), radius: 1, y: 0.5))
            .scaleEffect(keyDown ? 0.994 : 1)
            .offset(y: keyDown ? 0.5 : 0)
            .transaction { $0.animation = nil }
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !keyDown else { return }
                    keyDown = true
                    flip()
                }
                .onEnded { _ in keyDown = false })
            .accessibilityElement()
            .accessibilityLabel(pm ? "PM" : "AM")
            .accessibilityHint("Switches between AM and PM")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { flip() }
    }

    private var chip: some View {
        Capsule().fill(.ultraThinMaterial)
            .overlay(Capsule().fill(p.chip))
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [p.rim, .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
            .shadow(color: .black.opacity(keyDown ? 0 : p.chipShadow), radius: 4, y: 2)
            .environment(\.colorScheme, p.dark ? .dark : .light)
    }

    private var turnGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let dx = g.location.x - size / 2, dy = g.location.y - size / 2
                guard hypot(dx, dy) > 8 else { return }          // too close to the arbor to read an angle
                let a = atan2(dy, dx) * 180 / .pi
                if raw == nil { raw = Double(minuteHand); Feedback.shared.prepare() }
                if let last = lastAngle {
                    var d = a - last
                    if d > 180 { d -= 360 } else if d < -180 { d += 360 }
                    let r = (raw ?? Double(minuteHand)) + d / 6
                    raw = r
                    step(to: Int(r.rounded()))
                }
                lastAngle = a
            }
            .onEnded { _ in
                lastAngle = nil
                // Let go between minutes and the jumper pulls the hand back into the one it's in. Nothing coasts.
                withAnimation(reduceMotion ? nil : .timingCurve(0.2, 0, 0.3, 1, duration: 0.08)) { raw = nil }
            }
    }

    // A step from the keys: the jumper throws the train into the next minute, accelerating, then it stops dead.
    private func nudge(_ dir: Int) {
        withAnimation(reduceMotion ? nil : .timingCurve(0.55, 0, 1, 1, duration: 0.06)) { step(to: minuteHand + dir) }
    }

    private func step(to n: Int) {
        let from = minuteHand
        guard n != from else { return }
        let dir = n > from ? 1 : -1, before = time
        var five = false, k = from + dir
        while k != n + dir { if mod(k, 5) == 0 { five = true }; k += dir }
        let next = mod(time + n - from, 1440)
        hand = n
        time = next
        // Passing midnight or noon also turns the 24-hour wheel, so its flag drops with a firmer clack.
        if (before < 720) != (next < 720) { Feedback.shared.play(.flag, sound: sound) }
        else { Feedback.shared.play(five ? .five : .minute, sound: sound) }
    }

    private func flip() {
        time = mod(time + 720, 1440)
        Feedback.shared.play(.latch, sound: sound)
    }

    private var spoken: String {
        let h = mod(time / 60, 12) == 0 ? 12 : mod(time / 60, 12)
        return String(format: "%d:%02d %@", h, time % 60, pm ? "PM" : "AM")
    }
}

private func mod(_ n: Int, _ m: Int) -> Int { ((n % m) + m) % m }

/// The look, as tokens. Light from above; every highlight belongs to the room, never to a moving part.
private struct Palette {
    let dark: Bool
    private func w(_ v: Double, _ a: Double = 1) -> Color { Color(white: v, opacity: a) }
    var tileTop: Color { dark ? w(0.18) : w(0.99) }
    var tileBottom: Color { dark ? w(0.1) : w(0.89) }
    var sheen: Color { dark ? w(1, 0.04) : w(1, 0.55) }
    var rim: Color { dark ? w(1, 0.12) : w(1) }
    var contact: Color { .black.opacity(dark ? 0.6 : 0.15) }
    var cast: Color { .black.opacity(dark ? 0.6 : 0.22) }
    var ray: Color { dark ? w(1, 0.045) : w(0, 0.05) }
    var minute: Color { dark ? w(0.37) : w(0.65) }
    var index: Color { dark ? w(0.28) : w(0.79) }
    var number: Color { dark ? w(0.44) : w(0.6) }
    var hand: Color { dark ? w(0.24) : w(1) }
    var handEdge: Color { dark ? w(0.08) : w(0.76) }
    var capEdge: Color { dark ? w(0.35) : w(0.81) }
    var drop: Double { dark ? 0.55 : 0.22 }
    var glow: Double { dark ? 0.5 : 0 }     // luminous paint only shows its glow once the room is dark
    var chip: Color { dark ? Color(red: 0.23, green: 0.23, blue: 0.25).opacity(0.6) : w(1, 0.65) }
    var chipShadow: Double { dark ? 0.4 : 0.1 }
    var dim: Color { dark ? w(0.53) : w(0.56) }
    var ink: Color { dark ? w(0.95) : w(0.11) }
    var ledOff: Color { dark ? w(1, 0.08) : w(0, 0.1) }
}

/// The printed face: faint rays, minute marks, numerals, and the hour indices: an applied frame filled with luminous paint.
private struct Face: View {
    let u: CGFloat
    let lume: Color
    let p: Palette
    var body: some View {
        ZStack {
            Canvas { ctx, size in
                ctx.translateBy(x: size.width / 2, y: size.height / 2)
                for i in stride(from: 0, to: 60, by: 5) {
                    var c = ctx
                    c.rotate(by: .degrees(Double(i) * 6))
                    c.stroke(line(-78.5, -67.5), with: .color(lume), style: StrokeStyle(lineWidth: 4 * u, lineCap: .round))
                }
            }
            .blur(radius: 1.6 * u)
            .opacity(p.glow)
            Canvas { ctx, size in
                ctx.translateBy(x: size.width / 2, y: size.height / 2)
                for h in 0..<12 {
                    var c = ctx
                    c.rotate(by: .degrees(Double(h) * 30))
                    c.stroke(line(0, -66), with: .color(p.ray), lineWidth: 0.6 * u)
                }
                for i in 0..<60 {
                    var c = ctx
                    c.rotate(by: .degrees(Double(i) * 6))
                    if i % 5 != 0 {
                        c.stroke(line(-78, -71), with: .color(p.minute), style: StrokeStyle(lineWidth: 1.5 * u, lineCap: .round))
                    } else {
                        c.stroke(line(-80, -66), with: .color(p.index), style: StrokeStyle(lineWidth: 5 * u, lineCap: .round))
                        c.stroke(line(-78.5, -67.5), with: .color(lume), style: StrokeStyle(lineWidth: 2 * u, lineCap: .round))
                    }
                }
                for h in 1...12 {
                    var c = ctx
                    c.rotate(by: .degrees(Double(h) * 30))
                    c.draw(Text("\(h)").font(.system(size: 10 * u, design: .monospaced)).foregroundStyle(p.number),
                           at: CGPoint(x: 0, y: -89.5 * u))
                }
            }
        }
    }
    private func line(_ y1: CGFloat, _ y2: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: y1 * u))
        path.addLine(to: CGPoint(x: 0, y: y2 * u))
        return path
    }
}

/// A hand pointing at 12, drawn in the 200-unit face space: a pale body with a darker edge, and an optional lume strip.
private struct Hand: View {
    let u: CGFloat
    let from: CGFloat, to: CGFloat, edge: CGFloat, fill: CGFloat
    let lume: Color?
    let p: Palette
    var body: some View {
        ZStack {
            Canvas { ctx, size in
                let x = size.width / 2
                func seg(_ a: CGFloat, _ b: CGFloat) -> Path {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: a * u)); path.addLine(to: CGPoint(x: x, y: b * u))
                    return path
                }
                ctx.stroke(seg(from, to), with: .color(p.handEdge), style: StrokeStyle(lineWidth: edge * u, lineCap: .round))
                ctx.stroke(seg(from, to), with: .color(p.hand), style: StrokeStyle(lineWidth: fill * u, lineCap: .round))
                if let lume {
                    ctx.drawLayer { glow in
                        glow.opacity = p.glow
                        glow.addFilter(.blur(radius: 1.6 * u))
                        glow.stroke(seg(72, 48), with: .color(lume), style: StrokeStyle(lineWidth: 4 * u, lineCap: .round))
                    }
                    ctx.stroke(seg(72, 48), with: .color(lume), style: StrokeStyle(lineWidth: 2 * u, lineCap: .round))
                }
            }
        }
    }
}

/// Haptics paired with each sound: a light tick per minute, firmer every five, a firm clack when the day half turns.
@MainActor private final class Feedback {
    static let shared = Feedback()
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let synth = ClickSynth()

    func prepare() { rigid.prepare() }
    func play(_ voice: ClickSynth.Voice, sound: Bool) {
        let strength: [ClickSynth.Voice: CGFloat] = [.minute: 0.4, .five: 0.65, .flag: 0.9, .latch: 0.8]
        rigid.impactOccurred(intensity: strength[voice] ?? 0.5)
        rigid.prepare()
        if sound { synth.play(voice) }
    }
}

/// Small hard parts can't make a pitched thump: they ring for a millisecond or two at a few high body modes.
private final class ClickSynth {
    enum Voice: CaseIterable { case minute, five, flag, latch }
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
        let ticks: [(Float, Float, Float)]
        switch voice {
        case .minute: ticks = [(0, 0.05, 1.35)]                          // the jumper dropping into a minute
        case .five: ticks = [(0, 0.07, 1.2)]                             // a deeper notch every five minutes
        case .flag: ticks = [(0, 0.12, 0.95), (0.006, 0.035, 1.25)]      // the 24-hour wheel's flag drops, then settles
        case .latch: ticks = [(0, 0.07, 1.08), (0.009, 0.16, 1)]         // the push button's latch lets go, then lands
        }
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
        @State private var morning = 4 * 60 + 45
        @State private var afternoon = 13 * 60 + 32
        var body: some View {
            VStack(spacing: 32) {
                ClockDial(time: $morning, tone: .light)
                ClockDial(time: $afternoon, tone: .dark)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: 0.5))
        }
    }
    return Demo()
}
