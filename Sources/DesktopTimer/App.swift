import AppKit
import Combine
import SwiftUI

// MARK: - Entry

@main
enum Main {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        let cid = CGSDefaultConnection()
        _ = CGSSetConnectionProperty(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

// MARK: - Window

// 前面にいないアプリのカーソル指定は普段は無視される。窓の上では効くよう許可を取る
@_silgen_name("_CGSDefaultConnection") private func CGSDefaultConnection() -> Int32
@_silgen_name("CGSSetConnectionProperty")
private func CGSSetConnectionProperty(_ cid: Int32, _ target: Int32, _ key: CFString, _ value: CFTypeRef) -> Int32

let fullSize = NSSize(width: 250, height: 150)
let miniSize = NSSize(width: 22, height: 22)

struct Theme {
    let name: String
    let rgb: (Double, Double, Double)
    let light: Bool

    var color: Color { Color(red: rgb.0, green: rgb.1, blue: rgb.2) }

    static let all: [Theme] = [
        Theme(name: "ブラック", rgb: (0, 0, 0), light: false),
        Theme(name: "ネイビー", rgb: (0.08, 0.13, 0.24), light: false),
        Theme(name: "グリーン", rgb: (0.11, 0.26, 0.20), light: false),
        Theme(name: "ワイン", rgb: (0.36, 0.10, 0.17), light: false),
        Theme(name: "パープル", rgb: (0.24, 0.10, 0.36), light: false),
        Theme(name: "グレー", rgb: (0.29, 0.31, 0.34), light: false),
        Theme(name: "ホワイト", rgb: (0.96, 0.96, 0.95), light: true),
        Theme(name: "イエロー", rgb: (1.0, 0.90, 0.43), light: true),
        Theme(name: "水色", rgb: (0.55, 0.83, 0.98), light: true),
        Theme(name: "ブルー", rgb: (0.16, 0.50, 0.95), light: false),
        Theme(name: "レッド", rgb: (0.90, 0.20, 0.20), light: false),
        Theme(name: "オレンジ", rgb: (1.0, 0.60, 0.10), light: true),
        Theme(name: "ピンク", rgb: (1.0, 0.62, 0.76), light: true),
        Theme(name: "ミント", rgb: (0.60, 0.93, 0.80), light: true),
        Theme(name: "ライム", rgb: (0.78, 0.95, 0.42), light: true),
        Theme(name: "ラベンダー", rgb: (0.78, 0.71, 0.98), light: true),
    ]
}

struct Celebration {
    let task: String
    let elapsed: TimeInterval
}

final class AppState: ObservableObject {
    enum Editing { case none, duration, until, task }

    // この時間でやること。1行のメモとして上の行に出す
    @Published var task = UserDefaults.standard.string(forKey: "task") ?? "" {
        didSet { UserDefaults.standard.set(task, forKey: "task") }
    }

    // 設定: 背景色と濃さ。選んだ値はmacに保存して再起動後も使う
    @Published var showSettings = false
    @Published var themeIndex = UserDefaults.standard.integer(forKey: "themeIndex") {
        didSet { UserDefaults.standard.set(themeIndex, forKey: "themeIndex") }
    }
    @Published var opacity = UserDefaults.standard.object(forKey: "bgOpacity") as? Double ?? 0.78 {
        didSet { UserDefaults.standard.set(opacity, forKey: "bgOpacity") }
    }

    var theme: Theme { Theme.all[min(max(themeIndex, 0), Theme.all.count - 1)] }

    // 完了ボタンを押したときのお祝い。中身はお祝いの画面に出す
    @Published var celebration: Celebration?

    @Published var mini = false
    @Published var editing = Editing.none
    @Published var input = ""
    // 掴んで運んでいる間。少し縮めて、動かす向きと逆へ傾ける
    @Published var lifted = false
    @Published var tilt = 0.0
    // 入力中に、タイマーの外のクリックを見張る
    var outsideClickMonitor: Any?
}

final class FloatingPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: fullSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // 全画面アプリや他の最前面ウィンドウよりも上に出す
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        // macの標準の移動を使うと、画面端で整列の予告が出て他の窓に干渉する。移動は自前で行う
        isMovable = false
        becomesKeyOnlyIfNeeded = true
    }

