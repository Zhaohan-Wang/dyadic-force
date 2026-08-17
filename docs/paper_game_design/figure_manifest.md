# 论文图片索引与来源说明

> 本表记录 `images/` 中每张图片的来源、尺寸、推荐用途和风险。正式投稿前应再次核对冻结版本、授权与会议格式要求。

## 1. 图片清单

| 编号 | 文件 | 尺寸 | 类型 | 推荐用途 | 当前状态 |
|---|---|---:|---|---|---|
| Fig. 1 | `fig01_game_concept_hero.jpg` | 1440×720 | 概念主视觉 | Introduction、系统概览 | 可用；必须注明非实际截图 |
| Fig. 2 | `fig02_split_screen_gameplay.png` | 1920×1080 | 实际游戏截图 | Apparatus、核心交互 | 当前最适合论文正文 |
| Fig. 3a | `fig03_level_1_joint_start.jpg` | 448×280 | 关卡概览 | 五关组合图 | 低分辨率；需冻结后重截 |
| Fig. 3b | `fig04_level_2_joint_braking.jpg` | 448×280 | 关卡概览 | 五关组合图 | 低分辨率；需冻结后重截 |
| Fig. 3c | `fig05_level_3_curve_coordination.jpg` | 448×280 | 关卡概览 | 五关组合图 | 低分辨率；需冻结后重截 |
| Fig. 3d | `fig06_level_4_imbalance_compensation.jpg` | 448×280 | 关卡概览 | 五关组合图 | 低分辨率；需冻结后重截 |
| Fig. 3e | `fig07_level_5_route_choice.jpg` | 448×280 | 关卡概览 | 五关组合图 | 低分辨率；需冻结后重截 |
| 补充 A | `fig08_title_art_without_logo.jpg` | 2752×1536 | 标题插画 | 作品集、补充材料 | 非实际截图 |
| 补充 B | `fig09_game_logo.png` | 691×381 | 透明 Logo | 图版、封面 | 论文正文通常不需要 |
| 补充 C | `fig10_macos_app_icon.png` | 1024×1024 | 应用图标 | 软件交付、作品集 | 不建议作核心论文图 |

## 2. 原始文件映射

| 论文包文件 | 仓库原始位置 |
|---|---|
| `fig01_game_concept_hero.jpg` | `docs/readme/hero.jpg` |
| `fig02_split_screen_gameplay.png` | `docs/preview.png` |
| `fig03_level_1_joint_start.jpg` | `docs/readme/level_1.jpg` |
| `fig04_level_2_joint_braking.jpg` | `docs/readme/level_2.jpg` |
| `fig05_level_3_curve_coordination.jpg` | `docs/readme/level_3.jpg` |
| `fig06_level_4_imbalance_compensation.jpg` | `docs/readme/level_4.jpg` |
| `fig07_level_5_route_choice.jpg` | `docs/readme/level_5.jpg` |
| `fig08_title_art_without_logo.jpg` | `assets/ui/title_bg.jpg` |
| `fig09_game_logo.png` | `assets/ui/title_logo.png` |
| `fig10_macos_app_icon.png` | `assets/ui/monkey_push_ball.png` |

这些文件是独立副本。原始图片更新后，论文包不会自动同步，需要重新复制或重新生成。

## 3. 推荐图注

### Fig. 1 — 概念主视觉

英文：

> **Figure 1. Dyadic Force concept artwork.** Two monkeys jointly move a shared ball through a natural pixel-art environment. The image communicates the game theme and is not a screenshot of the experimental interface.

中文：

> **图 1. Dyadic Force 概念主视觉。** 两只猴子在自然像素场景中共同推动一个球体。该图用于表达游戏主题，并非实验界面的实际截图。

### Fig. 2 — 双人分屏

英文：

> **Figure 2. Dyadic Force split-screen interface.** Each player observes the shared ball from a dedicated camera. Direction indicators beside the monkeys visualize continuous player input, while the ball’s translation and rotation reflect the coupled forces.

