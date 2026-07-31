# Dyadic Force

双人合力滚球原型 —— 两只猴子锁在大球直径两端，通过推力与扭矩一起驱动球体。

![分屏预览](docs/preview.png)

## 玩法

- **P1**：`WASD` 控制球上方 / 一侧的猴子  
- **P2**：方向键控制另一侧的猴子  
- 同向推 → 球平移；反向推 → 球原地旋转；单人推 → 又移又转，需要配合修正  
- 球有惯性和摩擦，启动与停下都靠力，不是直接改速度

## 当前实现

- 像素风伪 3D 球（shader 球面纹理 + 滚动 / 自转）
- 弹簧相机分屏：左跟 P1，右跟 P2；撞障碍时两侧同步震屏
- 猴子前后遮挡、脚下阴影、被拖走时的失衡动画
- 轻量像素暗角与分屏 HUD

## 运行

- 引擎：**Godot 4.6**（Forward Plus）
- 打开本仓库，运行主场景 `scenes/main.tscn`

## 操作

| 玩家 | 移动 |
| --- | --- |
| P1 | W A S D |
| P2 | ↑ ← ↓ → |

## 素材

场景与 UI 基于 [Sprout Lands](https://cupnooble.itch.io/sprout-lands-asset-pack) 风格素材；角色动画来自 Jungle Monkey Platformer 精灵表。详见 `assets/` 内说明。
