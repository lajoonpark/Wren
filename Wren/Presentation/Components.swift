import SwiftUI

// MARK: - Explanations

/// A process name that explains itself: click the name or the glyph beside it
/// to open the wiki. Deliberately always visible rather than hover-revealed,
/// because the person who needs it is the one who has no idea what they are
/// looking at. Hovering the name also holds updates still, so the name and its
/// tooltip stay put long enough to read and click.
struct ProcessNameCell: View {
    let name: String
    var bundleIdentifier: String? = nil
    var detail: String? = nil
    var font: Font = Typeface.label(12.5)

    @Environment(AppRouter.self) private var router
    @Environment(AppSession.self) private var session
    @State private var isHovering = false
    @State private var holdID = UUID()

    var body: some View {
        Button {
            router.openWiki(forName: name, bundleIdentifier: bundleIdentifier)
        } label: {
            HStack(spacing: 5) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(font)
                        .foregroundStyle(isHovering ? Palette.accent : Palette.ink)
                        .lineLimit(1)
                    if let detail {
                        Text(detail)
                            .font(Typeface.label(10.5))
                            .foregroundStyle(Palette.inkSoft)
                            .lineLimit(1)
                    }
                }
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft.opacity(isHovering ? 0.9 : 0.45))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("What is \(name)?")
        .accessibilityLabel(name)
        .accessibilityHint("Opens the wiki to explain what this is")
        .onHover { hovering in
            // Text-colour changes are the expensive part of hover: animating
            // them re-rasterizes the name's glyphs at display refresh, and a
            // scroll sweeps the pointer across many names. The colour and glyph
            // still change, just without an easing curve.
            isHovering = hovering
            session.setReadHold(holdID, hovering)
        }
        .onDisappear {
            session.setReadHold(holdID, false)
        }
    }
}

/// A metric name that explains itself: hover for a one-line answer, click for
/// the fuller one. Every technical term in the app wears one of these.
struct GlossaryLabel: View {
    let entry: GlossaryEntry
    var title: String? = nil
    var font: Font = Typeface.label(11.5)
    var tint: Color = Palette.inkSoft
    var showsGlyph: Bool = true

    @Environment(AppSession.self) private var session
    @State private var showsDetail = false
    @State private var holdID = UUID()

    var body: some View {
        Button {
            showsDetail.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(title ?? entry.term)
                    .font(font)
                if showsGlyph {
                    Image(systemName: "info.circle")
                        .font(.system(size: 8.5, weight: .semibold))
                        .opacity(0.55)
                }
            }
            .foregroundStyle(tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(entry.summary)
        .popover(isPresented: $showsDetail, arrowEdge: .bottom) {
            GlossaryPopover(entry: entry)
        }
        .onChange(of: showsDetail) { _, presented in
            session.setReadHold(holdID, presented)
        }
        .onDisappear {
            session.setReadHold(holdID, false)
        }
        .accessibilityLabel(entry.term)
        .accessibilityHint(entry.summary)
    }
}

struct GlossaryPopover: View {
    let entry: GlossaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(entry.term)
                .font(Typeface.heading(13))
                .foregroundStyle(Palette.ink)
            Text(entry.summary)
                .font(Typeface.proseEmphasis(15))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle()
                .fill(Palette.rule)
                .frame(height: 1)
            Text(entry.detail)
                .font(Typeface.prose(13.5))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
        .background(Palette.paperCard)
    }
}

// MARK: - Values

/// Numeric readout that snaps to its new value, like the gauges beside it:
/// measured, not eased. Values change on every sample, and animating them
/// redraws the window's glyphs at display refresh — see `Motion`.
struct MetricValue: View {
    let text: String
    var font: Font = Typeface.data(13)
    var color: Color = Palette.ink

    var body: some View {
        Text(text)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
    }
}