中文：

> **图 2. Dyadic Force 双人分屏界面。** 两名玩家分别通过独立视图观察共享球体；猴子旁的方向指示器显示连续输入，球体的平移与旋转共同反映两侧作用力。

### Fig. 3 — 五关

英文：

> **Figure 3. The five cooperative levels.** (a) Joint Start uses breakable gates to elicit coordinated acceleration. (b) Joint Braking places broad reversals after long straights. (c) Curve Coordination balances left and right turns. (d) Imbalance Compensation uses a wide route while reducing one player’s effective input. (e) Route Choice presents shorter–narrower and longer–wider alternatives.

中文：

> **图 3. 五个正式合作关卡。**（a）共同起步通过可撞门诱发协调加速；（b）共同减速在长直道后设置回转；（c）弯道协调平衡左右转向；（d）失衡补偿在宽路中降低一名玩家的有效输入；（e）路线选择提供短窄与长宽两类路径。

## 4. 来源与授权备注

### 4.1 场景像素素材

游戏场景主要使用 Sprout Lands Basic（Cup Nooble）：

- 允许修改；
- 允许非商业项目使用；
- 要求署名；
- 禁止重新分发原始素材包；
- 禁止 NFT 和 AI 训练用途；
- 商业用途需另行联系作者。

论文中的游戏截图属于项目输出，但最终投稿、开放材料和商业传播仍应保留署名并核对许可边界。

### 4.2 猴子与输入图

项目 README 提到 Jungle Monkey Platformer 角色素材以及 Controllers & Keyboard 输入图，但仓库当前未发现完整独立许可文件。正式发布前需要补充授权证据。

### 4.3 概念主视觉、标题插画、Logo 与图标

这些资产的完整创作来源和授权链目前未在本目录内单独记录。正式投稿或公开发布前应确认：

- 是否由项目成员创作；
- 是否使用生成式工具；
- 是否包含第三方素材；
- 是否允许论文、作品集和商业传播；
- 需要何种署名。

在来源未确认前，不应把它们标为“作者原创”。

## 5. 图片质量检查

### 5.1 正式投稿前

- [ ] 使用正式收数 commit 重新截取；
- [ ] 记录截图日期和 commit；
- [ ] 关闭调试信息；
- [ ] 检查参与者编号是否需要匿名化；
- [ ] 使用统一分辨率和缩放；
- [ ] 确保子图文字在最终版面可读；
- [ ] 输出会议要求的 DPI；
- [ ] 检查 RGB/CMYK 要求；
- [ ] 不拉伸低分辨率图片；
- [ ] 在图注中区分概念图与实际截图；
- [ ] 补齐素材授权和署名。

### 5.2 建议截图规格

实际游戏截图：

- 原生 1920×1080 或更高；
- PNG；
- 不经过有损压缩；
- 同一 UI 语言；
- 同一显示比例；
- 固定窗口或全屏模式。

关卡概览：

- 至少 1600 px 宽；
- 统一裁切比例；
- 保留完整路线；
- 另输出带后台标注的调试版；
- 调试版与玩家可见版分开。

## 6. 后续待补图片编号

| 预留编号 | 内容 | 用途 |
|---|---|---|
| Fig. 4 | 输入—校准—力—球体流程图 | 解释连续力映射 |
| Fig. 5 | 门成功/失败对比 | 解释共同起步机制 |
| Fig. 6 | 第 4 关扰动 HUD 与后台时序 | 解释操纵 |
| Fig. 7 | 第 5 关岔路及隐藏判定区 | 解释路线选择 |
| Fig. 8 | raw → analysis → aggregate 数据管线 | 解释可重算性 |
| Supplement S1 | 实验录入、配对、校准流程 | 补充方法 |
| Supplement S2 | 传送门三阶段 | 游戏反馈设计 |
| Supplement S3 | 结算共同轨迹 | 非竞技化反馈 |

