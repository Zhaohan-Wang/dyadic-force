extends SceneTree
## 扣血档位映射回归；不需要手柄。

func _initialize() -> void:
	assert(not HapticProfile.is_large_hit(0.25), "quarter heart is small")
	assert(not HapticProfile.is_large_hit(0.5), "half heart is small")
	assert(not HapticProfile.is_large_hit(0.99), "just under one heart is small")
	assert(HapticProfile.is_large_hit(1.0), "one heart is large")
	assert(HapticProfile.is_large_hit(1.5), "one and a half is large")
	print("haptic_profile_assert OK")
	quit(0)
