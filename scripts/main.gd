extends Node3D
## VR Fight entry point. Picks the VR or desktop rig, builds the arena, and runs the lobby and the
## three modes: Practice (dummy), Single Player (bot) and LAN (host or join). See docs/DESIGN.md.

enum Mode { LOBBY, PRACTICE, BOT, HOST, JOIN }

const PAD_MODES := [Mode.PRACTICE, Mode.BOT, Mode.HOST, Mode.JOIN]
const PAD_NAMES := ["PRACTICE", "VS\nBOT", "HOST\nLAN", "JOIN\nLAN"]
const CORNERS := [Vector3(0, 0, 1.2), Vector3(0, 0, -1.2)]  # start marks: red, blue
const FACING := [0.0, PI]  # red faces -Z, blue faces +Z
const POSE_HZ := 45.0
const STATE_HZ := 10.0
const RECOVER_HOLD := 1.5  # seconds of guard-up a downed player needs to show the referee
const END_SCREEN := 8.0

var settings: Dictionary
var rig  # VrRig or DesktopRig (same methods)
var fighters: Array[Fighter] = []
var me := 0  # index of my boxer: 0 red (host / solo), 1 blue (joined)
var mode := Mode.LOBBY
var match_: BoxingMatch  # runs where the rules are decided: solo, or on the host
var bot: BotBrain  # the Single Player opponent
var autopilot: BotBrain  # drives my own boxer with --bot-vs-bot
var dummy: DummyBrain
var net: Net
var sfx: Sfx
var boards: Array[Label3D] = []
var hud: Label3D
var visor: MeshInstance3D
var pads: Array[MeshInstance3D] = []

var _state := {}  # latest match state: from match_, or from the host
var _remote := {}  # latest pose of the remote boxer
var _practice := {}
var _hud_t := 0.0
var _flash := 0.0
var _down := false
var _got_up := false  # I'm down but have already got up; waiting for the count to reach 8
var _guard_t := 0.0
var _back_t := 0.0
var _end_t := -1.0
var _pose_t := 0.0
var _state_t := 0.0


func _ready() -> void:
	settings = Config.load_settings()
	var ts: float = settings.timescale
	if ts != 1.0:
		Engine.time_scale = ts
		Engine.physics_ticks_per_second = roundi(60 * ts)  # keep the per-tick step small
		Engine.max_physics_steps_per_frame = roundi(8 * ts)
	Arena.build(self)
	sfx = Sfx.new()
	add_child(sfx)
	for z in [-1.0, 1.0]:
		var b := Label3D.new()
		b.position = Vector3(0, 3.0, z * (Arena.HALF + 0.7))  # above head height across the ring
		b.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		b.font_size = 64
		b.pixel_size = 0.004
		b.outline_size = 12
		add_child(b)
		boards.append(b)

	var xr := XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr and xr.is_initialized():
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)  # the headset paces frames
		xr.refresh_rate_changed.connect(func(hz: float):  # one physics tick per displayed frame
			Engine.physics_ticks_per_second = roundi(hz)
			print("XR refresh %s Hz" % hz))
		xr.session_begun.connect(func():  # refresh rates are only known once the session runs
			print("XR refresh rates offered: %s" % xr.get_available_display_refresh_rates())
			if 90.0 in xr.get_available_display_refresh_rates():
				xr.display_refresh_rate = 90.0)  # Quest 2 starts at 72; hit speeds are tuned for 90 Hz
		rig = VrRig.new()
	else:
		rig = DesktopRig.new()
	add_child(rig)
	hud = Label3D.new()
	hud.position = Vector3(0, -0.05, -0.8)
	hud.font_size = 32
	hud.pixel_size = 0.0015
	hud.outline_size = 8
	hud.no_depth_test = true
	hud.render_priority = 10
	hud.visible = false
	rig.camera.add_child(hud)
	visor = MeshInstance3D.new()
	visor.mesh = Arena.sphere(0.2)
	var vm := StandardMaterial3D.new()
	vm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	vm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vm.cull_mode = BaseMaterial3D.CULL_DISABLED
	vm.no_depth_test = true
	vm.render_priority = 5
	visor.material_override = vm
	visor.visible = false
	rig.camera.add_child(visor)

	for i in 2:
		var f := Fighter.new().setup(Arena.RED if i == 0 else Arena.BLUE)
		add_child(f)
		fighters.append(f)
	_make_pads()
	net = Net.new()
	net.port = settings.port
	net.discovery_port = settings.discovery_port
	add_child(net)
	net.connected.connect(_on_net_connected)
	net.disconnected.connect(_on_net_lost)

	_enter_lobby()
	var start := {"practice": Mode.PRACTICE, "bot": Mode.BOT, "host": Mode.HOST, "join": Mode.JOIN}
	if start.has(settings.mode):
		_start(start[settings.mode])


