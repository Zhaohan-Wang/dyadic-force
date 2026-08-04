extends Node
## 半心离散血量：空心显示必须对应死亡，禁止浮点残血。

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var def: LevelDef = LevelDef.new()
	def.ball_max_hp = 3.0
	var state: LevelState = LevelState.new()
	state.setup(def)
	state.start_running()

	assert(is_equal_approx(state.hp, 3.0), "start full")
	assert(not state.apply_damage(0.5), "half heart keeps alive")
	assert(is_equal_approx(state.hp, 2.5), "hp snaps to 2.5")
	assert(not state.apply_damage(1.0), "one heart keeps alive")
	assert(is_equal_approx(state.hp, 1.5), "hp snaps to 1.5")
	assert(state.apply_damage(1.5), "draining last 1.5 must kill")
	assert(is_equal_approx(state.hp, 0.0), "exact drain kills")

	state.setup(def)
	state.start_running()
	# 旧浮点残血：显示已可能空心，下一次伤害必须死亡归零
	state.hp = 0.25
	assert(state.apply_damage(0.5), "sub-half residue must die")
	assert(is_equal_approx(state.hp, 0.0), "residue cleared to zero")

	# 连续三次半心：3 → 0，第三次必死
	state.setup(def)
	state.start_running()
	assert(not state.apply_damage(0.5))
	assert(not state.apply_damage(0.5))
	assert(not state.apply_damage(0.5))
	assert(not state.apply_damage(0.5))
	assert(not state.apply_damage(0.5))
	assert(state.apply_damage(0.5), "sixth half-heart kills from 3.0")
	assert(is_equal_approx(state.hp, 0.0))

	var health: BallHealth = BallHealth.new()
	assert(is_equal_approx(health._damage_from_impact(90.0), 0.5), "threshold hit = half")
	assert(health._damage_from_impact(400.0) <= 1.5 + 0.001, "cap at 1.5")
	health.free()

	print("hp_half_heart_assert OK")
	get_tree().quit(0)
