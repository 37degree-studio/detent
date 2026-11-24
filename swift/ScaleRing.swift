// ScaleRing.swift — Detent
// A rotating bezel with a dB scale and a level scale, read against a fixed index line. It ratchets: the
// ring gives a little, then clicks into each of its 20 positions, and turns endlessly. oneWay makes it a
// dive bezel: counterclockwise only, the ratchet blocks the other way. weighted makes the ring heavy: flick it and
// it carries on 2 to 4 clicks after you let go, easing down over most of a second until it rests in the last notch. The readout is an LED display: digits switch instantly. iOS / iPadOS 17+.
// The readout uses a monospaced system font; add the Doto font to your app and pass readoutFont for the dot-matrix look.
//
// Usage:
//   @State private var step = 4          // 0...19; the dB value is -3 × step
//   ScaleRing(step: $step)
//   ScaleRing(step: $step, size: 260, oneWay: true)
//   ScaleRing(step: $step, weighted: true)

import SwiftUI
import UIKit
import AVFoundation

public struct ScaleRing: View {
    @Binding private var step: Int
    private let size: CGFloat
    private let marker: Color
    private let oneWay: Bool
    private let weighted: Bool
    private let sound: Bool
    private let readoutFont: Font?

    public init(step: Binding<Int>,
                size: CGFloat = 300,
                marker: Color = Color(red: 0.9, green: 0.14, blue: 0.16),
                oneWay: Bool = false,
                weighted: Bool = false,
                sound: Bool = true,
                readoutFont: Font? = nil) {
        _step = step
        self.size = size
        self.marker = marker
        self.oneWay = oneWay
        self.weighted = weighted
        self.sound = sound
        self.readoutFont = readoutFont
    }

    @State private var turns: Int = 0           // total clicks since appearing, so the ring never spins back the long way
    @State private var acc: Double = 0          // degrees pushed past the current click
    @State private var pushDir: Double = 0
    @State private var lastAngle: Double?
    @State private var trail: [(Double, Double)] = []     // (ms, cumulative degrees) over the last 80ms, for fling speed
    @State private var coastAngle: Double?                // the ring's free angle while it spins on its own
    @State private var coastTask: Task<Void, Never>?
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var give: Double { pushDir != 0 && acc.sign == pushDir.sign ? acc * 0.25 : 0 }
    private var ringAngle: Double { coastAngle ?? -18 * Double(turns) + give }
    private var dB: Int { -3 * step }
    // The ratchet spring throws the ring into each position: it accelerates and stops dead.
    private var snap: Animation? { reduceMotion ? nil : .timingCurve(0.55, 0, 1, 1, duration: 0.06) }