# --- Lobby and modes ----------------------------------------------------------------------------

func _make_pads() -> void:
	for i in PAD_NAMES.size():
		var box := BoxMesh.new()
		box.size = Vector3(0.28, 0.28, 0.08)
		var pad := Arena.make(box, Color(0.95, 0.75, 0.2))
		pad.position = Vector3(-0.6 + 0.4 * i, 1.5, 0.35)
		var label := Label3D.new()
		label.text = PAD_NAMES[i]
		label.position = Vector3(0, 0.25, 0)
		label.font_size = 22
		label.pixel_size = 0.003
		label.outline_size = 8
		pad.add_child(label)
		add_child(pad)
		pads.append(pad)


func _enter_lobby() -> void:
	net.stop()
	mode = Mode.LOBBY
	match_ = null
	bot = null
	dummy = null
	autopilot = null
	_state = {}
	_remote = {}
	_end_t = -1.0
	_down = false
	me = 0
	fighters[0].visible = true
	fighters[0].set_body_visible(false)
	fighters[1].visible = false
	for p in pads:
		p.visible = true
	rig.place(Vector3(0, 0, 1.0), 0.0)
	_board("VR FIGHT\nPunch a pad to start")


func _start(m: Mode) -> void:
	for p in pads:
		p.visible = false
	mode = m
	me = 1 if m == Mode.JOIN else 0
	var mine := fighters[me]
	var foe := fighters[1 - me]
	mine.visible = true
	mine.set_body_visible(false)
	foe.set_body_visible(true)
	foe.visible = m == Mode.PRACTICE or m == Mode.BOT
	if settings.bot_vs_bot:
		autopilot = BotBrain.new(mine, foe, settings.bot_skill)
		mine.set_body_visible(true)
	_hud("Guard: %s\nBack to lobby: %s" % [rig.hints.guard, rig.hints.back], 3.0)
	match m:
		Mode.PRACTICE:
			dummy = DummyBrain.new(foe, Vector3(0, 0, -0.2), settings.dummy_sway)
			_place_me(Vector3(0, 0, 0.6), 0.0)
			_practice = {"hits": 0, "best": 0.0, "last": "-"}
		Mode.BOT:
			bot = BotBrain.new(foe, mine, settings.bot_skill)
			_new_match()
		Mode.HOST:
			if net.host() == OK:
				_board("HOST LAN\nWaiting for an opponent...\n%s" % _local_ip())
			else:
				_board("Could not host:\nport %d is in use" % settings.port)
		Mode.JOIN:
			net.join(settings.join)
			_board("JOIN LAN\nLooking for a host...")


func _new_match() -> void:
	match_ = BoxingMatch.new(settings)
	match_.event.connect(_on_host_event)
	fighters[1 - me].visible = true
	_state = match_.to_dict()
	_place_corners()


func _place_me(pos: Vector3, yaw: float) -> void:
	if autopilot:
		autopilot.pos = pos
	else:
		rig.place(pos, yaw)


