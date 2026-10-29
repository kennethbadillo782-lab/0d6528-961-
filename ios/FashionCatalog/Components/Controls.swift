import SwiftUI

// MARK: - Barra de búsqueda

struct SearchBar: View {
    @Binding var text: String
    var placeholder: String
    var onSubmit: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Theme.textSecondary))
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { onSubmit?() }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Borrar búsqueda")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Theme.search, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Chips

enum ChipAccent {
    case white, blue
}

struct FilterChip: View {
    let title: String
    var isSelected: Bool
    var accent: ChipAccent = .white
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .foregroundStyle(foreground)
                .background(background, in: Capsule())
                .overlay(
                    Capsule().stroke(accent == .blue && isSelected ? Theme.blue : .clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }

    private var foreground: Color {
        switch accent {
        case .white: return isSelected ? .black : .white
        case .blue: return .white
        }
    }

    private var background: Color {
        switch accent {
        case .white: return isSelected ? .white : Theme.chip
        case .blue: return isSelected ? Theme.blue.opacity(0.22) : Theme.chip
        }
    }
}

/// Fila horizontal desplazable con selección única. `allLabel` añade "Todos/Todas".
struct ChipRow: View {
    let options: [String]
    var allLabel: String?
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let allLabel {
                    FilterChip(title: allLabel, isSelected: selection == nil) { selection = nil }
                }
                ForEach(options, id: \.self) { option in
                    FilterChip(title: option, isSelected: selection == option) {
                        if selection == option, allLabel != nil {
                            selection = nil
                        } else {
                            selection = option
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.hPadding)
        }
        .padding(.horizontal, -Theme.hPadding)
    }
}

// MARK: - Botones

struct PrimaryButtonStyle: ButtonStyle {
    var isEnabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.white.opacity(isEnabled ? 1 : 0.4),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct HeartButton: View {
    let isOn: Bool
    var size: CGFloat = 17
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "heart.fill" : "heart")
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(isOn ? Theme.heart : .white)
                .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: isOn)
        .accessibilityLabel(isOn ? "Quitar de favoritos" : "Marcar como favorito")
    }
}

// MARK: - Varios

struct SectionTitle: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
    }
}

struct DemoBadge: View {
    var body: some View {
        Text("Ejemplo")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.55), in: Capsule())
    }
}

struct TagChip: View {
    let text: String
    var tint: Color = .white
    var filled = false

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(filled ? tint.opacity(0.16) : Theme.chip,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.textSecondary)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .frame(height: 40)
                    .background(Color.white, in: Capsule())
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }
}

struct ToastView: View {
    let message: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
            Text(message).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().stroke(Theme.border, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
    }
}

struct ColorDot: View {
    let swatch: ColorSwatch
    var isSelected: Bool
    var size: CGFloat = 30

    var body: some View {
        Circle()
            .fill(swatch.color)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            .padding(3)
            .overlay(Circle().stroke(isSelected ? Theme.blue : .clear, lineWidth: 2))
            .accessibilityLabel(swatch.name)
    }
}

// MARK: - Distribución en filas que saltan de línea

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: proposal.width ?? width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Control deslizante de rango

struct RangeSlider: View {
    @Binding var range: ClosedRange<Double>
    let bounds: ClosedRange<Double>
    let thumb: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width - thumb, 1)
            let span = max(bounds.upperBound - bounds.lowerBound, 0.0001)
            let lowX = CGFloat((range.lowerBound - bounds.lowerBound) / span) * width
            let highX = CGFloat((range.upperBound - bounds.lowerBound) / span) * width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.border)
                    .frame(height: 4)
                    .padding(.horizontal, thumb / 2)
                Capsule()
                    .fill(Theme.blue)
                    .frame(width: max(highX - lowX, 0), height: 4)
                    .offset(x: lowX + thumb / 2)
                knob
                    .offset(x: lowX)
                    .gesture(DragGesture(coordinateSpace: .named("range")).onChanged { g in
                        let v = value(at: g.location.x, width: width, span: span)
                        range = min(v, range.upperBound)...range.upperBound
                    })
                knob
                    .offset(x: highX)
                    .gesture(DragGesture(coordinateSpace: .named("range")).onChanged { g in
                        let v = value(at: g.location.x, width: width, span: span)
                        range = range.lowerBound...max(v, range.lowerBound)
                    })
            }
            .frame(height: geo.size.height)
        }
        .coordinateSpace(name: "range")
        .frame(height: 30)
    }

    private var knob: some View {
        Circle()
            .fill(Color.white)
            .frame(width: thumb, height: thumb)
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
    }

    private func value(at x: CGFloat, width: CGFloat, span: Double) -> Double {
        let ratio = Double(min(max((x - thumb / 2) / width, 0), 1))
        return (bounds.lowerBound + ratio * span).rounded()
    }
}
