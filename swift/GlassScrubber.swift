// GlassScrubber.swift — Detent
// A glass lens on a carriage that slides along a printed 24-hour scale. The lens really magnifies the scale under it, and the
// hairline engraved in it reads the time. The carriage clicks into a detent every 15 minutes (step: 5, 15, 30 or 60), clicks
// firmer on each hour, and stops hard at 00:00 and at the last detent. weighted (the default) lets a flick carry it on 2 to 4
// clicks, easing to rest over most of a second. The readout on the carriage is digital: digits switch instantly. The sky above
// follows the time on its own: the sun and the moon ride one arc, the sky brightens only as the sun clears the
// horizon, and the stars fade out one by one, faintest first. Light or dark follows the color scheme, or pass tone. iOS / iPadOS 17+.
//
// Usage:
//   @State private var minutes = 420          // 07:00, minutes since midnight
//   GlassScrubber(minutes: $minutes, label: "Eastern Time")
//   GlassScrubber(minutes: $minutes, step: 5, weighted: false, tone: .dark)

import SwiftUI
import UIKit
import AVFoundation

public struct GlassScrubber: View {
    @Binding private var minutes: Int
    private let label: String
    private let step: Int
    private let weighted: Bool
    private let tone: ColorScheme?
    private let line: Color
    private let sound: Bool

    public init(minutes: Binding<Int>,
                label: String = "Local time",
                step: Int = 15,
                weighted: Bool = true,
                tone: ColorScheme? = nil,
                line: Color = Color(red: 0.9, green: 0.14, blue: 0.16),
                sound: Bool = true) {
        _minutes = minutes
        self.label = label
        self.step = [5, 15, 30, 60].contains(step) ? step : 15
        self.weighted = weighted
        self.tone = tone
        self.line = line
        self.sound = sound
    }

    @State private var raw: Double?                        // where the finger has pushed the carriage, in minutes
    @State private var dragFrom: Int?
    @State private var trail: [(Double, Double)] = []      // (ms, raw minutes) over the last 80ms, for fling speed
    @State private var coastAt: Double?                    // the carriage's free position while it coasts, in minutes
    @State private var coastTask: Task<Void, Never>?
    @State private var atEdge = 0
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var maxMinutes: Int { 1440 - step }
    private var value: Int { min(maxMinutes, max(0, minutes / step * step)) }
    // The carriage sits in its notch and leans a little toward the finger.
    private var shown: Double { coastAt ?? Double(value) + ((raw ?? Double(value)) - Double(value)) * 0.25 }
    private var palette: ScrubberPalette { (tone ?? scheme) == .dark ? .dark : .light }
    // The detent throws the carriage into each notch: it accelerates and stops dead.
    private var snap: Animation? { reduceMotion ? nil : .timingCurve(0.55, 0, 1, 1, duration: 0.06) }
    private var back: Animation? { reduceMotion ? nil : .timingCurve(0.2, 0, 0.3, 1, duration: 0.08) }

