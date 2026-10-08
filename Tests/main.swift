// Behaviour checks for Brain.swift. Run: ./build.sh test
func world(mouse: (Double, Double) = (5000, 5000), speed: Double = 0, chase: Bool = false) -> World {
    World(floor: 100, minX: 0, maxX: 1000, mouseX: mouse.0, mouseY: mouse.1, mouseSpeed: speed, height: 200, chase: chase)
}
func run(_ p: inout Pet, _ w: World, seconds: Double) { for _ in 0..<Int(seconds * 60) { p.step(1 / 60, w) } }

// dropped from high up, she falls, bounces and lands on the floor
var p = Pet(x: 500, y: 900); p.mode = .fall; p.rand = { 0.99 }
run(&p, world(), seconds: 3)
precondition(p.y == 100 && p.mode == .dance, "lands: y=\(p.y) mode=\(p.mode)")

// walking reaches the target and faces the way she went
p = Pet(x: 500, y: 100); p.mode = .walk; p.targetX = 300; p.timer = 15; p.rand = { 0.99 }
run(&p, world(), seconds: 0.5)
precondition(p.left && p.x < 500, "walks left")
run(&p, world(), seconds: 5)
precondition(p.x == 300 && p.mode == .dance, "arrives: x=\(p.x) mode=\(p.mode)")

// the cursor is her ex: a fast swipe through her body starts a fight, facing him
p = Pet(x: 500, y: 100); p.mode = .dance; p.timer = 5
p.step(1 / 60, world(mouse: (450, 200), speed: 2000))
precondition(p.mode == .fight && p.left, "swipe starts a fight")

// a slow hover does not, so she can be picked up
p = Pet(x: 500, y: 100); p.mode = .dance; p.timer = 5
p.step(1 / 60, world(mouse: (500, 200), speed: 50))
precondition(p.mode == .dance, "hover is not a fight")

// chasing runs at the cursor and fights it on arrival
p = Pet(x: 100, y: 100); p.mode = .chase; p.timer = 6
for _ in 0..<240 where p.mode == .chase { p.step(1 / 60, world(mouse: (800, 150), chase: true)) }
precondition(p.mode == .fight && !p.left && p.x > 600, "chase ends in a fight: x=\(p.x) mode=\(p.mode)")

// thrown hard at a wall, she bounces back and stays on screen
p = Pet(x: 900, y: 500); p.mode = .fall; p.vx = 3000; p.rand = { 0.99 }
for _ in 0..<180 { p.step(1 / 60, world()); precondition(p.x >= 0 && p.x <= 1000, "on screen: x=\(p.x)") }
precondition(p.mode == .dance && p.y == 100, "lands after the wall")

// held: the brain leaves her where the mouse put her
p = Pet(x: 400, y: 700); p.mode = .held
run(&p, world(), seconds: 1)
precondition(p.x == 400 && p.y == 700, "held stays put")

// the playlist plays one outfit's moves in turn, then moves on to the next outfit
func play(_ l: inout Playlist, seconds: Double, cycle: Double) -> [String] {
    var seen = [l.current]
    for _ in 0..<Int(seconds * 60) where l.advance(1 / 60, cycle: cycle) { seen.append(l.current) }
    return seen
}
var l = Playlist(looks: [["dance", "hoop", "kick"], ["spin", "fight"], ["start"]])
precondition(play(&l, seconds: 39, cycle: 2) == ["dance", "hoop", "kick", "spin", "fight", "start", "dance", "hoop", "kick", "spin"],
             "rotates outfit by outfit")

// a long move plays twice, a short one repeats at most 4 times in a row
l = Playlist(looks: [["dance", "spin"]])
_ = play(&l, seconds: 2 * 2.5 - 0.1, cycle: 2.5); precondition(l.current == "dance", "long move: 2 plays")
_ = play(&l, seconds: 0.2, cycle: 2.5); precondition(l.current == "spin", "then the next move")
_ = play(&l, seconds: 4 * 0.4 - 0.3, cycle: 0.4); precondition(l.current == "spin", "short move: up to 4 plays")
_ = play(&l, seconds: 0.4, cycle: 0.4); precondition(l.current == "dance", "no more than 4")

// picking one outfit keeps her in it; picking none goes back to rotating
l = Playlist(looks: [["dance", "hoop"], ["spin"]])
l.pick(1)
precondition(play(&l, seconds: 20, cycle: 2).allSatisfy { $0 == "spin" }, "locked to the trench")
l.pick(nil)
precondition(play(&l, seconds: 10, cycle: 2).contains("dance"), "rotates again")

print("ok")