    // 時刻の入力欄に文字を打てるようにする。前面のアプリは切り替えない
    override var canBecomeKey: Bool { true }

    weak var state: AppState?
    private var carryTimer: Timer?

    // 窓の上では、掴めることが分かるよう手の形のカーソルにする。前面のアプリでなくても効かせる
    override var contentView: NSView? {
        didSet {
            contentView?.addTrackingArea(NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                owner: self, userInfo: nil
            ))
        }
    }

    override func mouseEntered(with event: NSEvent) { updateCursor(event) }
    override func mouseMoved(with event: NSEvent) { updateCursor(event) }
    override func cursorUpdate(with event: NSEvent) { updateCursor(event) }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

    private func updateCursor(_ event: NSEvent) {
        if state?.lifted == true { return }
        switch ownDragView(event) {
        case is NSText, is NSTextField: NSCursor.iBeam.set()
        case is NSControl: NSCursor.arrow.set()
        default: NSCursor.openHand.set()
        }
    }

    // 入力欄とつまみ以外は、文字やボタンの上でも掴んで運べるようにする
    // 動かさずに離したときだけ、押した合図を元の部品へ渡してクリックとして扱う
    override func sendEvent(_ event: NSEvent) {
        guard event.type == .leftMouseDown, ownDragView(event) == nil else { return super.sendEvent(event) }
        SpringMover.shared.stop()
        let startMouse = NSEvent.mouseLocation
        let startOrigin = frame.origin
        let startTime = CACurrentMediaTime()
        var moved = false
        var distance: CGFloat = 0
        var up: NSEvent?

        trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: .infinity, mode: .eventTracking) { ev, stop in
            guard let ev else { return }
            let p = NSEvent.mouseLocation
            let dx = p.x - startMouse.x, dy = p.y - startMouse.y
            distance = hypot(dx, dy)

            if ev.type == .leftMouseDragged {
                if !moved && distance < 3 { return }
                if !moved {
                    moved = true
                    NSCursor.closedHand.set()
                    self.lift(true)
                }
                // 画面の外へ出した分は重く動かし、引っぱっている感じを出す
                let raw = NSRect(origin: NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy), size: self.frame.size)
                let inside = self.boundedFrame(raw)
                self.setFrameOrigin(NSPoint(
                    x: inside.minX + Self.rubberBand(raw.minX - inside.minX),
                    y: inside.minY + Self.rubberBand(raw.minY - inside.minY)
                ))
                return
            }
            up = ev
            stop.pointee = true
        }

        if moved {
            lift(false)
            // 画面の端で引っぱった後は、窓の外で離すこともある
            (frame.contains(NSEvent.mouseLocation) ? NSCursor.openHand : NSCursor.arrow).set()
        }
        // トラックパッドのクリックは数px揺れるので、短く小さい動きはクリックとみなす
        let quick = CACurrentMediaTime() - startTime < 0.35
        if !moved || (quick && distance < 12) {
            setFrameOrigin(startOrigin)
            if let up { postEvent(up, atStart: true) }
            super.sendEvent(event)
        } else {
            SpringMover.shared.move(self, to: boundedFrame(frame).origin)
        }
    }

    // 文字の選択やつまみの操作は、部品自身のドラッグに任せる
    private func ownDragView(_ event: NSEvent) -> NSView? {
        guard let content = contentView, let parent = content.superview else { return nil }
        var view = content.hitTest(parent.convert(event.locationInWindow, from: nil))
        while let v = view, v !== content {
            if v is NSText || v is NSControl { return v }
            view = v.superview
        }
        return nil
    }

    // 持ち上げたら少し縮め、横に振った速さに応じて傾ける。離したら弾んで戻す
    private func lift(_ on: Bool) {
        withAnimation(on ? .spring(response: 0.2, dampingFraction: 0.6) : .spring(response: 0.4, dampingFraction: 0.45)) {
            state?.lifted = on
            if !on { state?.tilt = 0 }
        }
        carryTimer?.invalidate()
        var lastX = NSEvent.mouseLocation.x
        let until = CACurrentMediaTime() + 0.8
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] t in
            guard let self else { return t.invalidate() }
            if on, let state = self.state {
                let x = NSEvent.mouseLocation.x
                state.tilt += (max(-2.5, min(2.5, (lastX - x) * 0.25)) - state.tilt) * 0.2
                lastX = x
            } else if CACurrentMediaTime() > until {
                t.invalidate()
            }
            // 窓の影は中身の形から作られるので、縮みや傾きに合わせて作り直す
            self.invalidateShadow()
        }
        RunLoop.main.add(timer, forMode: .common)
        carryTimer = timer
    }

    private static func rubberBand(_ over: CGFloat) -> CGFloat {
        let limit: CGFloat = 60
        return over.sign == .minus
            ? -limit * (1 - 1 / (-over / limit + 1))
            : limit * (1 - 1 / (over / limit + 1))
    }

    // メニューバーを持たないアプリなので、入力欄のcmd+A・C・V・X・Zをここで受ける
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.shift) == .command,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        let shift = event.modifierFlags.contains(.shift)
        let action: Selector?
        switch key {
        case "a": action = #selector(NSText.selectAll(_:))
        case "c": action = #selector(NSText.copy(_:))
        case "v": action = #selector(NSText.paste(_:))
        case "x": action = #selector(NSText.cut(_:))
        case "z": action = shift ? Selector(("redo:")) : Selector(("undo:"))
        default: action = nil
        }
        if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