    public var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                // The sky is a window onto the time of day, not part of the mechanism: it glides to the time you set,
                // easing in without overshoot, so the sun and moon move smoothly while the carriage clicks.
                ScrubberSky(minutes: shown, width: geo.size.width)
                    .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0), value: shown)
            }
            .frame(height: 160)
            .overlay(alignment: .bottom) { Rectangle().fill(palette.edge).frame(height: 1) }
            GeometryReader { geo in
                let w = geo.size.width, x = carriageX(w)
                ZStack(alignment: .topLeading) {
                    // The digital readout rides on the carriage, right above the lens.
                    Text(Self.format(value))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .contentTransition(.identity)
                        .foregroundStyle(palette.chipInk)
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(palette.chip)
                            .shadow(color: palette.drop, radius: 1, y: 1)
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(palette.rim, lineWidth: 0.5)))
                        .fixedSize()
                        .position(x: x, y: 13)
                    ScrubberScale(width: w, maxMinutes: maxMinutes, palette: palette)
                        .frame(width: w, height: 60)
                        .offset(y: 32)
                    ScrubberLens(x: x, width: w, maxMinutes: maxMinutes, palette: palette, line: line, pressed: dragFrom != nil)
                        .offset(x: x - 15, y: 39)
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(width: w))
            }
            .frame(height: 92)
            .padding(.horizontal, 40)
            .padding(.top, 12)
            Text(label.uppercased())
                .font(.system(size: 11, weight: .medium))
                .tracking(1.5)
                .foregroundStyle(palette.label)
                .padding(.top, 12)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: 400)
        .background(palette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(palette.edge, lineWidth: 1))
        .shadow(color: .black.opacity(palette.isDark ? 0 : 0.12), radius: 14, y: 8)
        .focusable()
        .focused($focused)
        .onKeyPress(keys: [.upArrow, .rightArrow, .downArrow, .leftArrow]) { press in
            nudge(press.key == .upArrow || press.key == .rightArrow ? 1 : -1)
            return .handled
        }
        .accessibilityElement()
        .accessibilityLabel("Time")
        .accessibilityValue(Self.format(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudge(1)
            case .decrement: nudge(-1)
            @unknown default: break
            }
        }
    }

    private func carriageX(_ w: CGFloat) -> CGFloat { CGFloat(shown / Double(maxMinutes)) * w }

    static func format(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }

    private func dragGesture(width w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if dragFrom == nil {
                    catchCarriage()
                    dragFrom = value
                    trail = []
                    ScrubberFeedback.shared.prepare()
                }
                // You push the carriage: it moves exactly as far as your finger, wherever you grabbed the track.
                let r = min(Double(maxMinutes), max(0, Double(dragFrom ?? value) + Double(g.translation.width / max(1, w)) * Double(maxMinutes)))
                let now = Date.timeIntervalSinceReferenceDate * 1000
                trail.append((now, r))
                while trail.count > 2, let first = trail.first, now - first.0 > 80 { trail.removeFirst() }
                raw = r
                let v = Int((r / Double(step)).rounded()) * step
                if v != value { withAnimation(snap) { commit(v, sound: true) } }
            }
            .onEnded { _ in
                dragFrom = nil
                if weighted, !reduceMotion, fling(width: w) { return }
                // The detent pulls it back into the notch it's in.
                withAnimation(back) { raw = nil }
            }
    }

    // A quarter-hour notch is one tiny dry tick; any move that lands on or passes an hour is a firmer one. The stops tick once, duller.
    private func commit(_ v: Int, sound detent: Bool) {
        let was = value
        minutes = v
        let edge = v <= 0 ? -1 : v >= maxMinutes ? 1 : 0
        if edge != 0 && atEdge != edge { ScrubberFeedback.shared.stop(sound: sound) }
        if edge != 0 { atEdge = edge }
        else if (atEdge < 0 && Double(v) > Double(maxMinutes) * 0.03) || (atEdge > 0 && Double(v) < Double(maxMinutes) * 0.97) { atEdge = 0 }
        if detent && edge == 0 {
            if Self.hour(from: was, to: v) { ScrubberFeedback.shared.hour(sound: sound) } else { ScrubberFeedback.shared.quarter(sound: sound) }
        }
    }

    static func hour(from a: Int, to b: Int) -> Bool {
        var h = Int((Double(min(a, b)) / 60).rounded(.up)) * 60
        while h <= max(a, b) { if h != a { return true }; h += 60 }
        return false
    }

    // Keys and VoiceOver: one notch. Pushing past an end stop does nothing at all.
    private func nudge(_ n: Int) {
        catchCarriage()
        let v = min(maxMinutes, max(0, value + n * step))
        guard v != value else { return }
        raw = nil
        withAnimation(snap) { commit(v, sound: true) }
    }

    // Weighted: release speed over the last 80ms. A slow or stopped release doesn't coast.
    private func fling(width w: CGFloat) -> Bool {
        let now = Date.timeIntervalSinceReferenceDate * 1000
        guard trail.count >= 2, let first = trail.first, let last = trail.last, now - last.0 < 60 else { return false }
        let v = (last.1 - first.1) / max(1, last.0 - first.0)                 // minutes per ms
        let px = abs(v / Double(maxMinutes) * Double(w))
        guard px >= 0.35 else { return false }
        let n = 2 + Int((min(1, (px - 0.35) / 2.2) * 2).rounded())
        let notches = Double(maxMinutes / step)
        guard let spin = Self.spin(from: shown / Double(step), speed: max(-0.2, min(0.2, v / Double(step))), clicks: n, lo: 0, hi: notches) else { return false }
        coast(spin)
        return true
    }

    // The carriage has some weight, so a flick carries it on after you let go: 2 more notches for a gentle flick, up to 4 for a
    // hard one. It leaves your finger at the flick's speed, drag bleeds that down to a slow creep within a fraction of a notch,
    // and friction then eases it to rest in the last notch over most of a second. So the clicks start quick and spread out, the
    // last gap the longest. If the end stop comes first, it hits it and stops dead. Positions are in notches; speed in notches per ms.
    // The whole coast is worked out at release, and its clicks are rendered as one sample-accurate audio track.
    struct Spin { var path: [Double]; var clicks: [(ms: Double, notch: Int, stop: Bool)]; var end: Double }

    static func spin(from start: Double, speed v: Double, clicks n: Int, lo: Double, hi: Double) -> Spin? {
        let dir: Double = v < 0 ? -1 : 1
        let home = start.rounded(), rest = home + dir * Double(n), dist = abs(rest - start)
        if min(hi, max(lo, rest)) == home { return nil }                 // already against the stop it was flicked toward
        let creep = 2 * dist / (500 + 150 * Double(n))
        func speed(_ x: Double) -> Double {
            (creep + max(0, abs(v) - creep) * exp(-x / 0.22)) * max(0, 1 - x / dist).squareRoot()
        }
        var pos = start, x = 0.0, t = 0.0, click = Int(home)
        var out = Spin(path: [start], clicks: [], end: 0)
        while dist - x > 0.001 && t < 4000 {
            let prev = pos
            x = min(dist, x + max(speed(x), 0.0002))
            pos = start + dir * x
            t += 1
            if pos <= lo || pos >= hi {                                       // the end stop: it arrives and stops dead
                let stop = pos <= lo ? lo : hi
                out.path.append(stop)
                out.clicks.append((ms: t - 1 + (stop - prev) / (pos - prev), notch: Int(stop), stop: true))
                out.end = t
                return out
            }
            let k = Int(pos.rounded())
            if k != click {
                // the click is the hilltop between notches
                if Double(k) > lo && Double(k) < hi { out.clicks.append((ms: t - 1 + (Double(min(k, click)) + 0.5 - prev) / (pos - prev), notch: k, stop: false)) }
                click = k
            }
            out.path.append(pos)
        }
        out.path[out.path.count - 1] = rest
        out.end = t
        return out
    }

    private func coast(_ spin: Spin) {
        raw = nil
        coastAt = shown
        coastTask?.cancel()
        let step = step
        ScrubberFeedback.shared.track(spin.clicks.filter { !$0.stop }.map { ($0.ms, $0.notch * step % 60 == 0) }, sound: sound)
        coastTask = Task { @MainActor in
            let t0 = Date.timeIntervalSinceReferenceDate
            var done = 0
            while !Task.isCancelled {
                let t = (Date.timeIntervalSinceReferenceDate - t0) * 1000
                while done < spin.clicks.count, spin.clicks[done].ms <= t {
                    let c = spin.clicks[done]
                    commit(c.notch * step, sound: false)       // the end stop's tick sounds as it arrives
                    if !c.stop { ScrubberFeedback.shared.tap(hour: c.notch * step % 60 == 0) }
                    done += 1
                }
                if t >= spin.end { break }
                let i = min(spin.path.count - 2, Int(t)), f = t - Double(i)
                coastAt = (spin.path[i] + (spin.path[i + 1] - spin.path[i]) * f) * Double(step)
                try? await Task.sleep(for: .milliseconds(4))
            }
            guard !Task.isCancelled else { return }
            coastAt = nil
            coastTask = nil
        }
    }

    // A finger on a coasting carriage stops it: its click track is cut off and it settles into the nearest notch.
    private func catchCarriage() {
        guard coastTask != nil else { return }
        coastTask?.cancel()
        coastTask = nil
        ScrubberFeedback.shared.cancelTrack()
        withAnimation(back) { coastAt = nil }
    }
}

