import SwiftUI

/// Illustrations never send receiver input. Help is separate from device setup.
struct RemoteGuideView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(String(localized: "把手机变成触控板"))
                        .font(.title2.weight(.semibold))
                    Text(String(localized: "先在左上角选择设备，再看着电脑或电视屏幕操作。"))
                        .foregroundStyle(Palette.muted)
                    guideCard("hand.draw", gesture: .move,
                              title: String(localized: "滑动手指，移动电脑光标"),
                              detail: String(localized: "光效跟随你在手机上的手指，电脑光标的位置请看电脑屏幕。"))
                    guideCard("hand.tap", gesture: .tap,
                              title: String(localized: "单击左键，左右分区双击"),
                              detail: String(localized: "任意位置单击都是左键。左半区连续点两下发送两次左键，右半区连续点两下发送两次右键。分区只在指南中示意。"))
                    guideCard("hand.point.up", gesture: .hold,
                              title: String(localized: "按住 0.3 秒开始拖动，抬手松开"),
                              detail: String(localized: "按住后滑动手指，拖动物件或选择文字。"))
                    guideCard("hand.draw.fill", gesture: .scroll,
                              title: String(localized: "双指或右侧单指滑动，滚动页面"),
                              detail: String(localized: "双指像推动页面一样滚动；触控区右边的滚动条向下拉，页面向下走。"))
                    guideCard("keyboard", gesture: .text,
                              title: String(localized: "键盘与语音输入"),
                              detail: String(localized: "先选中电脑输入框，再点键盘或麦克风。支持的输入框自动同步，其他输入框用发送按钮提交。箭头可收起或展开键盘。"))
                    guideCard("delete.left", gesture: .backspace,
                              title: String(localized: "草稿与电脑退格"),
                              detail: String(localized: "先选中电脑输入框。实时输入时退格会同步；草稿中的未发送文字先在手机上删除。清空本地草稿后，可用键盘退格删除电脑文字。框下的电脑退格按钮直接作用于电脑，不删除手机草稿。"))
                    VStack(alignment: .leading, spacing: 10) {
                        Label {
                            Text(verbatim: "Android TV / Google TV")
                        } icon: {
                            Image(systemName: "tv")
                        }
                            .font(.headline)
                        Text(String(localized: "实验性接收端：光标是屏幕指示层，单击操作可访问控件，兼容性取决于电视与应用。暂不支持系统鼠标、右键、拖动、键盘或语音输入。"))
                            .font(.footnote).foregroundStyle(Palette.muted)
                    }.padding(18).background(Palette.panel, in: RoundedRectangle(cornerRadius: 20))
                    HStack {
                        Link(String(localized: "隐私政策"), destination: URL(string: "https://github.com/chekusu/sofatap/blob/main/PRIVACY.md")!)
                        Spacer()
                        Link(String(localized: "帮助与反馈"), destination: URL(string: "https://github.com/chekusu/sofatap/issues")!)
                    }.font(.footnote).padding(.vertical, 12)
                }.padding(20)
            }
            .background(Palette.background)
            .navigationTitle(String(localized: "使用指南"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "完成")) { dismiss() } } }
        }
        .tint(Palette.mint).preferredColorScheme(.dark)
    }

    private func guideCard(_ symbol: String, gesture: GuideGesture, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            GuideGestureDiagram(gesture: gesture).frame(height: 88).accessibilityHidden(true)
            Label(title, systemImage: symbol).font(.system(size: 16, weight: .semibold))
            Text(detail).font(.system(size: 14)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 20))
    }
}

private enum GuideGesture { case move, tap, hold, scroll, text, backspace }

private struct GuideGestureDiagram: View {
    let gesture: GuideGesture
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15).fill(Palette.background)
            Canvas { context, size in
                for row in 0..<5 {
                    for column in 0..<16 {
                        let rect = CGRect(x: CGFloat(column) * size.width / 16 + 8,
                                          y: CGFloat(row) * 17 + 8, width: 2, height: 2)
                        context.fill(Path(ellipseIn: rect), with: .color(Palette.mint.opacity(0.18)))
                    }
                }
            }
            HStack(spacing: 16) {
                if gesture == .tap {
                    // Show the invisible physical halves only in this guide. Keep
                    // their positions stable in right-to-left interface languages.
                    tapHalf(String(localized: "左键 ×2"))
                    Rectangle().fill(Palette.mint.opacity(0.25)).frame(width: 1, height: 58)
                    tapHalf(String(localized: "右键 ×2"))
                } else if gesture == .text {
                    Image(systemName: "keyboard"); Image(systemName: "mic.fill"); Image(systemName: "arrow.up.circle.fill")
                } else if gesture == .backspace {
                    Image(systemName: "delete.left"); Image(systemName: "arrow.right"); Image(systemName: "desktopcomputer")
                } else {
                    if gesture == .hold {
                        Circle().stroke(Palette.mint.opacity(0.30), lineWidth: 2).frame(width: 46, height: 46)
                            .overlay(Circle().fill(Palette.mint).frame(width: 17, height: 17))
                    } else {
                        HStack(spacing: 7) {
                            Capsule().fill(Palette.mint).frame(width: 12, height: 29)
                            if gesture == .scroll { Capsule().fill(Palette.mint).frame(width: 12, height: 29) }
                        }
                    }
                    if gesture == .hold { Text(verbatim: "0.3 s").font(.system(size: 17, weight: .medium, design: .rounded)) }
                    Image(systemName: gesture == .scroll ? "arrow.up.arrow.down" : "arrow.right")
                }
            }
            .font(.system(size: 24, weight: .medium)).foregroundStyle(Palette.mint)
            .environment(\.layoutDirection, .leftToRight)
        }
    }

    private func tapHalf(_ label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "hand.tap")
            Text(label).font(.system(size: 12, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
    }
}

struct RemoteIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        let pressed = isEnabled && configuration.isPressed
        configuration.label
            .scaleEffect(pressed && !reduceMotion ? 0.92 : 1)
            .opacity(pressed ? 0.65 : isEnabled ? 1 : 0.40)
            .animation(reduceMotion ? nil : .easeOut(duration: pressed ? 0.10 : 0.16), value: pressed)
    }
}
