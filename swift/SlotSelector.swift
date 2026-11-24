// SlotSelector.swift — Detent
// A vertical slide selector switch. A plastic cap rides over a slot with a spring detent at each position:
// push and it gives a little, then snaps over center into the next one with a click, and stops hard at both
// ends. The labels are printed on the panel; a small LED beside each one shows the selected position.
// Options run from the bottom up. Follows the color scheme. Haptics and sound are built in. iOS / iPadOS 17+.
//
// Usage:
//   @State private var mode = 1
//   SlotSelector(selection: $mode, options: ["opt a", "opt b", "opt c", "opt d"], label: "mode")
//   SlotSelector(selection: $gain, options: ["low", "high"], label: "gain", led: .orange)
//       .environment(\.colorScheme, .dark)   // force a tone

import SwiftUI
import UIKit
import AVFoundation

public struct SlotSelector: View {
    @Binding private var selection: Int         // 0 = bottom
    private let options: [String]
    private let label: String
    private let row: CGFloat
    private let led: Color
    private let sound: Bool

    public init(selection: Binding<Int>,
                options: [String] = ["opt a", "opt b", "opt c", "opt d"],
                label: String = "mode",
                row: CGFloat = 38,
                led: Color = Color(red: 1, green: 0.23, blue: 0.18),
                sound: Bool = true) {
        _selection = selection
        self.options = options.count < 2 ? ["off", "on"] : options
        self.label = label
        self.row = row
        self.led = led
        self.sound = sound
    }

    @State private var acc: CGFloat = 0         // points pushed past the current position (up is +)
    @State private var pushDir: CGFloat = 0
    @State private var lastY: CGFloat?
    @State private var pressed = false
    @State private var atEdge = 0
    @State private var travel: Task<Void, Never>?
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var n: Int { options.count }
    private var index: Int { min(n - 1, max(0, selection)) }
    private var dark: Bool { scheme == .dark }
    // After a snap the cap is ahead of the finger, so it only shows give while it's actually being pushed.
    private var give: CGFloat { acc.sign == pushDir.sign && pushDir != 0 ? acc * 0.25 : 0 }
    private func centerY(_ i: Int) -> CGFloat { (CGFloat(n - i) - 0.5) * row }
    // Over center, the detent spring throws the cap: it accelerates and stops dead. No overshoot.
    private var snap: Animation? { reduceMotion ? nil : .timingCurve(0.55, 0, 1, 1, duration: 0.07) }

    // Printed ink, and the parts' own colors. A dark panel gets a pale cap with a groove; a light one a black cap.
    private var ink: Color { dark ? Color(white: 0.43) : Color(red: 0.47, green: 0.47, blue: 0.44) }
    private var head: Color { dark ? Color(white: 0.9) : Color(white: 0.11) }