/// Light and dark: a pale satin panel with the scale printed in ink, or a black anodized one printed in pale grey.
private struct ScrubberPalette {
    var panel, ink, ink2, label, edge, rim, drop, highlight, side, caustic, chip, chipInk: Color
    var isDark: Bool
    static let light = ScrubberPalette(panel: Color(red: 0.937, green: 0.933, blue: 0.949), ink: Color(red: 0.404, green: 0.4, blue: 0.435),
                                       ink2: Color(red: 0.69, green: 0.686, blue: 0.722), label: Color(red: 0.43, green: 0.427, blue: 0.467),
                                       edge: .black.opacity(0.11), rim: .black.opacity(0.16), drop: .black.opacity(0.25), highlight: .white.opacity(0.9),
                                       side: .black.opacity(0.1), caustic: .white.opacity(0.55),
                                       chip: Color(red: 0.984, green: 0.984, blue: 0.988), chipInk: Color(red: 0.17, green: 0.165, blue: 0.19), isDark: false)
    static let dark = ScrubberPalette(panel: Color(red: 0.067, green: 0.067, blue: 0.082), ink: Color(red: 0.62, green: 0.616, blue: 0.66),
                                      ink2: Color(red: 0.286, green: 0.282, blue: 0.322), label: Color(red: 0.557, green: 0.553, blue: 0.596),
                                      edge: .white.opacity(0.09), rim: .white.opacity(0.18), drop: .black.opacity(0.7), highlight: .white.opacity(0.32),
                                      side: .white.opacity(0.07), caustic: .white.opacity(0.09),
                                      chip: Color(red: 0.12, green: 0.12, blue: 0.145), chipInk: Color(red: 0.925, green: 0.92, blue: 0.94), isDark: true)
}