final class FinishedPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hidesOnDeactivate = false
        isMovable = false
        setFrame(screen.frame, display: true)
    }

    // OKをEnterでも押せるようにする
    override var canBecomeKey: Bool { true }
}

struct FinishedView: View {
    @ObservedObject var state: AppState
    let ok: () -> Void

    var body: some View {
        ZStack {
            // 赤をゆっくり明滅させる
            TimelineView(.animation) { ctx in
                Color.red.opacity(0.6 + 0.1 * sin(ctx.date.timeIntervalSinceReferenceDate * 3.5))
            }
            VStack(spacing: 18) {
                Text("時間です")
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                if !state.task.isEmpty {
                    Text(state.task)
                        .font(.system(size: 26, weight: .bold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                Button(action: ok) {
                    Text("OK")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.red)
                        .frame(width: 160, height: 52)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .foregroundStyle(Color.white)
            .padding(40)
        }
        .ignoresSafeArea()
    }
}

struct CelebrationView: View {
    static let duration: TimeInterval = 3.4

    struct Piece {
        let x, delay, speed, sway, phase, spin: Double
        let color: Color
    }

    let celebration: Celebration
    private let start = Date()
    private let pieces: [Piece] = {
        let colors: [Color] = [.red, .orange, .yellow, .green, .mint, .blue, .purple, .pink]
        return (0..<180).map { _ in
            Piece(
                x: .random(in: 0...1), delay: .random(in: 0...0.7), speed: .random(in: 0.8...1.4),
                sway: .random(in: 2...5), phase: .random(in: 0...6.3), spin: .random(in: -8...8),
                color: colors.randomElement()!
            )
        }
    }()

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            ZStack {
                Canvas { g, size in
                    for p in pieces {
                        let tt = t - p.delay
                        guard tt > 0 else { continue }
                        let y = -20 + tt * p.speed * size.height / 1.6
                        guard y < size.height + 20 else { continue }
                        let x = p.x * size.width + sin(tt * p.sway + p.phase) * 30
                        var piece = g
                        piece.translateBy(x: x, y: y)
                        piece.rotate(by: .radians(tt * p.spin))
                        piece.fill(Path(CGRect(x: -4, y: -7, width: 8, height: 14)), with: .color(p.color))
                    }
                }
                card
                    .scaleEffect(1 - exp(-t * 8) * cos(t * 12) * 0.3)
                    .opacity(t < 0.15 ? t / 0.15 : min(1, max(0, (Self.duration - t) / 0.6)))
            }
        }
        .ignoresSafeArea()
    }

    private var card: some View {
        VStack(spacing: 10) {
            Text("おめでとう！")
                .font(.system(size: 52, weight: .heavy, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [.orange, .pink, .purple], startPoint: .leading, endPoint: .trailing))
            if !celebration.task.isEmpty {
                Text(celebration.task)
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            if celebration.elapsed >= 1 {
                Text(Self.elapsedText(celebration.elapsed) + "で完了")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.secondary)
            }
        }
        .foregroundStyle(Color.black)
        .padding(.horizontal, 44)
        .padding(.vertical, 28)
        .background(RoundedRectangle(cornerRadius: 24).fill(Color.white).shadow(radius: 24))
    }

    private static func elapsedText(_ t: TimeInterval) -> String {
        let s = Int(t)
        if s >= 3600 { return "\(s / 3600)時間\(s % 3600 / 60)分" }
        if s >= 60 { return "\(s / 60)分\(s % 60)秒" }
        return "\(s)秒"
    }
}

final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    // SwiftUIが矢印に戻さないよう、カーソルは窓側で決める
    override func cursorUpdate(with event: NSEvent) {}
}

// 掴んで運ぶのは窓側で行う。ここは背景のクリックと右クリックのメニューを受ける
final class DragAreaView: NSView {
    var onClick: (() -> Void)?
    var menuItems: [(String, () -> Void)] = []
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        // 入力欄の外を押したら入力欄から外し、打った値を確定させる
        if let window, window.isKeyWindow { window.makeFirstResponder(self) }
    }