    public var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                Rectangle().fill(ink).frame(width: 28, height: 1.5).frame(width: 52)
                Text("\(label) [\(n)]").foregroundStyle(head).padding(.leading, 18)
            }
            GridRow(alignment: .top) {
                track
                VStack(alignment: .leading, spacing: 0) {
                    ForEach((0..<n).reversed(), id: \.self) { i in
                        HStack(spacing: 12) {
                            lamp(on: i == index)
                            Text(options[i]).foregroundStyle(ink)
                        }
                        .frame(height: row)
                        .contentShape(Rectangle())
                        .onTapGesture { move(to: i) }
                    }
                }
            }
        }
        .font(.system(size: 17))
        .focusable()
        .focused($focused)
        .onKeyPress(keys: [.upArrow, .rightArrow, .downArrow, .leftArrow]) { press in
            nudge(press.key == .upArrow || press.key == .rightArrow ? 1 : -1)
            return .handled
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(options[index])
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudge(1)
            case .decrement: nudge(-1)
            @unknown default: break
            }
        }
    }

    private var track: some View {
        ZStack(alignment: .top) {
            // The slot: shaded under its upper wall, light catching its lower lip.
            RoundedRectangle(cornerRadius: 4)
                .fill(dark ? Color(white: 0.01) : Color(red: 0.2, green: 0.2, blue: 0.18))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.black.opacity(dark ? 1 : 0.7), lineWidth: 2)
                    .blur(radius: 1.2).offset(y: 1.5).clipShape(RoundedRectangle(cornerRadius: 4)))
                .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(dark ? 0.09 : 0.9)).offset(y: 1))
                .frame(width: 8, height: CGFloat(n - 1) * row + 14)
                .offset(y: row / 2 - 7)
            cap
                .offset(y: centerY(index) - give - 11)
        }
        .frame(width: 52, height: CGFloat(n) * row, alignment: .top)
        .contentShape(Rectangle())
        .gesture(dragGesture)
    }

    // The cap rides on the panel over the slot, lit from above, with a contact shadow below. It never lifts.
    private var cap: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(LinearGradient(colors: dark ? [Color(white: 0.945), Color(white: 0.835)] : [Color(white: 0.172), Color(white: 0.083)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(dark ? 1 : 0.12), lineWidth: 1)
                .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.15))))
            .overlay(
                // Dark: a molded groove, its lower wall catching the light. Light: a painted line.
                Capsule().fill(dark ? Color(white: 0.11) : Color(white: 0.95))
                    .frame(width: 40 * 0.56, height: 2)
                    .background(Capsule().fill(.white.opacity(dark ? 0.7 : 0)).offset(y: 0.5))
            )
            .frame(width: 40, height: 22)
            .shadow(color: .black.opacity(0.35), radius: 0.3)
            .shadow(color: .black.opacity(dark ? 0.7 : 0.35), radius: pressed ? 0.5 : 0.75, y: pressed ? 0.5 : 1)
            .shadow(color: .black.opacity(dark ? 0.7 : 0.35), radius: pressed ? 1.5 : 2.5, y: pressed ? 1 : 2.5)
            .scaleEffect(pressed ? 0.994 : 1)        // a finger presses it in a hair; it never lifts
            .offset(y: pressed ? 0.5 : 0)
    }

    // An LED is its own light source: lit, it tints the panel around it a touch. Unlit, it's a dark lens.
    private func lamp(on: Bool) -> some View {
        ZStack {
            Circle().fill(on ? led : (dark ? Color(red: 0.08, green: 0.06, blue: 0.05) : Color(red: 0.35, green: 0.34, blue: 0.31)))
            Circle().fill(on ? AnyShapeStyle(RadialGradient(colors: [.white.opacity(0.55), .clear], center: UnitPoint(x: 0.5, y: 0.4),
                                                            startRadius: 0, endRadius: 2.5))
                             : AnyShapeStyle(led.opacity(dark ? 0.22 : 0.3)))
        }
            .overlay(Circle().strokeBorder(.white.opacity(on ? 0 : 0.18), lineWidth: 0.5)
                .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center)))
            .frame(width: 6, height: 6)
            .shadow(color: on ? led.opacity(dark ? 0.55 : 0.3) : .clear, radius: 3.5)
            // The LED switches the instant the contact makes. It doesn't fade.
            .transaction { $0.animation = nil }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if lastY == nil {
                    withAnimation(.easeOut(duration: 0.05)) { pressed = true }
                    acc = 0
                    Feedback.shared.prepare()
                    // Pressed in the slot beside the cap: it's pushed along to that position, detent by detent.
                    if abs(g.startLocation.y - centerY(index)) > 13 {
                        move(to: min(n - 1, max(0, n - 1 - Int(g.startLocation.y / row))))
                    }
                    lastY = g.location.y
                    return
                }
                let d = (lastY ?? g.location.y) - g.location.y   // up is +
                lastY = g.location.y
                if d != 0 && travel == nil { push(d) }
            }
            .onEnded { _ in
                lastY = nil
                // Let go between positions and the detent pulls the cap back into place.
                withAnimation(reduceMotion ? nil : .timingCurve(0.2, 0, 0.3, 1, duration: 0.08)) { pressed = false; acc = 0; pushDir = 0 }
            }
    }

    // It only gives a little until it passes halfway to the next position, then the detent throws it over.
    // At either end it sits on its stop and gives nothing at all.
    private func push(_ d: CGFloat) {
        pushDir = d < 0 ? -1 : 1
        acc += d
        if (index == 0 && acc < 0) || (index == n - 1 && acc > 0) {
            acc = 0
            hitStop(index + Int(pushDir))
            return
        }
        // Strictly past halfway: exactly halfway would leave it halfway behind the new position and throw it straight back.
        while abs(acc) > row / 2 {
            let dir = acc < 0 ? -1 : 1
            let next = index + dir
            if next < 0 || next >= n { acc = 0; break }
            acc -= CGFloat(dir) * row
            set(next)
        }
    }

    private func nudge(_ dir: Int) {
        let next = index + dir
        if next < 0 || next >= n { hitStop(next); return }
        set(next)
    }

    // Moved from a distance (a tapped label, a press in the slot), the cap crosses each detent in turn.
    private func move(to target: Int) {
        travel?.cancel()
        travel = Task { @MainActor in
            while index != target && !Task.isCancelled {
                set(index + (target > index ? 1 : -1))
                try? await Task.sleep(for: .milliseconds(70))
            }
            travel = nil
        }
    }

    private func set(_ next: Int) {
        guard next != index, next >= 0, next < n else { return }
        withAnimation(snap) { selection = next }
        Feedback.shared.click(sound: sound)
        if (atEdge < 0 && next > 0) || (atEdge > 0 && next < n - 1) { atEdge = 0 }
        // Arriving at an end, the cap lands on its stop.
        if next == 0 || next == n - 1 { hitStop(next == 0 ? -1 : n) }
    }

    // End stops sound once on arrival and stay silent while you keep pushing.
    private func hitStop(_ next: Int) {
        let side = next < 0 ? -1 : 1
        guard atEdge != side else { return }
        atEdge = side
        Feedback.shared.stop(sound: sound)
    }
}

/// A firm haptic per position, like the detent spring snapping over. Nothing on touch-down.
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
/// A selector makes two: the detent dropping into place, then the contact settling.
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
        @State private var mode = 1
        @State private var gain = 1
        var body: some View {
            VStack(spacing: 0) {
                SlotSelector(selection: $mode, options: ["opt a", "opt b", "opt c", "opt d"], label: "mode")
                    .padding(40).frame(maxWidth: .infinity)
                    .background(Color(red: 0.94, green: 0.94, blue: 0.93))
                    .environment(\.colorScheme, .light)
                SlotSelector(selection: $gain, options: ["low", "high"], label: "gain")
                    .padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(white: 0.04))
                    .environment(\.colorScheme, .dark)
            }
        }
    }
    return Demo()
}