/// The printed scale: a mark every quarter hour, longer on the half hour and the hour.
/// Numbered every three hours, the six-hour marks bolder. Drawn on a 60pt-high strip whose marks sit on the line y = 26. The numbers sit below the lens's travel, so the glass never
/// cuts through them; the magnified copy inside the lens draws the marks only.
private func drawScrubberScale(_ ctx: GraphicsContext, width w: CGFloat, maxMinutes: Int, palette p: ScrubberPalette, lensAt: CGFloat? = nil) {
    // Through the lens: positions and lengths magnified 1.8× around the hairline, drawn with the same fine line so the lens doesn't shout.
    let z: CGFloat = lensAt == nil ? 1 : 1.8
    func X(_ x: CGFloat) -> CGFloat { lensAt.map { 15 + (x - $0) * z } ?? x }
    func Y(_ y: CGFloat) -> CGFloat { lensAt == nil ? y : 19 + (y - 26) * z }
    for m in stride(from: 0, through: maxMinutes, by: 15) {
        let x = X(CGFloat(m) / CGFloat(maxMinutes) * w)
        if lensAt != nil && (x < -2 || x > 32) { continue }
        let h: CGFloat = m % 60 == 0 ? 8 : m % 30 == 0 ? 5 : 3
        var path = Path()
        path.move(to: CGPoint(x: x, y: Y(26 - h)))
        path.addLine(to: CGPoint(x: x, y: Y(26 + h)))
        ctx.stroke(path, with: .color(m % 60 == 0 ? p.ink : p.ink2), lineWidth: m % 60 == 0 ? 1.4 : 1)
        if lensAt == nil && m % 180 == 0 {
            let big = m % 360 == 0
            ctx.draw(Text(String(format: "%02d", m / 60)).font(.system(size: 10, weight: big ? .semibold : .medium, design: .monospaced))
                        .foregroundStyle(big ? p.ink : p.ink2),
                     at: CGPoint(x: x, y: 51))
        }
    }
}

private struct ScrubberScale: View {
    let width: CGFloat, maxMinutes: Int, palette: ScrubberPalette
    var body: some View {
        Canvas { ctx, _ in drawScrubberScale(ctx, width: width, maxMinutes: maxMinutes, palette: palette) }
            .allowsHitTesting(false)
    }
}

