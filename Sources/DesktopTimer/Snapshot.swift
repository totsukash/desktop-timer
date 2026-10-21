import AppKit
import SwiftUI

// README用の画像を、本物の画面から書き出す
// DESKTOP_TIMER_SNAPSHOT=<出力先> を付けて起動すると、画像を書いて終わる
enum Snapshot {
    private static var windows: [(NSWindow, String)] = []

    static func run(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let hero = scene(task: "企画書を仕上げる", minutes: "25")
        render(Desktop(content: RootView(state: hero.0, timer: hero.1)), size: NSSize(width: 760, height: 380), name: "hero")

        let themes: [(Int, Double, String, String)] = [
            (1, 0.85, "メールを返す", "15"), (13, 0.9, "設計を考える", "45"),
            (7, 0.9, "読書", "30"), (0, 0.35, "コードレビュー", "1:30:00"),
        ]
        render(Desktop(content: HStack(spacing: 18) {
            ForEach(themes.indices, id: \.self) { i in
                let s = scene(task: themes[i].2, minutes: themes[i].3, theme: themes[i].0, opacity: themes[i].1)
                RootView(state: s.0, timer: s.1).frame(width: fullSize.width, height: fullSize.height)
            }
        }, alignment: .center), size: NSSize(width: 1120, height: 230), name: "themes")

        let typing = scene(task: "企画書を仕上げる")
        typing.0.editing = .duration
        typing.0.input = "25"
        let until = scene(task: "企画書を仕上げる")
        until.0.editing = .until
        until.0.input = "8:00"
        render(Desktop(content: HStack(spacing: 24) {
            RootView(state: typing.0, timer: typing.1).frame(width: fullSize.width, height: fullSize.height)
            RootView(state: until.0, timer: until.1).frame(width: fullSize.width, height: fullSize.height)
        }, alignment: .center), size: NSSize(width: 600, height: 210), name: "input")

        let carry = scene(task: "企画書を仕上げる", minutes: "25")
        carry.0.lifted = true
        carry.0.tilt = -2.2
        render(Desktop(content: RootView(state: carry.0, timer: carry.1)
            .frame(width: fullSize.width, height: fullSize.height)
            .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
            .overlay(Image(systemName: "hand.raised.fill").font(.system(size: 26)).foregroundStyle(.white)
                .shadow(radius: 2).offset(x: 20, y: 6)),
            alignment: .center), size: NSSize(width: 420, height: 230), name: "carry")

        let settings = scene()
        settings.0.showSettings = true
        let mini = scene(minutes: "25")
        mini.0.mini = true
        render(Desktop(content: HStack(spacing: 40) {
            RootView(state: settings.0, timer: settings.1).frame(width: fullSize.width, height: fullSize.height)
            RootView(state: mini.0, timer: mini.1)
                .frame(width: miniSize.width, height: miniSize.height)
                .scaleEffect(3)
                .frame(width: 90, height: 90)
        }, alignment: .center), size: NSSize(width: 520, height: 210), name: "settings")

        let done = AppState()
        done.task = "企画書を仕上げる"
        render(FinishedView(state: done) {}.background(Wallpaper()), size: NSSize(width: 720, height: 400), name: "finished")
        render(CelebrationView(celebration: Celebration(task: "企画書を仕上げる", elapsed: 23 * 60 + 12))
            .background(Wallpaper()), size: NSSize(width: 720, height: 400), name: "celebration")

        // 紙吹雪が画面の中ほどまで落ちるのを待ってから書き出す
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            for (window, name) in windows {
                guard let view = window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
            }
            exit(0)
        }
    }

    private static func scene(task: String = "", minutes: String? = nil, theme: Int = 1, opacity: Double = 0.85) -> (AppState, TimerModel) {
        let state = AppState()
        state.task = task
        state.themeIndex = theme
        state.opacity = opacity
        let timer = TimerModel()
        if let minutes { _ = timer.start(typed: minutes) }
        return (state, timer)
    }

    private static func render<V: View>(_ view: V, size: NSSize, name: String) {
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -20000, y: -20000), size: size),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.sizingOptions = []
        window.contentView = host
        window.orderFrontRegardless()
        windows.append((window, name))
    }
}

// macの画面に見立てた背景。右上にタイマーを置き、左に作業中の窓を描く
private struct Desktop<Content: View>: View {
    let content: Content
    var alignment: Alignment = .topTrailing

    var body: some View {
        ZStack(alignment: alignment) {
            Wallpaper()
            if alignment == .topTrailing {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(white: 0.97))
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 7) {
                                ForEach([Color.red, .orange, .green], id: \.self) { Circle().fill($0).frame(width: 11, height: 11) }
                            }
                            ForEach([0.9, 0.7, 0.8, 0.5, 0.75, 0.6], id: \.self) { w in
                                RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.1)).frame(width: 380 * w, height: 9)
                            }
                        }
                        .padding(16)
                    }
                    .frame(width: 440, height: 300)
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 40)
                    .offset(y: 30)
                content
                    .frame(width: fullSize.width, height: fullSize.height)
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                    .padding(.top, 28)
                    .padding(.trailing, 20)
            } else {
                content
            }
        }
        .clipped()
    }
}

private struct Wallpaper: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.36, green: 0.42, blue: 0.85), Color(red: 0.62, green: 0.40, blue: 0.80), Color(red: 0.95, green: 0.60, blue: 0.55)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}
