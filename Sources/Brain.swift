// What Claudia does next. Pure logic, no AppKit, so Tests/main.swift can drive it.
// Screen coordinates, y up. (x, y) is the point between her feet.

enum Mode { case dance, walk, chase, fight, held, fall }

struct World {
    var floor, minX, maxX: Double
    var mouseX, mouseY, mouseSpeed: Double
    var height: Double      // her height on screen
    var chase: Bool         // allowed to go after the cursor
}

struct Pet {
    var x = 0.0, y = 0.0, vx = 0.0, vy = 0.0
    var mode = Mode.fall
    var left = false        // facing left
    var timer = 0.0         // seconds left in this mode
    var targetX = 0.0
    var cooldown = 0.0      // seconds until she will fight again
    var rand: () -> Double = { .random(in: 0..<1) }

    static let gravity = 2400.0, walkSpeed = 90.0, runSpeed = 260.0

    mutating func step(_ dt: Double, _ w: World) {
        timer -= dt; cooldown -= dt
        if mode == .held { return }   // the mouse moves her
        let lo = w.minX + w.height * 0.25, hi = w.maxX - w.height * 0.25

        switch mode {
        case .fall:
            vy -= Pet.gravity * dt; x += vx * dt; y += vy * dt
            if x < lo { x = lo; vx = abs(vx) * 0.5 }
            if x > hi { x = hi; vx = -abs(vx) * 0.5 }
            if y <= w.floor {
                y = w.floor
                if vy < -600 { vy = -vy * 0.3; vx *= 0.6 } else { vx = 0; vy = 0; pick(w) }
            }
        case .walk, .chase:
            if mode == .chase { targetX = w.mouseX }
            let d = targetX - x, v = (mode == .chase ? Pet.runSpeed : Pet.walkSpeed) * dt
            left = d < 0
            x += min(max(d, -v), v)
            if (mode == .walk && abs(d) < 2) || timer <= 0 { pick(w) }
        case .fight:
            if timer <= 0 { mode = .dance; timer = 2 + rand() * 2 }
        case .dance:
            if timer <= 0 { pick(w) }
        case .held: break
        }
        x = min(max(x, lo), hi)

        // the cursor is her ex: a fast swipe through her body, or catching him, starts a fight
        let touching = abs(w.mouseX - x) < w.height * 0.4 && w.mouseY > y && w.mouseY < y + w.height
        if touching && cooldown <= 0 && mode != .fall && (w.mouseSpeed > 800 || mode == .chase) {
            mode = .fight; timer = 1.2; cooldown = 2.5; left = w.mouseX < x
        }
    }

    mutating func pick(_ w: World) {
        let r = rand()
        if w.chase && r < 0.25 { mode = .chase; timer = 6 }
        else if r < 0.55 { mode = .walk; targetX = w.minX + rand() * (w.maxX - w.minX); timer = 15 }
        else { mode = .dance; timer = 4 + rand() * 6 }
    }
}

// Which move she dances: one outfit's moves in turn, then the next outfit.
struct Playlist {
    let looks: [[String]]   // moves per outfit
    var look = 0, move = 0
    var locked = false      // stay in one outfit
    var elapsed = 0.0
    var current: String { looks[look][move] }

    // `cycle` is one play of the current move. A long move plays twice; a short one repeats until
    // about 2.5 s have passed, never more than 4 times in a row. True when the move changes.
    mutating func advance(_ dt: Double, cycle: Double) -> Bool {
        elapsed += dt
        let plays = min(max(2, (2.5 / cycle).rounded(.up)), 4)
        guard elapsed >= plays * cycle else { return false }
        elapsed = 0; move += 1
        if move == looks[look].count { move = 0; if !locked { look = (look + 1) % looks.count } }
        return true
    }

    // one outfit only, or nil to rotate through all of them
    mutating func pick(_ l: Int?) { locked = l != nil; look = l ?? look; move = 0; elapsed = 0 }
}