/// The lens. Clear glass over the printed scale, so what you see through it is the scale itself, magnified 1.8×.
/// The room light is overhead: a soft highlight across the top of the glass, its edges bend light away and read darker,
/// it focuses a little brightness onto the panel under it, and it casts a short shadow straight down.
private struct ScrubberLens: View {
    let x: CGFloat, width: CGFloat, maxMinutes: Int, palette: ScrubberPalette, line: Color, pressed: Bool
    var body: some View {
        let p = palette
        ZStack {
            p.panel
            RadialGradient(colors: [p.caustic, .clear], center: UnitPoint(x: 0.5, y: 0.66), startRadius: 0, endRadius: 12)
            Canvas { ctx, _ in
                drawScrubberScale(ctx, width: width, maxMinutes: maxMinutes, palette: p, lensAt: x)   // the lens center sits over x
            }
            Rectangle().fill(line.opacity(0.9)).frame(width: 1).padding(.vertical, 4)  // the hairline engraved in the glass
            LinearGradient(stops: [.init(color: p.side, location: 0), .init(color: .clear, location: 0.24),
                                   .init(color: .clear, location: 0.76), .init(color: p.side, location: 1)], startPoint: .leading, endPoint: .trailing)
            EllipticalGradient(colors: [p.highlight, .clear], center: UnitPoint(x: 0.5, y: 0.08), startRadiusFraction: 0, endRadiusFraction: 0.32)
        }
        .frame(width: 30, height: 38)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(p.rim, lineWidth: 0.5))
        .shadow(color: p.drop, radius: pressed ? 0.5 : 0.8, y: pressed ? 0.5 : 1)
        .shadow(color: p.drop.opacity(0.6), radius: pressed ? 3 : 4.5, y: pressed ? 2 : 4)
        // Nothing moves on hover; a finger sinks the lens a hair.
        .scaleEffect(pressed ? 0.994 : 1)
        .offset(y: pressed ? 0.5 : 0)
        .animation(.linear(duration: 0.05), value: pressed)
        .allowsHitTesting(false)
    }
}

/// The sky. The sun and the moon ride opposite ends of one arc: the sun rises on the left at 06:00, is highest at noon and sets on
/// the right at 18:00; the moon does the same through the night. The sky's color comes from the sun's height alone, so there is
/// no light before it nears the horizon. Each star fades over its own stretch of twilight, faintest first. It is the only light
/// that changes; the panel is lit by the room. Animatable, so a change of time glides through every moment in between.
private struct ScrubberSky: View, Animatable {
    var minutes: Double
    let width: CGFloat
    nonisolated var animatableData: Double {
        get { minutes }
        set { minutes = newValue }
    }

    typealias RGB = (Double, Double, Double)
    // [x %, y %, brightness]. Brighter stars come out first at dusk and are the last to go at dawn.
    private static let stars: [(CGFloat, CGFloat, Double)] = [(5, 14, 1), (11, 40, 0.5), (16, 24, 0.75), (21, 60, 0.4), (27, 9, 0.6),
        (32, 36, 0.9), (37, 64, 0.45), (42, 20, 0.55), (47, 46, 0.7), (53, 10, 0.95), (57, 58, 0.4), (62, 30, 0.65), (67, 72, 0.5),
        (72, 16, 0.85), (77, 44, 0.45), (82, 26, 0.6), (86, 60, 0.8), (91, 12, 0.5), (95, 38, 0.7), (8, 76, 0.45), (30, 80, 0.5),
        (50, 82, 0.4), (70, 84, 0.55), (89, 80, 0.4)]
    // The sky by the sun's height (sine of its elevation): [height, zenith, middle, horizon]. Deep night until about an hour
    // before sunrise, then the dawn comes up from the horizon; the same in reverse at dusk.
    private static let table: [(Double, RGB, RGB, RGB)] = [
        (-1, (6, 9, 24), (11, 18, 42), (20, 28, 56)),
        (-0.28, (6, 9, 24), (11, 18, 42), (20, 28, 56)),
        (-0.14, (11, 17, 42), (26, 34, 76), (56, 56, 104)),
        (-0.04, (28, 42, 88), (88, 80, 130), (208, 126, 104)),
        (0.03, (50, 80, 138), (146, 128, 158), (250, 168, 108)),
        (0.15, (70, 116, 176), (150, 180, 212), (246, 206, 160)),
        (0.4, (63, 120, 191), (121, 172, 220), (188, 220, 242)),
        (1, (58, 114, 186), (114, 166, 218), (184, 218, 242)),
    ]

