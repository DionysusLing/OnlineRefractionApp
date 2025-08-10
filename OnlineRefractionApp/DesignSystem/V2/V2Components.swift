// =============================
// File: DesignSystem/V2/V2Components.swift
// 说明：v2 通用组件集合
// =============================
import SwiftUI

public struct GlowButton: View {
    public var title: String
    public var disabled: Bool = false
    public var action: () -> Void
    public init(title: String, disabled: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.disabled = disabled; self.action = action
    }
    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(ThemeV2.Fonts.h1())
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    LinearGradient(colors: [ThemeV2.Colors.brandBlue, ThemeV2.Colors.brandCyan], startPoint: .leading, endPoint: .trailing)
                        .opacity(disabled ? 0.4 : 1)
                )
                .cornerRadius(20)
                .shadow(color: ThemeV2.Colors.brandBlue.opacity(0.35), radius: 16, x: 0, y: 10)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

public struct ChipToggle: View {
    public var label: String
    @Binding public var isOn: Bool
    public init(label: String, isOn: Binding<Bool>) { self.label = label; _isOn = isOn }
    public var body: some View {
        Button { isOn.toggle() } label: {
            HStack {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isOn ? Color.white.opacity(0.2) : ThemeV2.Colors.slate50)
                        .frame(width: 28, height: 28)
                        .overlay(Text(isOn ? "✓" : "·").font(.system(size: 14, weight: .bold)).foregroundColor(isOn ? .white : .gray))
                    Text(label)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(isOn ? .white : ThemeV2.Colors.text)
                }
                Spacer()
                ZStack(alignment: isOn ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isOn ? Color.white.opacity(0.25) : ThemeV2.Colors.slate50)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isOn ? Color.white.opacity(0.4) : ThemeV2.Colors.border, lineWidth: 1))
                        .frame(width: 44, height: 20)
                    Circle().fill(isOn ? .white : Color.gray.opacity(0.6)).frame(width: 16, height: 16).padding(2)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background {
                ZStack {
                    ThemeV2.Colors.card
                    if isOn {
                        LinearGradient(
                            colors: [Color(red: 0, green: 0.78, blue: 0.60), .green],
                            startPoint: .leading, endPoint: .trailing
                        )
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(isOn ? Color.clear : ThemeV2.Colors.border, lineWidth: 1))
            .cornerRadius(20)
            .shadow(color: .black.opacity(isOn ? 0.08 : 0.03), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}

public enum InfoTone { case info, warn, error, ok }
public struct InfoBar: View {
    public var tone: InfoTone = .info
    public var text: String
    public init(tone: InfoTone = .info, text: String) { self.tone = tone; self.text = text }
    public var body: some View {
        let cfg: (Color, Color, Color) = {
            switch tone {
            case .info:  return (Color.blue.opacity(0.1), Color.blue.opacity(0.9), Color.blue.opacity(0.2))
            case .warn:  return (Color.orange.opacity(0.12), Color.orange.opacity(0.9), Color.orange.opacity(0.25))
            case .error: return (Color.red.opacity(0.12), Color.red.opacity(0.9), Color.red.opacity(0.25))
            case .ok:    return (Color.green.opacity(0.1), Color.green.opacity(0.9), Color.green.opacity(0.2))
            }
        }()
        return Text(text)
            .font(ThemeV2.Fonts.note())
            .foregroundColor(cfg.1)
            .padding(.vertical, 8).padding(.horizontal, 12)
            .background(cfg.0)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(cfg.2, lineWidth: 1))
            .cornerRadius(12)
    }
}

public struct StepProgress: View {
    public var step: Int
    public var total: Int
    public init(step: Int, total: Int) { self.step = step; self.total = total }
    public var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(ThemeV2.Colors.border).frame(height: 6)
            GeometryReader { g in
                let w = max(6, CGFloat(step) / CGFloat(total) * (g.size.width))
                Capsule().fill(LinearGradient(colors: [ThemeV2.Colors.brandBlue, ThemeV2.Colors.brandCyan], startPoint: .leading, endPoint: .trailing))
                    .frame(width: w, height: 6)
                    .animation(.easeInOut(duration: 0.25), value: step)
            }
        }
        .frame(height: 6)
        .accessibilityLabel("进度")
        .accessibilityValue("第\(step)步，共\(total)步")
    }
}

public struct SpeakerView: View { public init() {} ;
    public var body: some View {
        Image(systemName: "speaker.wave.2.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.gray)
            .frame(width: 44, height: 44)
            .background(ThemeV2.Colors.card)
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(ThemeV2.Colors.border, lineWidth: 1))
            .cornerRadius(22)
            .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
            .padding(.top, 12)
    }
}