    public var body: some View {
        ZStack {
            RingFace(marker: marker)
                .rotationEffect(.degrees(ringAngle))
            Index()
            VStack(spacing: size * 0.01) {
                Text(step == 0 ? "0" : "\(dB)")
                    .font(readoutFont ?? .system(size: size * 0.15, weight: .heavy, design: .monospaced))
                    .contentTransition(.identity)          // an LED display: digits switch, they don't roll
                    .foregroundStyle(Color(white: 0.94))
                Text("dB · lvl \(String(format: "%02d", (100 - step * 5) % 100))")
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Color(white: 0.54))
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(turnGesture)
        .onAppear { turns = step }
        .focusable()
        .focused($focused)
        .onKeyPress(keys: [.upArrow, .rightArrow, .downArrow, .leftArrow]) { press in
            nudge(press.key == .upArrow || press.key == .rightArrow ? 1 : -1)
            return .handled
        }
        .accessibilityElement()
        .accessibilityLabel("Level")
        .accessibilityValue("\(dB) decibels")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudge(1)
            case .decrement: nudge(-1)
            @unknown default: break
            }
        }
    }

    private var turnGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let dx = g.location.x - size / 2, dy = g.location.y - size / 2
                guard hypot(dx, dy) > 8 else { return }
                let a = atan2(dy, dx) * 180 / .pi
                if lastAngle == nil { catchRing(); acc = 0; trail = []; Feedback.shared.prepare() }
                if let last = lastAngle {
                    var d = a - last
                    if d > 180 { d -= 360 } else if d < -180 { d += 360 }
                    let now = Date.timeIntervalSinceReferenceDate * 1000
                    trail.append((now, (trail.last?.1 ?? 0) + d))
                    while trail.count > 2, let first = trail.first, now - first.0 > 80 { trail.removeFirst() }
                    push(d)
                }
                lastAngle = a
            }
            .onEnded { _ in
                lastAngle = nil
                if weighted, !reduceMotion, fling() { return }
                // The ratchet pulls the ring back into its last click.
                withAnimation(reduceMotion ? nil : .timingCurve(0.2, 0, 0.3, 1, duration: 0.08)) { acc = 0; pushDir = 0 }
            }
    }

    // d: degrees the finger moved the ring, clockwise positive.
    private func push(_ d: Double) {
        pushDir = d < 0 ? -1 : 1
        acc += d
        if oneWay && acc > 0 { acc = 0 }           // the ratchet blocks clockwise: no give at all
        while abs(acc) > 9 {
            let dir = acc < 0 ? -1.0 : 1.0
            acc -= dir * 18
            click(dir < 0 ? 1 : -1)
        }
    }

    // Weighted: release speed over the last 80ms, in degrees per millisecond. A slow or stopped release doesn't spin.
    private func fling() -> Bool {
        let now = Date.timeIntervalSinceReferenceDate * 1000
        guard trail.count >= 2, let first = trail.first, let last = trail.last, now - last.0 < 60 else { return false }
        let v = (last.1 - first.1) / max(1, last.0 - first.0)
        guard abs(v) >= 0.3, !(oneWay && v > 0) else { return false }
        coast(from: ringAngle, speed: max(-2.5, min(2.5, v)))
        return true
    }

    // The ring is heavy, so a flick carries it on after you let go: 2 more clicks for a gentle flick, up to 4 for a
    // hard one. It leaves your finger at the flick's speed, drag bleeds that down to a slow creep within a few degrees,
    // and friction then eases it to rest in the last notch over most of a second. So the clicks start quick and spread
    // out, the last gap the longest.
    // The whole coast is worked out at release, and its clicks are rendered as one sample-accurate audio track.
    static func spin(from start: Double, speed v: Double) -> (path: [Double], clicks: [(ms: Double, turns: Int)], end: Double) {
        let dir: Double = v < 0 ? -1 : 1
        let fast = min(1, max(0, (abs(v) - 0.3) / 1.7))
        let n = 2 + Int((fast * 2).rounded())                       // 2, 3 or 4 clicks
        let home = -18 * (-start / 18).rounded(), rest = home + dir * 18 * Double(n), dist = abs(rest - start)
        let creep = 2 * dist / (500 + 150 * Double(n))              // the slow pace it eases down to, degrees per ms
        // speed by distance travelled: the flick, bled off by drag, times the friction curve that stops it in the notch
        func speed(_ x: Double) -> Double {
            (creep + max(0, abs(v) - creep) * exp(-x / 4)) * max(0, 1 - x / dist).squareRoot()
        }
        var pos = start, x = 0.0, t = 0.0
        var click = Int((-pos / 18).rounded())
        var path = [pos], clicks: [(ms: Double, turns: Int)] = []
        while dist - x > 0.02 && t < 4000 {
            let prev = pos
            x = min(dist, x + max(speed(x), 0.004))
            pos = start + dir * x
            t += 1
            let k = Int((-pos / 18).rounded())
            if k != click {
                let top = -18 * (Double(min(k, click)) + 0.5)          // the hilltop between the two notches
                clicks.append((ms: t - 1 + (top - prev) / (pos - prev), turns: k))
                click = k
            }
            path.append(pos)
        }
        path[path.count - 1] = rest
        return (path, clicks, t)
    }

    private func coast(from start: Double, speed: Double) {
        acc = 0
        pushDir = 0
        coastAngle = start
        coastTask?.cancel()
        let spin = Self.spin(from: start, speed: speed)
        Feedback.shared.spin(at: spin.clicks.map(\.ms), sound: sound)
        coastTask = Task { @MainActor in
            let t0 = Date.timeIntervalSinceReferenceDate
            var done = 0
            while !Task.isCancelled {
                let t = (Date.timeIntervalSinceReferenceDate - t0) * 1000
                while done < spin.clicks.count, spin.clicks[done].ms <= t {
                    let k = spin.clicks[done].turns
                    turns = k
                    step = ((k % 20) + 20) % 20
                    Feedback.shared.tap()
                    done += 1
                }
                if t >= spin.end { break }
                let i = min(spin.path.count - 2, Int(t)), f = t - Double(i)
                coastAngle = spin.path[i] + (spin.path[i + 1] - spin.path[i]) * f
                try? await Task.sleep(for: .milliseconds(4))
            }
            guard !Task.isCancelled else { return }
            coastAngle = nil
            coastTask = nil
        }
    }

    // A finger on a spinning ring stops it: its click track is cut off and it settles into the nearest notch.
    private func catchRing() {
        guard coastTask != nil else { return }
        coastTask?.cancel()
        coastTask = nil
        Feedback.shared.cancelSpin()
        if let at = coastAngle { turns = Int((-at / 18).rounded()); step = ((turns % 20) + 20) % 20 }
        withAnimation(.timingCurve(0.2, 0, 0.3, 1, duration: 0.08)) { coastAngle = nil }
    }

    // n = +1 is one click counterclockwise, which brings the next mark under the index.
    private func nudge(_ n: Int) {
        if oneWay && n < 0 { return }
        click(n)
    }

    private func click(_ n: Int) {
        withAnimation(snap) {
            turns += n
            step = ((step + n) % 20 + 20) % 20
        }
        Feedback.shared.click(sound: sound)
    }
}