    // 押した時点で戻すと、離した合図が戻った後の「−」に届いて、またたたまれる
    override func mouseUp(with event: NSEvent) {
        onClick?()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard !menuItems.isEmpty else { return nil }
        let menu = NSMenu()
        for (title, action) in menuItems {
            let item = ClosureMenuItem(title: title, action: action)
            menu.addItem(item)
        }
        return menu
    }
}

extension NSWindow {
    // 窓が一番多く重なっている画面の、メニューバーとDockを除いた範囲に収めた位置
    func boundedFrame(_ f: NSRect, margin: CGFloat = 6) -> NSRect {
        let overlap: (NSScreen) -> CGFloat = {
            let r = $0.frame.intersection(f)
            return r.isNull ? 0 : r.width * r.height
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.max { overlap($0) < overlap($1) }.flatMap { overlap($0) > 0 ? $0 : nil }
            ?? NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
        guard let vf = screen?.visibleFrame.insetBy(dx: margin, dy: margin) else { return f }
        let x = min(max(f.minX, vf.minX), vf.maxX - f.width)
        let y = min(max(f.minY, vf.minY), vf.maxY - f.height)
        return NSRect(x: x, y: y, width: f.width, height: f.height)
    }
}

// 少し行き過ぎてから止まる、減衰するバネで窓を動かす
final class SpringMover {
    static let shared = SpringMover()
    private var timer: Timer?

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func move(_ window: NSWindow, to target: NSPoint) {
        stop()
        let from = window.frame.origin
        guard hypot(from.x - target.x, from.y - target.y) > 0.5 else { return }
        let t0 = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            let t = CACurrentMediaTime() - t0
            if t >= 0.9 {
                window.setFrameOrigin(target)
                self?.stop()
                return
            }
            let k = exp(-t * 8) * cos(t * 13)
            window.setFrameOrigin(NSPoint(
                x: target.x + (from.x - target.x) * k,
                y: target.y + (from.y - target.y) * k
            ))
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, action: @escaping () -> Void) {
        handler = action
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}

struct DragArea: NSViewRepresentable {
    var onClick: (() -> Void)? = nil
    var menuItems: [(String, () -> Void)] = []

    func makeNSView(context: Context) -> DragAreaView { DragAreaView() }

    func updateNSView(_ view: DragAreaView, context: Context) {
        view.onClick = onClick
        view.menuItems = menuItems
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let state = AppState()
    private let timer = TimerModel()
    private var panel: FloatingPanel!
    private var cancellables = Set<AnyCancellable>()
    private let topRightKey = "panelTopRight"

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = FloatingPanel()
        panel.state = state
        let host = ClickThroughHostingView(rootView: RootView(state: state, timer: timer))
        host.sizingOptions = []
        panel.contentView = host
        panel.delegate = self
        panel.setFrame(NSRect(origin: originFor(size: fullSize), size: fullSize), display: true)
        panel.orderFrontRegardless()

        // 隠すときは中身を丸に替えてから縮め、戻すときは広げてから中身を替える
        // 逆の順だと、大きい中身が小さい窓で切れた絵が一瞬出る
        state.$mini.dropFirst().sink { [weak self] mini in
            if mini {
                DispatchQueue.main.async { self?.resize(to: miniSize) }
            } else {
                self?.resize(to: fullSize)
            }
        }.store(in: &cancellables)

        state.$celebration.compactMap { $0 }.sink { [weak self] c in
            self?.showCelebration(c)
        }.store(in: &cancellables)

        timer.$alerted.removeDuplicates().sink { [weak self] alerted in
            alerted ? self?.showFinished() : self?.hideFinished()
        }.store(in: &cancellables)

    }

