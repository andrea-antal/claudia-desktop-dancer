// Claudia, a desktop dancer for macOS. Sprites cut from BLISS (claudia.gallery). Claudia by anabology.
import AppKit

struct Anim {
    let reps: [NSBitmapImageRep], cgs: [CGImage]
    let height: Double   // her median height in pixels, so every move shows at one size

    init(_ name: String) {
        let dir = Bundle.main.resourceURL!.appendingPathComponent("Sprites/\(name)")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        reps = files.filter { $0.pathExtension == "png" }.sorted { $0.path < $1.path }
            .compactMap { (try? Data(contentsOf: $0)).flatMap(NSBitmapImageRep.init(data:)) }
        cgs = reps.compactMap(\.cgImage)
        height = (try? String(contentsOf: dir.appendingPathComponent("height"), encoding: .utf8))
            .flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? Double(reps[0].pixelsHigh)
    }

    // frame index at time t (24 fps), forward then back: the film clips don't loop, so this hides the seam
    func index(_ t: Double) -> Int {
        let n = reps.count, i = Int(t * 24)
        guard n > 1 else { return 0 }
        let k = i % (2 * n - 2)
        return k < n ? k : 2 * n - 2 - k
    }
    var cycle: Double { Double(max(2 * reps.count - 2, 1)) / 24 }   // seconds for one forward-and-back play
}

// Plus! Dancer's "Select Dancer" list: each outfit's moves, danced in turn, and the move she fights the cursor with.
let looks = [("Holo Dancer", ["dance", "hoop", "kick"], "kick"), ("Cyber Trench", ["spin", "fight"], "fight"),
             ("Start", ["start"], "start"), ("Window Dress", ["window"], "window")]

final class Item: NSMenuItem {
    let run: () -> Void
    init(_ title: String, on: Bool = false, _ run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self; state = on ? .on : .off
    }
    required init(coder: NSCoder) { fatalError() }
    @objc func fire() { run() }
}