func _place_corners() -> void:
	_place_me(CORNERS[me], FACING[me])
	if bot:
		bot.pos = CORNERS[1 - me]


func _check_pads() -> void:
	var f := fighters[me]
	for i in pads.size():
		for g in 2:
			var p := pads[i].to_local(f.gloves[g])
			if absf(p.x) < 0.2 and absf(p.y) < 0.2 and absf(p.z) < 0.12 and f.glove_vel[g].length() > 1.2:
				rig.buzz(g, 0.8)
				_start(PAD_MODES[i])
				return


func _unhandled_input(e: InputEvent) -> void:
	var key := e as InputEventKey
	if mode == Mode.LOBBY and key and key.pressed and key.keycode >= KEY_1 and key.keycode <= KEY_4:
		_start(PAD_MODES[key.keycode - KEY_1])


# --- Simulation -----------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	var mine := fighters[me]
	var foe := fighters[1 - me]
	var fighting: bool = _state.get("state", -1) == BoxingMatch.State.ROUND
	if autopilot:
		autopilot.update(dt, fighting)
	else:
		rig.move(dt, _down)
		_keep_in_ring()
		mine.head = rig.head_transform()
		mine.gloves[0] = rig.glove(0)
		mine.gloves[1] = rig.glove(1)
	match mode:
		Mode.PRACTICE:
			dummy.update(dt, mine.head.origin)
		Mode.BOT:
			bot.update(dt, fighting)
		Mode.HOST, Mode.JOIN:
			_follow_remote(foe, dt)
	for f in fighters:
		f.step(dt)
	if mode == Mode.LOBBY:
		_check_pads()
		return
	_detect_hits(mine, foe)
	if match_:
		match_.tick(dt)
		_state = match_.to_dict()
	_network(dt)
	_check_recovery(dt)
	_update_board()
	if _end_t > 0.0:
		_end_t -= dt
		if _end_t <= 0.0:
			_enter_lobby()


func _process(dt: float) -> void:
	_hud_t -= dt
	hud.visible = _hud_t > 0.0
	_flash = maxf(0.0, _flash - dt)
	var tint := Color(0, 0, 0, 0.8) if _down else Color(0.7, 0.0, 0.0, _flash * 2.0)
	visor.visible = tint.a > 0.01
	(visor.material_override as StandardMaterial3D).albedo_color = tint
	_back_t = _back_t + dt if rig.back_pressed() else 0.0
	if _back_t > 0.5 and mode != Mode.LOBBY:
		_back_t = 0.0
		_enter_lobby()


func _keep_in_ring() -> void:
	var h: Vector3 = rig.head_transform().origin
	var lim := Arena.HALF - 0.3
	var push := Vector3(clampf(h.x, -lim, lim) - h.x, 0.0, clampf(h.z, -lim, lim) - h.z)
	var foe := fighters[1 - me]
	if mode != Mode.LOBBY and foe.visible:
		var gap := h + push - foe.head.origin
		gap.y = 0.0
		if gap.length() < Fighter.MIN_GAP and gap.length() > 0.001:
			push += gap.normalized() * (Fighter.MIN_GAP - gap.length())
	if push != Vector3.ZERO:
		rig.shift(push)


func _detect_hits(mine: Fighter, foe: Fighter) -> void:
	if not foe.visible:  # no opponent yet (still waiting for the network)
		return
	for h in mine.punches_on(foe):
		if not autopilot:
			rig.buzz(h.hand, h.power)
		match mode:
			Mode.PRACTICE:
				sfx.thud(h.point, h.blocked)
				dummy.hit(mine.glove_vel[h.hand] * 0.02)
				_practice.hits += 1
				_practice.best = maxf(_practice.best, h.speed)
				_practice.last = "%s %.1f m/s" % [h.zone.to_upper(), h.speed]
			Mode.BOT, Mode.HOST:
				match_.register_hit(me, h.zone, h.power, h.blocked, h.behind)
			Mode.JOIN:
				net_hit.rpc_id(1, h.zone, h.power, h.blocked, h.behind)
	if mode == Mode.BOT:  # the bot's punches are local too
		for h in foe.punches_on(mine):
			match_.register_hit(1 - me, h.zone, h.power, h.blocked, h.behind)