    // 隠すボタンの位置がずれないよう、右上の角を基準に大きさを変える
    private func resize(to size: NSSize) {
        let f = panel.frame
        let origin = NSPoint(x: f.maxX - size.width, y: f.maxY - size.height)
        SpringMover.shared.stop()
        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
        panel.invalidateShadow()
        SpringMover.shared.move(panel, to: panel.boundedFrame(panel.frame).origin)
    }

    private func originFor(size: NSSize) -> NSPoint {
        if let saved = UserDefaults.standard.string(forKey: topRightKey) {
            let p = NSPointFromString(saved)
            let rect = NSRect(x: p.x - size.width, y: p.y - size.height, width: size.width, height: size.height)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) {
                return rect.origin
            }
        }
        let vf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: vf.maxX - size.width - 16, y: vf.maxY - size.height - 16)
    }

    // 0になったら、どの画面も赤く覆って知らせる。OKで閉じて次へ進む
    private var finishedWindows: [NSWindow] = []

    private func showFinished() {
        hideFinished()
        for screen in NSScreen.screens {
            let w = FinishedPanel(screen: screen)
            let host = NSHostingView(rootView: FinishedView(state: state) { [weak self] in
                self?.timer.reset()
            })
            host.sizingOptions = []
            w.contentView = host
            w.orderFrontRegardless()
            finishedWindows.append(w)
        }
        finishedWindows.first?.makeKey()
    }

    private var celebrationWindows: [NSWindow] = []

    // 紙吹雪は操作のじゃまをしないよう、クリックを下の窓へ通して数秒で消える
    private func showCelebration(_ c: Celebration) {
        celebrationWindows.forEach { $0.orderOut(nil) }
        celebrationWindows = NSScreen.screens.map { screen in
            let w = FinishedPanel(screen: screen)
            w.ignoresMouseEvents = true
            let host = NSHostingView(rootView: CelebrationView(celebration: c))
            host.sizingOptions = []
            w.contentView = host
            w.orderFrontRegardless()
            return w
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + CelebrationView.duration) { [weak self] in
            self?.celebrationWindows.forEach { $0.orderOut(nil) }
            self?.celebrationWindows = []
        }
    }

    private func hideFinished() {
        finishedWindows.forEach { $0.orderOut(nil) }
        finishedWindows = []
        NSWorkspace.shared.frontmostApplication?.activate()
    }

    func windowDidMove(_ notification: Notification) {
        let f = panel.frame
        UserDefaults.standard.set(NSStringFromPoint(NSPoint(x: f.maxX, y: f.maxY)), forKey: topRightKey)
    }
}

// MARK: - Timer

final class TimerModel: ObservableObject {
    @Published private(set) var total: TimeInterval = 15 * 60
    @Published private(set) var remaining: TimeInterval = 15 * 60
    @Published private(set) var running = false
    // 「8:00まで」のように時刻で決めたときの終わりの時刻
    @Published private(set) var until: Date?

    private var endDate: Date?
    private var ticker: Timer?
    // 0になって知らせた状態。OKで次へ進むまで続く
    @Published private(set) var alerted = false

    var overtime: Bool { remaining <= 0 && (running || alerted) }

    var progress: Double {
        total > 0 ? max(0, min(1, remaining / total)) : 0
    }

    var display: String {
        let secs = remaining >= 0 ? Int(remaining.rounded(.up)) : Int((-remaining).rounded(.down))
        let h = secs / 3600, m = (secs % 3600) / 60, s = secs % 60
        let body = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
        return remaining < 0 ? "-" + body : body
    }

    func set(minutes: Int) {
        until = nil
        total = TimeInterval(minutes * 60)
        remaining = total
        alerted = false
        if running { endDate = Date().addingTimeInterval(remaining) }
    }