    var body: some View {
        let h: CGFloat = 160, a = (minutes / 60 - 6) / 12 * .pi, e = sin(a)
        let rx = width / 2, ry: CGFloat = 112   // the sun rises from the very left edge and sets at the right
        let sun = CGPoint(x: width / 2 - rx * cos(a), y: h - ry * e), moon = CGPoint(x: width - sun.x, y: h + ry * e)
        var i = 0
        while i < Self.table.count - 2 && e > Self.table[i + 1].0 { i += 1 }
        let lo = Self.table[i], hi = Self.table[i + 1], k = min(1, max(0, (e - lo.0) / (hi.0 - lo.0)))
        let low = 1 - Self.ramp(0, 0.3, e)
        return ZStack(alignment: .topLeading) {
            LinearGradient(stops: [.init(color: Self.color(Self.blend(lo.1, hi.1, k)), location: 0),
                                   .init(color: Self.color(Self.blend(lo.2, hi.2, k)), location: 0.62),
                                   .init(color: Self.color(Self.blend(lo.3, hi.3, k)), location: 1)], startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                for (sx, sy, b) in Self.stars {
                    let th = -0.24 + b * 0.2                                  // where this star goes out
                    let o = (0.5 + 0.5 * b) * (1 - Self.ramp(th - 0.06, th + 0.06, e))
                    guard o > 0.01 else { continue }
                    let r = (1.4 + b * 1.6) / 2, c = CGPoint(x: sx / 100 * size.width, y: sy / 100 * size.height)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 2.5, y: c.y - r * 2.5, width: r * 5, height: r * 5)),
                             with: .radialGradient(Gradient(colors: [Color(red: 0.87, green: 0.9, blue: 1).opacity(o * 0.35), .clear]),
                                                   center: c, startRadius: 0, endRadius: r * 2.5))
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(.white.opacity(o)))
                }
            }
            // the warm band of sunrise and sunset gathers around the sun at the horizon
            Ellipse()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.6, blue: 0.32).opacity(0.7), Color(red: 1, green: 0.6, blue: 0.32).opacity(0.25), .clear],
                                     center: .center, startRadius: 0, endRadius: 170))
                .frame(width: 340, height: 150)
                .position(x: sun.x, y: h)
                .opacity(exp(-pow((e - 0.02) / 0.11, 2)))
            // A crescent: only the side facing the sun is lit.
            Crescent()
                .fill(Color(red: 0.95, green: 0.93, blue: 0.886))
                .frame(width: 18, height: 18)
                .rotationEffect(.radians(atan2(sun.y - moon.y, sun.x - moon.x)))
                .shadow(color: Color(red: 0.91, green: 0.9, blue: 1).opacity(0.35), radius: 5)
                .position(moon)
                .opacity(Self.ramp(-0.04, 0.12, -e))
            // a low sun shines through more air: warmer
            Circle()
                .fill(Color(red: 1, green: (246 - 82 * low) / 255, blue: (224 - 132 * low) / 255))
                .frame(width: 22, height: 22)
                .shadow(color: Color(red: 1, green: (216 - 76 * low) / 255, blue: (138 - 80 * low) / 255).opacity(0.6), radius: 8)
                .shadow(color: Color(red: 1, green: 0.75, blue: 0.42).opacity(0.18), radius: 28)
                .position(sun)
        }
        .frame(width: width, height: h)
        .clipped()
        .allowsHitTesting(false)
    }

    static func ramp(_ lo: Double, _ hi: Double, _ v: Double) -> Double { let k = min(1, max(0, (v - lo) / (hi - lo))); return k * k * (3 - 2 * k) }
    static func blend(_ a: RGB, _ b: RGB, _ t: Double) -> RGB { (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t) }
    static func color(_ c: RGB) -> Color { Color(red: c.0 / 255, green: c.1 / 255, blue: c.2 / 255) }
}