func _check_recovery(dt: float) -> void:
	if autopilot or not _down or _got_up:
		_guard_t = 0.0
		return
	_guard_t = _guard_t + dt if rig.guard_up() else 0.0
	if _guard_t >= RECOVER_HOLD:
		_guard_t = 0.0
		_got_up = true
		_recover(me)
		_hud("YOU'RE UP\nBoxing resumes at 8", 1.1)


func _recover(f: int) -> void:
	if match_:
		match_.recover(f)
	elif mode == Mode.JOIN and f == me:
		net_recover.rpc_id(1)


func _brain_of(f: int) -> BotBrain:
	for b in [bot, autopilot]:
		if b and b.me == fighters[f]:
			return b
	return null


# --- Match events (same handling on solo, host and client) --------------------------------------

func _on_host_event(what: String, d: Dictionary) -> void:
	if mode == Mode.HOST:
		net_event.rpc(what, d)
	_on_match_event(what, d)


func _on_match_event(what: String, d: Dictionary) -> void:
	match what:
		"round_start":
			sfx.bell()
			_place_corners()
			_hud("ROUND %d\nBOX!" % d.round, 2.0)
		"round_end":
			sfx.bell()
			var cards := PackedStringArray()
			for c in d.cards:
				cards.append("%d-%d" % [c[0], c[1]])
			_hud("END OF ROUND %d\nJudges: %s" % [d.round, "  ".join(cards)], 4.0)
		"hit":
			sfx.thud(fighters[1 - int(d.attacker)].head.origin, d.blocked)
			if int(d.attacker) != me and not d.blocked:
				_flash = 0.15
				rig.buzz(0, 0.3)
				rig.buzz(1, 0.3)
		"knockdown":
			var f := int(d.fighter)
			_down = f == me
			_got_up = false
			_hud("YOU'RE DOWN!\nTo get up: %s" % rig.hints.guard if _down else "KNOCKDOWN!", 1.1)
			var brain := _brain_of(f)
			if brain:
				brain.on_knockdown(int(d.total))
		"count":
			var text := str(d.count)
			if _down:  # the count would otherwise hide how to get up
				text += "\nUp - boxing resumes at 8" if _got_up else "\nTo get up: %s" % rig.hints.guard
			_hud(text, 1.1)
			var brain := _brain_of(int(d.fighter))
			if brain and int(d.count) >= brain.recover_at:
				_recover(int(d.fighter))
		"resume":
			_up()
			_hud("BOX!", 1.0)
		"foul":
			_hud("%s\nWarning %d%s" % [d.kind, d.warnings, "  -  POINT DEDUCTED" if d.deducted else ""], 3.0)
		"match_over":
			_up()
			var text := _result_text(d)
			_hud(text, END_SCREEN)
			_board(text)
			_end_t = END_SCREEN
			print("MATCH_OVER ", JSON.stringify(d))
			if settings.quit_on_end:
				get_tree().create_timer(1.0, true, false, true).timeout.connect(get_tree().quit)


func _up() -> void:
	_down = false
	_got_up = false
	for b in [bot, autopilot]:
		if b:
			b.down = false


func _result_text(d: Dictionary) -> String:
	var lines := PackedStringArray()
	var w := int(d.winner)
	if w < 0:
		lines.append("DRAW")
	else:
		var how := {"KO": "by knockout", "TKO": "by technical knockout", "UD": "by unanimous decision",
			"MD": "by majority decision", "SD": "by split decision"}
		lines.append("%s WINS%s" % ["RED" if w == 0 else "BLUE", " - YOU!" if w == me else ""])
		lines.append(how.get(d.method, d.method))
	for t in d.totals:
		lines.append("%d - %d" % [t[0], t[1]])
	return "\n".join(lines)