final class SpriteView: NSView {
    let sprite = CALayer()
    weak var app: App?
    var grab = NSPoint.zero, dragged = false, lastDrag = (p: NSPoint.zero, t: 0.0)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer!.addSublayer(sprite)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }

    override func mouseDown(with e: NSEvent) {
        guard let app else { return }
        let m = NSEvent.mouseLocation
        grab = NSPoint(x: m.x - app.pet.x, y: m.y - app.pet.y)
        dragged = false; lastDrag = (m, e.timestamp)
    }
    override func mouseDragged(with e: NSEvent) {
        guard let app else { return }
        let m = NSEvent.mouseLocation, dt = max(e.timestamp - lastDrag.t, 1 / 240)
        app.pet.mode = .held; dragged = true
        app.pet.vx = app.pet.vx * 0.5 + 0.5 * (m.x - lastDrag.p.x) / dt
        app.pet.vy = app.pet.vy * 0.5 + 0.5 * (m.y - lastDrag.p.y) / dt
        app.pet.x = m.x - grab.x; app.pet.y = m.y - grab.y
        lastDrag = (m, e.timestamp)
    }
    override func mouseUp(with e: NSEvent) {
        guard let app else { return }
        if dragged {   // throw her
            app.pet.mode = .fall
            app.pet.vx = min(max(app.pet.vx, -4000), 4000); app.pet.vy = min(max(app.pet.vy, -4000), 4000)
        } else {       // poke her
            app.pet.mode = .fight; app.pet.timer = 1.2
        }
    }
    override func rightMouseDown(with e: NSEvent) {
        if let menu = app?.menu { NSMenu.popUpContextMenu(menu, with: e, for: self) }
    }
}

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let view = SpriteView(frame: .zero)
    let menu = NSMenu()
    var status: NSStatusItem!
    var anims: [String: Anim] = [:]
    var pet = Pet()
    var playlist = Playlist(looks: looks.map(\.1))
    var chase = true, size = 220.0
    var t = 0.0, lastMode = Mode.fall, lastTick = CACurrentMediaTime(), lastMouse = NSEvent.mouseLocation, mouseSpeed = 0.0

    func applicationDidFinishLaunching(_ n: Notification) {
        for name in Set(looks.flatMap(\.1)) { anims[name] = Anim(name) }
        playlist.look = Int.random(in: 0..<looks.count)

        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .statusBar   // above every window, under menus, like Plus! Dancer's "Always on Top"
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.contentView = view; view.app = self
        panel.orderFrontRegardless()

        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "✷"
        menu.delegate = self; status.menu = menu

        // she drops in from the top of the screen
        let s = NSScreen.main!.frame
        pet.x = s.midX + .random(in: -s.width / 4...s.width / 4); pet.y = s.maxY - size

        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [unowned self] _ in tick() }
        RunLoop.main.add(timer, forMode: .common)
    }

    func tick() {
        let now = CACurrentMediaTime(), dt = min(now - lastTick, 0.05); lastTick = now
        let m = NSEvent.mouseLocation
        mouseSpeed = mouseSpeed * 0.7 + 0.3 * hypot(m.x - lastMouse.x, m.y - lastMouse.y) / max(dt, 0.001)
        lastMouse = m

        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: pet.x, y: pet.y + 1)) } ?? NSScreen.main!
        pet.step(dt, World(floor: screen.visibleFrame.minY, minX: screen.frame.minX, maxX: screen.frame.maxX,
                           mouseX: m.x, mouseY: m.y, mouseSpeed: mouseSpeed, height: size, chase: chase))
        if pet.mode != lastMode { t = 0; lastMode = pet.mode }
        let frozen = pet.mode == .held || pet.mode == .fall, fighting = pet.mode == .fight
        if !frozen { t += dt }   // freeze while held or flying
        if !frozen && !fighting && playlist.advance(dt, cycle: anims[playlist.current]!.cycle) { t = 0 }

        let anim = anims[fighting ? looks[playlist.look].2 : playlist.current]!
        let i = anim.index(t)
        let scale = size / anim.height
        let w = Double(anim.reps[i].pixelsWide) * scale, h = Double(anim.reps[i].pixelsHigh) * scale
        let flip = pet.left && [.walk, .chase, .fight].contains(pet.mode)   // sprites face right

        panel.setFrame(NSRect(x: pet.x - w / 2, y: pet.y, width: w, height: h), display: false)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        view.sprite.frame = view.bounds
        view.sprite.contents = anim.cgs[i]
        view.sprite.setAffineTransform(flip ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
        CATransaction.commit()

        // click through everything except her
        if pet.mode != .held {
            let f = panel.frame, rep = anim.reps[i]
            var px = Int((m.x - f.minX) / f.width * Double(rep.pixelsWide))
            let py = Int((f.maxY - m.y) / f.height * Double(rep.pixelsHigh))
            if flip { px = rep.pixelsWide - 1 - px }
            let inside = f.contains(m) && px >= 0 && py >= 0 && px < rep.pixelsWide && py < rep.pixelsHigh
            panel.ignoresMouseEvents = !(inside && (rep.colorAt(x: px, y: py)?.alphaComponent ?? 0) > 0.15)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let credit = NSMenuItem(title: "Claudia by anabology", action: nil, keyEquivalent: ""); credit.isEnabled = false
        menu.addItem(credit)
        menu.addItem(.separator())
        menu.addItem(Item("Start Dancing", on: panel.isVisible) { [unowned self] in
            if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
        })
        menu.addItem(Item("Chase the Cursor", on: chase) { [unowned self] in chase.toggle() })

        let dancers = NSMenu()
        dancers.addItem(Item("Rotate", on: !playlist.locked) { [unowned self] in playlist.pick(nil); t = 0 })
        dancers.addItem(.separator())
        for (k, l) in looks.enumerated() {
            dancers.addItem(Item(l.0, on: playlist.locked && k == playlist.look) { [unowned self] in playlist.pick(k); t = 0 })
        }
        let pick = NSMenuItem(title: "Select Dancer", action: nil, keyEquivalent: ""); pick.submenu = dancers
        menu.addItem(pick)

        let sizes = NSMenu()
        for (label, h) in [("Small", 150.0), ("Medium", 220.0), ("Large", 320.0)] {
            sizes.addItem(Item(label, on: size == h) { [unowned self] in size = h })
        }
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: ""); sizeItem.submenu = sizes
        menu.addItem(sizeItem)
        menu.addItem(.separator())
        menu.addItem(Item("Quit Claudia") { NSApp.terminate(nil) })
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
