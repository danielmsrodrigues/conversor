import AppKit
import SwiftUI

/// Círculo dividido em fatias (um "pie menu") que aparece à volta do cursor.
struct RingView: View {
    @ObservedObject var model: RingModel

    static let size: CGFloat = 360
    static let outerRadius: CGFloat = 138
    static let innerRadius: CGFloat = 52

    var body: some View {
        ZStack {
            // Clicar fora do círculo fecha, como um menu.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { model.onDismiss() }

            Pie(model: model)
                .scaleEffect(model.open ? 1 : 0.55)
                .rotationEffect(.degrees(model.open ? 0 : -40))
                .opacity(model.open ? 1 : 0)
                .animation(.spring(response: 0.4, dampingFraction: 0.72), value: model.open)
                .allowsHitTesting(model.open)

            Hub(model: model)

            if case .failed(let message) = model.phase {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .frame(maxWidth: 300)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
                    .offset(y: 52)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }

            if case .done(let outputs, let failures) = model.phase {
                VStack(spacing: 2) {
                    Text(outputs.count == 1 ? shortened(outputs[0].lastPathComponent) : String(localized: "\(outputs.count) files created"))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if !failures.isEmpty {
                        Text("\(failures.count) failed")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .fixedSize()
                .glassEffect(.regular.interactive(), in: .capsule)
                .onTapGesture { model.reveal() }
                .help("Show in Finder")
                .offset(y: 46)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .foregroundStyle(.white)
        .frame(width: Self.size, height: Self.size)
        .preferredColorScheme(.dark)
    }

    /// Nomes compridos ficam "início…fim" para a etiqueta não sair do ecrã.
    private func shortened(_ name: String, limit: Int = 38) -> String {
        guard name.count > limit else { return name }
        return "\(name.prefix(limit / 2 - 1))…\(name.suffix(limit / 2 - 1))"
    }
}

/// O disco com as fatias, uma por formato.
private struct Pie: View {
    @ObservedObject var model: RingModel

    var body: some View {
        let count = model.targets.count
        let sweep = 360 / Double(max(count, 1))
        ZStack {
            ForEach(Array(model.targets.enumerated()), id: \.element.id) { index, format in
                // A primeira fatia fica centrada no topo.
                let start = -90 - sweep / 2 + sweep * Double(index)
                PieSlice(format: format, start: start, sweep: sweep, isHovered: model.hovered == format) {
                    model.convert(to: format)
                }
            }
        }
        .frame(width: RingView.outerRadius * 2, height: RingView.outerRadius * 2)
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        // O "hover" normal mede o quadrado todo; aqui decide-se a fatia pelo ângulo do rato.
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): model.hovered = format(at: point, sweep: sweep)
            case .ended: model.hovered = nil
            }
        }
    }

    private func format(at point: CGPoint, sweep: Double) -> Format? {
        let dx = point.x - RingView.outerRadius, dy = point.y - RingView.outerRadius
        let distance = hypot(dx, dy)
        guard distance >= RingView.innerRadius, distance <= RingView.outerRadius + 8, !model.targets.isEmpty else { return nil }
        let degrees = atan2(dy, dx) * 180 / .pi
        let index = Int(((degrees + 90 + sweep / 2).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / sweep)
        return model.targets[min(index, model.targets.count - 1)]
    }
}

private struct PieSlice: View {
    let format: Format
    let start: Double
    let sweep: Double
    let isHovered: Bool
    let action: () -> Void

    var body: some View {
        let shape = Sector(start: .degrees(start), sweep: .degrees(sweep))
        let mid = Angle.degrees(start + sweep / 2)
        let labelRadius = (RingView.innerRadius + RingView.outerRadius) / 2 + 4

        Button(action: action) {
            ZStack {
                // Só vidro, sem cores; a fatia debaixo do rato fica mais clara.
                Color.clear
                    .glassEffect(.regular.interactive(), in: shape)
                shape.fill(.white.opacity(isHovered ? 0.2 : 0))
                shape.stroke(.white.opacity(isHovered ? 0.35 : 0.1), lineWidth: 1)

                VStack(spacing: 0) {
                    Text(".\(format.ext)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(format.name)
                        .font(.system(size: 8, weight: .medium))
                        .opacity(0.8)
                        .lineLimit(1)
                }
                .fixedSize()
                .offset(x: cos(mid.radians) * labelRadius, y: sin(mid.radians) * labelRadius)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        // A fatia escolhida "salta" um pouco para fora.
        .offset(x: isHovered ? cos(mid.radians) * 6 : 0, y: isHovered ? sin(mid.radians) * 6 : 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isHovered)
    }
}

/// Uma fatia do anel: cantos de fora bem redondos, os de junto ao centro quase direitos.
private struct Sector: Shape {
    let start: Angle
    let sweep: Angle
    var gap: CGFloat = 5
    var outerCorner: CGFloat = 12
    var innerCorner: CGFloat = 3

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outer = RingView.outerRadius, inner = RingView.innerRadius
        func point(_ radius: CGFloat, _ angle: Double) -> CGPoint {
            CGPoint(x: c.x + radius * cos(angle), y: c.y + radius * sin(angle))
        }
        // Folga de largura constante: em ângulo é maior por dentro do que por fora.
        let outerPad = Double(gap / 2 / outer), innerPad = Double(gap / 2 / inner)
        let a0 = start.radians + outerPad, a1 = start.radians + sweep.radians - outerPad
        let b0 = start.radians + innerPad, b1 = start.radians + sweep.radians - innerPad

        // Cantos: arco tangente entre a aresta e a tangente ao círculo nesse ponto.
        // As arestas são quase perpendiculares aos arcos, por isso o canto "gasta" ~raio de arco.
        let outerStart = point(outer, a0), outerEnd = point(outer, a1)
        let innerEnd = point(inner, b1), innerStart = point(inner, b0)
        let edgeMid = CGPoint(x: (outerStart.x + innerStart.x) / 2, y: (outerStart.y + innerStart.y) / 2)

        var path = Path()
        path.move(to: edgeMid)
        path.addArc(tangent1End: outerStart,
                    tangent2End: CGPoint(x: outerStart.x - sin(a0) * 40, y: outerStart.y + cos(a0) * 40),
                    radius: outerCorner)
        path.addArc(center: c, radius: outer,
                    startAngle: .radians(a0 + Double(outerCorner / outer)),
                    endAngle: .radians(a1 - Double(outerCorner / outer)), clockwise: false)
        path.addArc(tangent1End: outerEnd, tangent2End: innerEnd, radius: outerCorner)
        path.addArc(tangent1End: innerEnd,
                    tangent2End: CGPoint(x: innerEnd.x + sin(b1) * 40, y: innerEnd.y - cos(b1) * 40),
                    radius: innerCorner)
        path.addArc(center: c, radius: inner,
                    startAngle: .radians(b1 - Double(innerCorner / inner)),
                    endAngle: .radians(b0 + Double(innerCorner / inner)), clockwise: true)
        path.addArc(tangent1End: innerStart, tangent2End: edgeMid, radius: innerCorner)
        path.closeSubpath()
        return path
    }
}

/// O círculo do meio: ficheiro → a converter → feito.
private struct Hub: View {
    @ObservedObject var model: RingModel

    private var hubSize: CGFloat { model.phase == .picking ? 92 : 52 }

    var body: some View {
        ZStack {
            switch model.phase {
            case .picking:
                VStack(spacing: 4) {
                    if let format = model.hovered {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                            .opacity(0.7)
                        Text(".\(format.ext)")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                    } else {
                        FileIcons(files: model.files)
                        Text(model.files.count == 1 ? model.files[0].lastPathComponent : String(localized: "\(model.files.count) files"))
                            .font(.system(size: 8.5, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 70)
                            .opacity(0.8)
                    }
                }
                .animation(.snappy(duration: 0.15), value: model.hovered)

            case .working:
                ProgressView().controlSize(.small)

            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.green)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))

            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(.yellow)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
        }
        // Ao escolher mostra o ficheiro; depois basta uma bolinha com o resultado.
        .frame(width: hubSize, height: hubSize)
        .glassEffect(.regular, in: .circle)
        .scaleEffect(model.open || model.phase != .picking ? 1 : 0.7)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: model.open)
        .onTapGesture {
            if case .done = model.phase { model.reveal() }
        }
    }
}

private struct FileIcons: View {
    let files: [URL]

    var body: some View {
        ZStack {
            ForEach(Array(files.prefix(3).enumerated().reversed()), id: \.offset) { index, url in
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 34, height: 34)
                    .rotationEffect(.degrees(Double(index) * 8))
                    .offset(x: CGFloat(index) * 5)
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }
}
