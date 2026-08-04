class_name HapticProfile
extends RefCounted
## 扣血量 → 震动档位。半格小震，一格及以上大震。

const LARGE_DAMAGE: float = 1.0

static func is_large_hit(damage: float) -> bool:
	return damage >= LARGE_DAMAGE