    // 文字盤に打った時間で始める。"25" は25分、"1:30" は1分30秒、"1:00:00" は1時間
    func start(typed text: String) -> Bool {
        let t = (text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text)
            .replacingOccurrences(of: "：", with: ":")
            .filter { $0.isNumber || $0 == ":" }
        let parts = t.split(separator: ":", omittingEmptySubsequences: false).map { Int($0.isEmpty ? "0" : $0) }
        guard !parts.isEmpty, parts.count <= 3, !parts.contains(where: { $0 == nil }) else { return false }
        let n = parts.map { $0! }
        let secs: Int
        switch n.count {
        case 1: secs = n[0] * 60
        case 2: secs = n[0] * 60 + n[1]
        default: secs = n[0] * 3600 + n[1] * 60 + n[2]
        }
        guard secs > 0 else { return false }
        until = nil
        total = TimeInterval(secs)
        remaining = total
        alerted = false
        if running { endDate = Date().addingTimeInterval(remaining) } else { start() }
        return true
    }

    // 指定の時刻までを数えてすぐ始める。過ぎた時刻なら翌日のその時刻にする
    func set(until target: Date) {
        until = target
        total = target.timeIntervalSinceNow
        remaining = total
        alerted = false
        if running { endDate = target } else { start() }
    }

    // "8:00" "8" "800" "20:30" "８：００" などを、次に来るその時刻にする
    static func parseClock(_ text: String, now: Date = Date()) -> Date? {
        let t = (text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text)
            .replacingOccurrences(of: "：", with: ":")
            .filter { $0.isNumber || $0 == ":" }
        var h: Int?, m = 0
        if t.contains(":") {
            let parts = t.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            h = Int(parts[0])
            m = parts[1].isEmpty ? 0 : (Int(parts[1]) ?? -1)
        } else if t.count <= 2 {
            h = Int(t)
        } else if t.count <= 4 {
            h = Int(t.dropLast(2))
            m = Int(t.suffix(2)) ?? -1
        }
        guard let h, (0...24).contains(h), (0...59).contains(m), !(h == 24 && m > 0) else { return nil }
        let cal = Calendar.current
        var date = cal.date(bySettingHour: h % 24, minute: m, second: 0, of: now)!
        if h == 24 { date = cal.date(byAdding: .day, value: 1, to: date)! }
        if date <= now { date = cal.date(byAdding: .day, value: 1, to: date)! }
        return date
    }

    func toggle() {
        if running {
            pause()
            until = nil
        } else {
            start()
        }
    }

    func reset() {
        pause()
        until = nil
        remaining = total
        alerted = false
    }

    private func start() {
        guard remaining > 0 || alerted else { return }
        endDate = Date().addingTimeInterval(remaining)
        running = true
        ticker = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(ticker!, forMode: .common)
    }

    private func pause() {
        if let endDate { remaining = endDate.timeIntervalSinceNow }
        ticker?.invalidate()
        ticker = nil
        endDate = nil
        running = false
    }

    private func tick() {
        guard let endDate else { return }
        remaining = endDate.timeIntervalSinceNow
        if remaining <= 0 && !alerted { alerted = true }
    }
}

// MARK: - Views

struct RootView: View {
    @ObservedObject var state: AppState
    @ObservedObject var timer: TimerModel

    var body: some View {
        Group {
            if state.mini {
                MiniView(state: state, timer: timer) { state.mini = false }
            } else {
                FullView(state: state, timer: timer)
            }
        }
        // 大きさを変える途中も、右上の角に合わせて描く
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .scaleEffect(state.lifted ? 0.94 : 1)
        .rotationEffect(.degrees(state.tilt))
        .environment(\.colorScheme, state.theme.light ? .light : .dark)
    }
}

struct MiniView: View {
    @ObservedObject var state: AppState
    @ObservedObject var timer: TimerModel
    let restore: () -> Void