# --- Network ------------------------------------------------------------------------------------

func _network(dt: float) -> void:
	if (mode != Mode.HOST and mode != Mode.JOIN) or not net.is_live():
		return
	_pose_t -= dt
	if _pose_t <= 0.0:
		_pose_t = 1.0 / POSE_HZ
		var f := fighters[me]
		net_pose.rpc(f.head, f.gloves[0], f.gloves[1])
	if match_:
		_state_t -= dt
		if _state_t <= 0.0:
			_state_t = 1.0 / STATE_HZ
			net_state.rpc(_state)


func _follow_remote(foe: Fighter, dt: float) -> void:
	if _remote.is_empty():
		return
	var k := 1.0 - exp(-30.0 * dt)
	if not foe.visible:
		foe.visible = true
		k = 1.0
	foe.head = foe.head.interpolate_with(_remote.h, k)
	foe.gloves[0] = foe.gloves[0].lerp(_remote.l, k)
	foe.gloves[1] = foe.gloves[1].lerp(_remote.r, k)


func _on_net_connected() -> void:
	if mode == Mode.HOST:
		_new_match()
	_hud("Opponent connected", 2.0)


func _on_net_lost() -> void:
	if mode == Mode.HOST or mode == Mode.JOIN:
		var finished := _end_t > 0.0
		_enter_lobby()
		if not finished:
			_hud("Connection lost", 3.0)


func _local_ip() -> String:
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			return ip
	return ""


@rpc("any_peer", "unreliable_ordered")
func net_pose(h: Transform3D, l: Vector3, r: Vector3) -> void:
	if mode == Mode.HOST or mode == Mode.JOIN:
		_remote = {"h": h, "l": l, "r": r}


# Trust boundary: only the host scores, and only for the joined boxer, with sane values.
@rpc("any_peer", "reliable")
func net_hit(zone: String, power: float, blocked: bool, behind: bool) -> void:
	if mode == Mode.HOST and match_ and zone in ["head", "body", "low"]:
		match_.register_hit(1, zone, clampf(power, 0.0, Fighter.MAX_POWER), blocked, behind)


@rpc("any_peer", "reliable")
func net_recover() -> void:
	if mode == Mode.HOST and match_:
		match_.recover(1)


@rpc("authority", "reliable")
func net_event(what: String, d: Dictionary) -> void:
	if mode == Mode.JOIN:
		_on_match_event(what, d)


@rpc("authority", "unreliable_ordered")
func net_state(d: Dictionary) -> void:
	if mode == Mode.JOIN:
		_state = d


# --- Text ---------------------------------------------------------------------------------------

func _update_board() -> void:
	if mode == Mode.PRACTICE:
		_board("PRACTICE\nHits %d    Best %.1f m/s\nLast: %s" % [_practice.hits, _practice.best, _practice.last])
		return
	if _state.is_empty() or int(_state.state) == BoxingMatch.State.OVER:
		return
	var s := _state
	var t := ceili(maxf(0.0, s.clock))
	var phase := "GET READY"
	match int(s.state):
		BoxingMatch.State.ROUND:
			phase = "ROUND %d/%d" % [s.round, s.rounds]
		BoxingMatch.State.KNOCKDOWN:
			phase = "COUNT %d" % s.count
		BoxingMatch.State.REST:
			phase = "REST"
	_board("%s   %d:%02d\nRED %d    BLUE %d" % [phase, t / 60, t % 60, roundi(s.health[0]), roundi(s.health[1])])


func _board(text: String) -> void:
	if mode != Mode.LOBBY:
		text += "\n%s: back to lobby" % rig.hints.back
	for b in boards:
		if b.text != text:
			b.text = text


func _hud(text: String, seconds: float) -> void:
	hud.text = text
	_hud_t = seconds