/// A crescent moon, lit on its right side: the disc minus the same disc shifted left.
private struct Crescent: Shape {
    func path(in r: CGRect) -> Path {
        Path(ellipseIn: r).subtracting(Path(ellipseIn: r.offsetBy(dx: -r.width * 0.28, dy: 0)))
    }
}

/// A light, crisp haptic per quarter, a firmer one on the hour, a dull one at the stops.
@MainActor private final class ScrubberFeedback {
    static let shared = ScrubberFeedback()
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let synth = ScrubberSynth()

    func prepare() { rigid.prepare(); soft.prepare() }
    func tap(hour: Bool) {
        rigid.impactOccurred(intensity: hour ? 0.8 : 0.45)
        rigid.prepare()
    }
    func quarter(sound: Bool) { tap(hour: false); if sound { synth.play([(0, false)]) } }
    func hour(sound: Bool) { tap(hour: true); if sound { synth.play([(0, true)]) } }
    func stop(sound: Bool) {
        soft.impactOccurred(intensity: 0.9)
        soft.prepare()
        if sound { synth.playStop() }
    }
    func track(_ clicks: [(Double, Bool)], sound: Bool) { if sound, !clicks.isEmpty { synth.play(clicks) } }
    func cancelTrack() { synth.stop() }
}

/// Small hard plastic parts ringing for a millisecond or two at a few high body modes: a tiny bright tick for the quarters,
/// a louder, lower one for the hours, a duller one for the end stops.
private final class ScrubberSynth {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let stopPlayer = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private var quarter: [Float] = [], hour: [Float] = [], stopTick: [Float] = []
    private var ready = false

    init() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else { return }
        self.format = format
        for p in [player, stopPlayer] {
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
        }
        let rate = Float(format.sampleRate)
        quarter = Self.renderTick(rate: rate, level: 0.05, tune: 1.35)
        hour = Self.renderTick(rate: rate, level: 0.07, tune: 1.6 * 0.62)
        stopTick = Self.renderTick(rate: rate, level: 0.09, tune: 0.85)
        // Ambient: respects the silent switch and mixes with the user's music.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        ready = (try? engine.start()) != nil
    }

    /// Mixes one click at each time (ms from now) into a single buffer, so their spacing is exact to the sample.
    func play(_ clicks: [(Double, Bool)]) {
        guard ready, let format, let lastMs = clicks.map(\.0).max() else { return }
        render(clicks.map { ($0.0, $0.1 ? hour : quarter) }, lastMs: lastMs, format: format, on: player)
    }

    func playStop() {
        guard ready, let format else { return }
        render([(0, stopTick)], lastMs: 0, format: format, on: stopPlayer)
    }

    func stop() { player.stop() }

    private func render(_ clicks: [(Double, [Float])], lastMs: Double, format: AVAudioFormat, on node: AVAudioPlayerNode) {
        let rate = format.sampleRate
        let frames = AVAudioFrameCount(rate * (lastMs / 1000 + 0.03))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let out = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = frames
        for i in 0..<Int(frames) { out[i] = 0 }
        for (ms, tick) in clicks {
            let start = Int(ms / 1000 * rate)
            for j in 0..<tick.count where start + j < Int(frames) { out[start + j] += tick[j] }
        }
        node.stop()
        node.scheduleBuffer(buffer, at: nil, options: .interrupts)
        node.play()
    }

    private static let modes: [(Float, Float, Float)] = [(1900, 0.0024, 1), (3400, 0.0015, 0.55), (6100, 0.0008, 0.3)]

    private static func renderTick(rate: Float, level: Float, tune: Float) -> [Float] {
        (0..<Int(rate * 0.02)).map { i in
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
        @State private var minutes = 375
        var body: some View {
            VStack(spacing: 24) {
                GlassScrubber(minutes: $minutes, label: "Eastern Time", tone: .light)
                GlassScrubber(minutes: $minutes, label: "Eastern Time", tone: .dark)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: 0.5))
        }
    }
    return Demo()
}