    var body: some View {
        ZStack {
            // 完全に透明な部分はクリックが下の窓へ抜けるため、見えない下地を敷く
            Rectangle().fill(Color.black.opacity(0.01))
            Circle().fill(state.theme.color.opacity(max(state.opacity, 0.6)))
            if timer.running || timer.overtime {
                Circle()
                    .trim(from: 0, to: timer.overtime ? 1 : timer.progress)
                    .stroke(timer.overtime ? Color.red : Color.green, lineWidth: 2.5)
                    .rotationEffect(.degrees(-90))
                    .padding(3)
            }
        }
        .frame(width: miniSize.width, height: miniSize.height)
        .overlay(DragArea(onClick: restore))
        .help("クリックで戻す")
    }
}

struct FullView: View {
    @ObservedObject var state: AppState
    @ObservedObject var timer: TimerModel
    @FocusState private var focused: Bool

    private let presets = [15, 30, 60]

    var body: some View {
        VStack(spacing: 6) {
            if state.showSettings {
                SettingsView(state: state)
            } else {
            HStack(spacing: 6) {
                Group {
                    if state.editing == .task {
                        TextField("この時間でやること", text: $state.input)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 4)
                            .frame(height: 18)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.15)))
                            .focused($focused)
                            .onSubmit { submit(leaving: false) }
                            .onExitCommand(perform: endEditing)
                    } else {
                        Button { beginEditing(.task) } label: {
                            Text(state.task.isEmpty ? "やることを入力" : state.task)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.primary.opacity(state.task.isEmpty ? 0.45 : 1))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(state.task.isEmpty ? "押してやることを入力" : state.task)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                RoundIconButton(name: "gearshape.fill", help: "設定") {
                    if state.editing != .none { endEditing() }
                    state.showSettings = true
                }
                Button { state.mini = true } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.primary.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .help("隠す")
            }

            if state.editing == .duration {
                inputField(placeholder: "25", size: 34, width: 150, height: 44)
            } else {
                Button(action: { beginEditing(.duration) }) {
                    Text(timer.display)
                        .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(timer.overtime ? Color.red : Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .help("押して時間を入力。25 で25分、1:30 で1分30秒")
            }

            HStack(spacing: 4) {
                if state.editing == .until {
                    inputField(placeholder: "8:00", size: 11, width: 52, height: 18)
                    Text("まで").font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.75))
                } else {
                    ForEach(presets, id: \.self) { m in
                        Button("\(m)分") {
                            if state.editing != .none { endEditing() }
                            timer.set(minutes: m)
                        }
                            .buttonStyle(ChipStyle(width: 38))
                    }
                    Button(timer.until.map { Self.clock.string(from: $0) } ?? "時刻") { beginEditing(.until) }
                        .buttonStyle(ChipStyle(width: 54, active: timer.until != nil))
                        .help("指定の時刻まで数える")
                }
            }

            HStack(spacing: 18) {
                IconButton(name: "arrow.counterclockwise", help: "リセット") {
                    if state.editing != .none { endEditing() }
                    timer.reset()
                }
                IconButton(name: timer.running ? "pause.fill" : "play.fill", help: "開始/一時停止") {
                    if state.editing != .none { submit(leaving: true) }
                    timer.toggle()
                }
                IconButton(name: "checkmark.circle.fill", help: "完了") { complete() }
            }
            }
        }
        // 背景が薄いときは、後ろの窓に文字が埋もれないよう影を付ける
        .shadow(color: (state.theme.light ? Color.white : Color.black).opacity(state.opacity < 0.5 ? 0.9 : 0), radius: 2)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: fullSize.width, height: fullSize.height)
        .background(
            DragArea(menuItems: [
                ("終了", { NSApp.terminate(nil) }),
            ])
            // 完全に透明でもクリックが下の窓へ抜けないよう、ごく薄い下地を残す
            .background(RoundedRectangle(cornerRadius: 14).fill(state.theme.color.opacity(max(state.opacity, 0.01))))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        )
        .onChange(of: focused) { _, now in
            guard !now else { return }
            // 文字盤から時刻の欄へ移るときも一瞬外れるので、少し待って本当に外れたときだけ確定する
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if !focused && state.editing != .none { submit(leaving: true) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            if state.editing != .none { submit(leaving: true) }
        }
    }

    private func inputField(placeholder: String, size: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        TextField(placeholder, text: $state.input)
            .textFieldStyle(.plain)
            .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
            .multilineTextAlignment(.center)
            .frame(width: width, height: height)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.18)))
            .focused($focused)
            .onSubmit { submit(leaving: false) }
            .onExitCommand(perform: endEditing)
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "H:mm"
        return f
    }()

    private func beginEditing(_ mode: AppState.Editing) {
        if state.editing != .none && state.editing != mode { submit(leaving: true) }
        state.input = mode == .task ? state.task : ""
        state.editing = mode
        NSApp.windows.first { $0 is FloatingPanel }?.makeKey()
        DispatchQueue.main.async { focused = true }
        if state.outsideClickMonitor == nil {
            state.outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
                if state.editing != .none { submit(leaving: true) }
            }
        }
    }

    // Enterでは打ち直せるよう入力欄に残し、外へ出たときは打てた分だけで確定して閉じる
    private func submit(leaving: Bool) {
        if state.editing == .task {
            state.task = state.input.trimmingCharacters(in: .whitespaces)
            endEditing()
            return
        }
        if state.input.trimmingCharacters(in: .whitespaces).isEmpty {
            endEditing()
            return
        }
        let ok: Bool
        switch state.editing {
        case .duration:
            ok = timer.start(typed: state.input)
        case .until:
            if let target = TimerModel.parseClock(state.input) {
                timer.set(until: target)
                ok = true
            } else {
                ok = false
            }
        case .none, .task:
            ok = true
        }
        if ok || leaving { endEditing() } else { state.input = "" }
    }

    // 早めに終わったとき。かかった時間を添えてお祝いし、タイマーとタスク欄を次に向けて空ける
    private func complete() {
        if state.editing != .none { endEditing() }
        let elapsed = timer.running || timer.remaining < timer.total ? timer.total - max(timer.remaining, 0) : 0
        timer.reset()
        state.celebration = Celebration(task: state.task, elapsed: elapsed)
        state.task = ""
    }

    // 打ち終えたら、キー入力を元のアプリへ返す
    private func endEditing() {
        if let m = state.outsideClickMonitor {
            NSEvent.removeMonitor(m)
            state.outsideClickMonitor = nil
        }
        state.editing = .none
        focused = false
        NSWorkspace.shared.frontmostApplication?.activate()
    }
}

struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("設定").font(.system(size: 12, weight: .semibold))
                Spacer()
                RoundIconButton(name: "checkmark", help: "閉じる") { state.showSettings = false }
            }

            HStack(alignment: .top, spacing: 6) {
                Text("背景色").font(.system(size: 11)).frame(width: 36, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach([0, 8], id: \.self) { row in
                        HStack(spacing: 6) {
                            ForEach(row..<min(row + 8, Theme.all.count), id: \.self) { i in
                                swatch(i)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                Text("透明度").font(.system(size: 11)).frame(width: 36, alignment: .leading)
                Slider(value: Binding(get: { 1 - state.opacity }, set: { state.opacity = 1 - $0 }), in: 0...1)
                    .controlSize(.small)
                Text("\(Int(((1 - state.opacity) * 100).rounded()))%")
                    .font(.system(size: 10).monospacedDigit())
                    .frame(width: 30, alignment: .trailing)
            }

            HStack(spacing: 6) {
                Button("終了") { NSApp.terminate(nil) }.buttonStyle(ChipStyle(width: 44))
            }
        }
        .foregroundStyle(Color.primary)
    }

    private func swatch(_ i: Int) -> some View {
        Button { state.themeIndex = i } label: {
            Circle()
                .fill(Theme.all[i].color)
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(Color.primary.opacity(0.35), lineWidth: 1))
                .overlay(Circle().stroke(Color.blue, lineWidth: 2).padding(-3).opacity(state.themeIndex == i ? 1 : 0))
        }
        .buttonStyle(.plain)
        .help(Theme.all[i].name)
    }
}

struct RoundIconButton: View {
    let name: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.primary.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct ChipStyle: ButtonStyle {
    var width: CGFloat = 32
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .frame(width: width, height: 18)
            .background(RoundedRectangle(cornerRadius: 5).fill(
                active ? Color.blue.opacity(0.55) : Color.primary.opacity(configuration.isPressed ? 0.3 : 0.12)
            ))
            .foregroundStyle(Color.primary)
    }
}

struct IconButton: View {
    let name: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary.opacity(0.9))
        .help(help)
    }
}