/// Thin meter that snaps to its new fill: measured, not eased.
struct GaugeBar: View {
    var fraction: Double
    var tint: Color = Palette.accent
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(tint.opacity(0.18))
                Capsule()
                    .fill(tint)
                    .frame(width: max(height, proxy.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

struct HealthDot: View {
    let level: HealthLevel
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(Palette.health(level))
            .frame(width: size, height: size)
            .shadow(color: Palette.health(level).opacity(0.5), radius: level == .normal ? 0 : 4)
    }
}

// MARK: - Panel surfaces

/// A value on the dark instrument surface: tracked label above, mono value below.
struct ReadoutTile: View {
    var label: GlossaryEntry?
    var title: String
    var value: String
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label {
                GlossaryLabel(entry: label, tint: Palette.readoutSoft)
            } else {
                Text(title)
                    .font(Typeface.label(11.5))
                    .foregroundStyle(Palette.readoutSoft)
            }
            MetricValue(text: value, font: Typeface.data(15), color: Palette.readoutInk)
            if let caption {
                Text(caption)
                    .font(Typeface.label(10.5))
                    .foregroundStyle(Palette.readoutSoft.opacity(0.85))
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous)
                .fill(Palette.readoutCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous)
                .strokeBorder(Palette.readoutRule, lineWidth: 1)
        )
    }
}

// MARK: - Ledger

/// A paper list: hairline rows that warm up under the pointer instead of
/// taking a hard selection highlight.
struct LedgerRow<Content: View>: View {
    @ViewBuilder var content: Content

    @Environment(AppSession.self) private var session
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            content
        }
        .padding(.init(top: 8, leading: 12, bottom: 8, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovering ? Palette.ink.opacity(0.045) : Color.clear)
        .overlay(alignment: .bottom) {
            Palette.rule.frame(height: 1)
        }
        .onHover { hovering in
            if session.isScrolling {
                isHovering = hovering
            } else {
                withAnimation(Motion.reveal) { isHovering = hovering }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Column headings for a ledger.
struct LedgerHeader<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) {
            content
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Sortable column heading, with the explanation as a separate small control
/// so the sort button and the info button never compete for the same click.
struct SortableHeader: View {
    let title: String
    var entry: GlossaryEntry? = nil
    var isActive: Bool = false
    var isAscending: Bool = false
    var width: CGFloat? = nil
    let action: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: action) {
                HStack(spacing: 3) {
                    Text(title)
                        .font(Typeface.label(11))
                        .foregroundStyle(isActive ? Palette.ink : Palette.inkSoft)
                    Image(systemName: isAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Palette.accent)
                        .opacity(isActive ? 1 : 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let entry {
                GlossaryGlyphButton(entry: entry)
            }
        }
        .frame(width: width, alignment: .trailing)
        .animation(Motion.reveal, value: isActive)
    }
}

/// Just the question mark, for places where the term is already on screen.
struct GlossaryGlyphButton: View {
    let entry: GlossaryEntry

    @Environment(AppSession.self) private var session
    @State private var showsDetail = false
    @State private var holdID = UUID()

    var body: some View {
        Button {
            showsDetail.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(Palette.inkSoft.opacity(0.6))
                .frame(width: 12, height: 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(entry.summary)
        .popover(isPresented: $showsDetail, arrowEdge: .bottom) {
            GlossaryPopover(entry: entry)
        }
        .onChange(of: showsDetail) { _, presented in
            session.setReadHold(holdID, presented)
        }
        .onDisappear {
            session.setReadHold(holdID, false)
        }
        .accessibilityLabel("What is \(entry.term)?")
        .accessibilityHint(entry.summary)
    }
}

// MARK: - Chrome

/// Freezes sampling so a reading stays still. Global chrome, because the need
/// to read a value without it moving is not tied to one tab. Icon-only: the
/// title bar shares space with the tab bar, and the pause glyph is unambiguous.
struct PauseButton: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Button {
            withAnimation(Motion.reveal) { session.togglePaused() }
        } label: {
            Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(session.isPaused ? Palette.accent : Palette.inkSoft)
                .frame(width: 26, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(session.isPaused ? Palette.accent.opacity(0.12) : Palette.ink.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
        .help(session.isPaused ? "Resume sampling" : "Pause sampling so the numbers hold still")
        .accessibilityLabel(session.isPaused ? "Resume sampling" : "Pause sampling")
    }
}
