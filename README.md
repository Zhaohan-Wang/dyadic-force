# Dyadic Force

双人合力滚球 —— 两只猴子锁在大球直径两端，通过推力与扭矩一起驱动球体。

![分屏预览](docs/preview.png)

## 玩法

- **P1**：`WASD` 或手柄 1  
- **P2**：方向键或手柄 2  
- 同向推 → 球平移；反向推 → 球原地旋转；撞障会掉血  
- 练习关无计时；正式关有倒计时、出生/重生点与终点

## 流程

`标题` → `实验信息录入（实验模式）` → `玩家配对` → `选关` → `关卡` → `结算`

- **练习关**：教程提示、无限时
- **正式关**：限时、生命值、终点判定、星级结算

开启实验模式后，数据写入游戏可写目录：

`user://experiments/dyad-<组号>/<UTC时间>/raw|analysis/`

标题页「打开数据文件夹」可直接进入该根目录。

## 文档

- [五关扩展需求](docs/five_level_expansion_requirements.md)：五个正式关的设计约束、组件、日志与验收标准。
- [实验数据字典](docs/experiment_data_dictionary.md)：原始 CSV（schema `2.1.0`）、派生分析与保存路径。

### 正式关主题（一关一挑战）

| 关卡 | 主题 | 主要机制 |
| --- | --- | --- |
| 1 GATE RUN | 共同起步 | 三扇可撞门（免伤），门间缓弯需重新加速 |
| 2 SWITCHBACK | 共同减速 | 长直道 + 两次回转 |
| 3 WOODLAND | 弯道协调 | 林间左右弯配对 + 2 扇门（复用第 1 关规则） |
| 4 UNSTEADY TRAIL | 失衡补偿 | 隐藏路段扰动 / Baseline 假触发 |
| 5 FORKED TRAILS | 路线选择 | 双岔路短窄 vs 长宽，汇合段 1 扇门 |

第 3/4/5 关的路线由样条曲线生成（无直角拐），宽度随难度变化，按林地 / 岩地 / 草甸 / 深林分区换植被与地面质感。
改完布局后跑 `tools/layout_audit.gd` 复核：它会打印路程、最窄通道、逐个弯道的半径与顶点，
输出可直接粘进 `.tres` 的 `route_centerline`，并在 `docs/layout_previews/` 生成真实美术图、可达性调试图和 1:1 局部图。

## 运行

- 引擎：**Godot 4.6**（Forward Plus）
- 主场景：`scenes/title_screen.tscn`

## 操作

| 玩家 | 键盘 | 手柄 |
| --- | --- | --- |
| P1 | W A S D | 左摇杆 / 十字键 |
| P2 | ↑ ← ↓ → | 左摇杆 / 十字键 |
| 菜单 | Enter / Space | A / 确认 |

配对界面（所有玩家必须主动确认，无默认绑定）：

- **加入**：P1 按 `WASD` 任意键、P2 按方向键任意键，或手柄按 **A** 认领空槽位
- **退出**：P1 键盘按 `X`、P2 键盘按 `Delete`，手柄按 **B**
- 双方都加入后 **START** 才可用；`Esc` 返回标题
- 手柄拔出时对应槽位自动腾空，重新加入即可

## UI 风格

- 界面复用 **Sprout Lands UI Pack**（面板 / 按钮 / 红心 / 图标）与
  **Controllers & Keyboard** 按键提示图（键帽 / 手柄键）
- 界面文字统一英文像素字体（素材字体仅含拉丁字形，混排中文会破坏像素风格）
- 所有弹入 / 聚焦 / 受击动效由 `Spring2D` + `UiSpring` 弹簧驱动

## 架构摘要

- Autoload：`GameState` / `InputHub` / `SceneDirector`
- 关卡数据：`resources/level_def.gd` + `levels/*.tres`
- 通用关卡场景：`scenes/level.tscn`（建岛、分屏、血量、计时、终点、重生）

## 素材

场景与 UI 基于 Sprout Lands 风格素材；角色动画来自 Jungle Monkey Platformer。
第 1 关可撞门用同一套栅栏木色与立柱；撞门尘土来自 Pixel Frog *Pixel Adventure 1*。详见 `assets/` 与 `assets/topdown/CREDITS.txt`。