/// The ring itself: serrated grip, printed dB and level scales, and the marker ticks. It all turns together.
private struct RingFace: View {
    let marker: Color
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 320       // drawn on a 320-unit grid
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            func radial(_ angle: Double, _ r1: CGFloat, _ r2: CGFloat) -> Path {
                let a = (angle - 90) * .pi / 180
                var p = Path()
                p.move(to: CGPoint(x: c.x + cos(a) * r1 * s, y: c.y + sin(a) * r1 * s))
                p.addLine(to: CGPoint(x: c.x + cos(a) * r2 * s, y: c.y + sin(a) * r2 * s))
                return p
            }
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 141 * s, y: c.y - 141 * s, width: 282 * s, height: 282 * s)),
                       with: .color(Color(white: 0.23)), lineWidth: 1.2 * s)
            // The serrated outer edge: the coin-edge grip real bezels have.
            for i in 0..<120 { ctx.stroke(radial(Double(i) * 3, 141, 147), with: .color(Color(white: 0.18)), lineWidth: 1.4 * s) }
            for k in [3, 7, 14] {
                ctx.stroke(radial(Double(k) * 18 - 9, 125, 133), with: .color(marker), style: StrokeStyle(lineWidth: 2.4 * s, lineCap: .round))
            }
            for k in 0..<20 {
                let outer = k == 0 ? "0 dB" : "−" + String(format: "%02d", k * 3)
                let inner = String(format: "%02d", (100 - k * 5) % 100)
                for (label, r, shade) in [(outer, 110.0, 0.84), (inner, 82.0, 0.66)] {
                    var t = ctx
                    t.translateBy(x: c.x, y: c.y)
                    t.rotate(by: .degrees(Double(k) * 18))
                    t.draw(Text(label).font(.system(size: 12.5 * s, design: .monospaced)).foregroundStyle(Color(white: shade)),
                           at: CGPoint(x: 0, y: -r * s))
                }
            }
        }
    }
}

/// The fixed index lines: one above the ring, one inside it.
private struct Index: View {
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 320
            let x = size.width / 2
            for (y1, y2) in [(0.0, 10.0), (92.0, 102.0)] {
                var p = Path()
                p.move(to: CGPoint(x: x, y: y1 * s))
                p.addLine(to: CGPoint(x: x, y: y2 * s))
                ctx.stroke(p, with: .color(Color(white: 0.92)), lineWidth: 1.6 * s)
            }
        }
        .allowsHitTesting(false)
    }
}

/// One light, crisp haptic per click.
@MainActor private final class Feedback {
    static let shared = Feedback()
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let synth = ClickSynth()

    func prepare() { rigid.prepare() }
    func tap() {
        rigid.impactOccurred(intensity: 0.55)
        rigid.prepare()
    }
    func click(sound: Bool) {
        tap()
        if sound { synth.play() }
    }
    func spin(at ms: [Double], sound: Bool) { if sound { synth.playTrack(at: ms) } }
    func cancelSpin() { synth.stop() }
}

/// A bezel ratchet click: small metal parts ringing for a millisecond or two at a few high body modes.
private final class ClickSynth {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private var tick: [Float] = []
    private var ready = false

    init() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else { return }
        self.format = format
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        tick = Self.renderTick(rate: Float(format.sampleRate))
        // Ambient: respects the silent switch and mixes with the user's music.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        ready = (try? engine.start()) != nil
    }

    func play() { playTrack(at: [0]) }

    /// Mixes one click at each time (ms from now) into a single buffer, so their spacing is exact to the sample.
    func playTrack(at ms: [Double]) {
        guard ready, let format, let lastMs = ms.max() else { return }
        let rate = format.sampleRate
        let frames = AVAudioFrameCount(rate * (lastMs / 1000 + 0.03))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let out = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = frames
        for i in 0..<Int(frames) { out[i] = 0 }
        for m in ms {
            let start = Int(m / 1000 * rate)
            for j in 0..<tick.count where start + j < Int(frames) { out[start + j] += tick[j] }
        }
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    func stop() { player.stop() }

    private static let modes: [(Float, Float, Float)] = [(1900, 0.0024, 1), (3400, 0.0015, 0.55), (6100, 0.0008, 0.3)]

    private static func renderTick(rate: Float) -> [Float] {
        let (level, tune): (Float, Float) = (0.07, 1.6)
        return (0..<Int(rate * 0.02)).map { i in
            let t = Float(i) / rate
            var tick: Float = 0
            for (hz, decay, gain) in modes { tick += gain * sinf(2 * .pi * hz * tune * t) * expf(-t / decay) }
            tick += Float.random(in: -1...1) * 0.5 * expf(-t / 0.0003)
            return tick * level * 2.2
        }
    }
}

#Preview {
    struct Demo: View {
        @State private var step = 4
        var body: some View {
            ScaleRing(step: $step, weighted: true)
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(white: 0.04))
        }
    }
    return Demo()
}
