# 论文“游戏与关卡设计”章节素材

> 本文只整理游戏设计相关内容。文中的“可直接改写段落”仍需根据目标期刊、研究问题和最终冻结版本调整。

## 1. 章节建议结构

```text
3. System and Game Design
3.1 Core Dyadic Interaction
3.2 Input-to-Force Mapping
3.3 Visual and Feedback Design
3.4 Tutorial and Level Progression
3.5 Design Rationale
3.6 Implementation and Apparatus
```

如果论文篇幅有限，可以合并为：

```text
3. Game Design
3.1 Core Interaction
3.2 Five Cooperative Tasks
3.3 Feedback and Implementation
```

---

## 2. 核心概念

### 2.1 可直接改写段落

Dyadic Force 是一个本地双人协作滚球游戏。两名玩家分别位于同一球体的两侧，并通过连续二维方向输入向球体轮缘施力。双方大体同向输入时，合力主要推动球体平移；双方反向或方向失配时，输入会产生旋转、侧偏或打滑。因此，玩家并非分别控制两个独立角色，而是共同控制一个同时整合两人方向、力度与时序的物理对象。

### 2.2 需要强调的设计区别

该任务不同于：

- 两人轮流操作；
- 一人导航、一人执行；
- 两人各自控制独立角色；
- 投票后由系统执行；
- 将两人输入简单求平均后直接设置速度。

其核心是**同时、连续、耦合的双人控制**。

### 2.3 推荐配图

- `images/fig01_game_concept_hero.jpg`：概念；
- `images/fig02_split_screen_gameplay.png`：实际界面。

---

## 3. 输入与物理设计

### 3.1 输入映射

每个玩家的输入依次经过：

```text
原始二维输入
→ 设备校准
→ 径向死区
→ 幂次响应曲线
→ 条件增益
→ 虚拟作用力
```

当前协议相关参数：

- 径向死区：0.12；
- 响应曲线 γ：1.6；
- 满幅标度：8.0 游戏力单位。

注意：这些单位不是牛顿。

### 3.2 可直接改写段落

系统没有将输入直接映射为球体目标速度，而是将校准后的输入映射为作用于球体轮缘的虚拟力。该设计使平移和旋转由同一套物理规则自然产生，并保留启动差、力度不对称、方向冲突和微小纠偏等连续行为。幂次响应曲线扩大了中等幅度输入的精细控制范围，但不人为限制满幅输入；高速满推的代价主要由惯性、碰撞和转弯精度产生。

### 3.3 物理透明性

制作过程中曾考虑或实现隐藏的合作增益倍率，但最终删除。当前合作优势应来自：

- 两股力真实叠加；
- 两个接触点产生的平移和扭矩；
- 闲置侧摩擦；
- 方向失配导致的旋转与打滑；
- 路线几何对高速控制的要求。

### 3.4 设计论点

可用于论文的论点：

> 与使用不可见合作倍率相比，接触点施力使玩家能够通过球体的平移、旋转和阻力直接感知双方输入之间的关系。

该论点属于系统设计解释，不是已经通过用户研究验证的结论。

---

## 4. 分屏与视觉反馈

### 4.1 分屏

- P1 使用左侧视图；
- P2 使用右侧视图；
- 两个视图同时观察同一世界和球体；
- 相机分别以对应角色为关注点；
- 屏幕震动与触觉反馈独立。

### 4.2 输入箭头

每名玩家的箭头显示连续二维输入方向，而不是吸附到八方向。它承担两种功能：

1. 帮助玩家理解自身施力；
2. 让双方比较当前方向是否一致。

### 4.3 可直接改写段落

界面采用左右分屏，使每名玩家拥有稳定的局部视角，同时仍能观察共同控制的球体。角色旁的方向箭头连续显示当前输入方向，为玩家提供输入—运动之间的即时视觉映射。系统将共同轨迹、碰撞和任务结果作为主要反馈，而不向玩家展示个人贡献比例或算法推断的领导者，以避免将合作任务重新框定为个体竞争。

### 4.4 推荐配图与图注

图片：`images/fig02_split_screen_gameplay.png`

图注草案：

> **Figure X. Dyadic Force split-screen interface.** Each player views the same shared ball from a dedicated camera. Direction indicators beside the monkeys visualize each player’s continuous input, while the ball’s translation and rotation reflect the coupled forces.

中文图注草案：

> **图 X. Dyadic Force 双人分屏界面。** 两名玩家分别通过独立视图观察同一个球体；猴子旁的方向箭头显示连续输入，球体的平移与旋转共同反映两侧作用力。

---

## 5. 美术与场景设计

### 5.1 可直接改写段落

游戏采用自然主题的像素美术，以草地、水面、木围栏、树木、灌木和石块构成路线。除可撞门外，实验路段、扰动触发区和岔路确认线均不会以专门实验物体呈现。不同场景区域通过植被密度、地貌和道路宽度形成视觉分区，使玩家能够辨认长路线中的位置，同时避免暴露后台测量结构。

### 5.2 美术服务于任务的方式

- 道路宽度提示操作压力；
- 水面明确分隔第 5 关分支；
- 门前开阔区提示助跑；
- 难点后的空地提示恢复；
- 植被分区帮助长关导航；
- 地面箭头只提示路线，不标实验条件；
- 木质门与现有围栏统一风格。

### 5.3 不采用的视觉语言

- 实验区边框；
- 同步率仪表；
- 领导者图标；
- 受扰玩家高亮；
- 风险路线标签；
- 停车台；
- 明确的“测试开始/结束”装置；
- 宝箱或分数奖励。

### 5.4 概念图图注

图片：`images/fig01_game_concept_hero.jpg`

英文图注草案：

> **Figure X. Dyadic Force concept artwork.** Two monkeys jointly move a shared ball through a natural pixel-art environment. This promotional illustration communicates the game theme and is not a screenshot of the experimental interface.

中文图注草案：

> **图 X. Dyadic Force 概念主视觉。** 两只猴子在自然像素场景中共同推动同一个球体。该图为宣传性概念插画，不是实验界面截图。

---

## 6. 教学关设计

### 6.1 教学目标

教学关用于建立以下心智模型：

- 同向输入推动球体；
- 反向输入让球体旋转；
- 转弯前可以减速；
- 普通碰撞造成伤害；
- 停在传送门上完成关卡；
- 双方共同加速可以撞开门。

### 6.2 教学关为何需要门

早期教学关没有门，玩家第一次进入正式第 1 关时才接触该机制。新手反馈说明，这会把规则学习混入第一个正式试次。

近期调整：

- 教学关加入一扇低难度门；
- 教学关不限时；
- 教学门低于正式关阈值；
- 开门后才推进对应教程步骤。

### 6.3 可直接改写段落

练习关不设置倒计时，并在低惩罚环境中介绍移动、旋转、碰撞、终点停车和共同撞门。将门机制前置到练习关，是为了降低第一个正式关中规则学习与协作表现之间的混淆。练习数据可用于描述熟悉过程，但不与正式关的主要指标合并。

---

## 7. 五关渐进设计

### 7.1 总体原则

每个正式关集中诱发一种主要合作行为：

1. 共同起步；
2. 共同减速；
3. 弯道协调；
4. 失衡补偿；
5. 路线选择。

关卡通过自然重复提供多个事件样本，但不在单关中叠加大量新机制。

### 7.2 可直接改写总述

五个正式关卡形成从基础同步到协调适应和共同决策的渐进结构。第 1 关使用可撞门诱发共同起步，第 2 关通过长直道后的回转诱发共同减速，第 3 关在连续左右弯中观察转向与纠偏，第 4 关在宽阔路线中短暂降低一名玩家的输入能力，第 5 关则让双方在短窄与长宽路线之间形成连续选择。除门外，所有实验标注和判定区域均对玩家不可见。

---

## 8. 第 1 关：共同起步

### 8.1 设计

- 三扇规则一致的可撞门；
- 门之间保留直线助跑与缓弯；
- 成功和失败撞门均不扣血；
- 失败的代价是时间和重新组织；
- 启动时间差被记录，但不作为严格失败条件。

### 8.2 行为机会

- 共同启动；
- 持续同向施力；
- 失败后重新同步；
- 多次门之间的学习。

### 8.3 图注草案

图片：`images/fig03_level_1_joint_start.jpg`

> **Figure Xa. Level 1—Joint Start.** Repeated straight sections and breakable gates create multiple opportunities for the dyad to coordinate acceleration.

---

## 9. 第 2 关：共同减速

### 9.1 设计

- 长直道鼓励建立速度；
- 两次回转迫使双方在入弯前减速；
- 外侧边界保留普通碰撞伤害；
- 不使用门、分叉或输入扰动。

### 9.2 行为机会

- 谁先开始减小输入；
- 双方是否共同反向制动；
- 高速入弯后的过冲；
- 出弯重新加速。

### 9.3 图注草案

图片：`images/fig04_level_2_joint_braking.jpg`

> **Figure Xb. Level 2—Joint Braking.** Long straights lead into broad reversals, requiring both players to reduce or reverse their input before turning.

---

## 10. 第 3 关：弯道协调

### 10.1 设计

- 长距离样条路线；
- 左右弯数量接近平衡；
- 不同半径和长度；
- 弯道间穿插恢复段；
- 植被分区帮助位置识别。

### 10.2 行为机会

- 转向发起；
- 方向一致性；
- 纠偏贡献；
- 左右弯中的领导切换；
- 出弯过冲和恢复。

### 10.3 图注草案

图片：`images/fig05_level_3_curve_coordination.jpg`

> **Figure Xc. Level 3—Curve Coordination.** Alternating left and right curves provide repeated observations of turn initiation, following, and correction.

---

## 11. 第 4 关：失衡补偿

### 11.1 设计

- 路线本身较宽；
- 主要由直道、缓弯和恢复空间构成；
- 第 4 关固定施加真实输入干扰；
- A/B 按可复现序列交替受扰；
- HUD 说明存在干扰，但不显示对象。

### 11.2 为什么路线要宽

如果同时使用窄道、急弯和输入失衡，将难以区分失败来自：

- 地图操作难度；
- 输入能力下降；
- 搭档未补偿；
- 玩家尚未恢复。

宽路降低地图本身的竞争解释。

### 11.3 图注草案

图片：`images/fig06_level_4_imbalance_compensation.jpg`

> **Figure Xd. Level 4—Imbalance Compensation.** A comparatively wide route limits geometric difficulty while the game temporarily reduces one player’s effective input.

---

## 12. 第 5 关：路线选择

### 12.1 设计

- 两个岔路；
- 每个岔路包含短窄和长宽两支；
- 两支最终汇合；
- 第二岔路交换短路线所在方向；
- 水面使两条路线在视觉上明确分离；
- 不显示投票或风险等级。

### 12.2 行为机会

- 初始路线偏好；
- 双方一致或冲突；
- 谁先改变方向；
- 最终共同选择；
- 进入分支后反转。

### 12.3 图注草案

图片：`images/fig07_level_5_route_choice.jpg`

> **Figure Xe. Level 5—Route Choice.** Two forks contrast a shorter, narrower route with a longer, wider route, allowing preference, conflict, and compromise to emerge during continuous control.

---

## 13. 五关组合图注

英文：

> **Figure X. The five cooperative levels.** (a) Joint Start uses breakable gates to elicit coordinated acceleration. (b) Joint Braking places broad reversals after long straights. (c) Curve Coordination balances left and right turns. (d) Imbalance Compensation uses a wide route while reducing one player’s effective input. (e) Route Choice presents shorter–narrower and longer–wider alternatives.

中文：

> **图 X. 五个正式合作关卡。**（a）共同起步通过可撞门诱发协调加速；（b）共同减速在长直道后设置回转；（c）弯道协调平衡左右转向；（d）失衡补偿在宽路中降低一名玩家的有效输入；（e）路线选择提供短窄与长宽两类路径。

---

## 14. 门、传送和反馈设计

### 14.1 可撞门

门不是单纯速度墙，还检查：

- 球体沿门法线前进；
- 双方都在有效施力；
- 双方方向大体一致；
- 合力主要朝向门。

成功：

- 取消阻挡；
- 打开或破裂；
- 粒子、震屏和触觉反馈；
- 不扣血。

失败：

- 晃动和轻微反弹；
- 不扣血；
- 离开接触范围后才允许新尝试。

### 14.2 传送门

终点要求球体进入并稳定停留，而不是高速穿过。传送门使用：

- 靠近变亮；
- 保留漩涡；
- 独立特效层；
- 渐强触觉；
- 成功后转入结算。

### 14.3 碰撞和死亡

- 普通障碍按冲击强度扣血；
- 生命以半心为最小单位；
- 重碰撞可触发死亡爆裂和重生；
- 门碰撞属于单独免伤类别。

---

## 15. 设计迭代的论文化表达

### 15.1 新手反馈驱动的门再标定

可写：

> Early internal testing relied heavily on keyboard input and underestimated gate difficulty under analog controllers. A subsequent novice controller playtest showed that even the first gate approached the participants’ practical difficulty ceiling. We therefore introduced a lower-threshold tutorial gate and standardized formal gates to the original entry-level configuration.

注意：

- 这属于形成性试玩，不是正式用户研究；
- 如没有参与者数量和记录，不应报告统计结果；
- 可以作为设计迭代过程。

### 15.2 L4/L5 拓扑重做

可写：

> Initial extensions changed obstacle placement without sufficiently differentiating the route topology. The two levels were redesigned around distinct switchback/compensation and fork/choice structures so that each level elicited a different cooperative behavior rather than merely presenting a reskinned course.

### 15.3 同步分析卡顿

可写：

> During development, synchronous session-wide analysis at trial termination introduced visible pauses at success and failure. This exposed a production-level validity risk: data infrastructure can become part of the participant experience. The final collection build should therefore separate raw-log durability from deferred or incremental derived analysis.

只有在修复完成后，才能把最后一句改成“we separated”。

---

## 16. 实现细节速查

| 项目 | 当前实现 |
|---|---|
| 引擎 | Godot 4.6 |
| 渲染 | Forward Plus |
| 语言 | GDScript |
| 球体 | `RigidBody2D` + shader 伪 3D |
| 输入 | 双键盘或双手柄 |
| 方向 | 连续二维 |
| 关卡数据 | `LevelDef` + `.tres` |
| 世界构建 | `WorldBuilder` |
| 分屏 | P1 左、P2 右 |
| 美术 | Sprout Lands 等像素素材 |
| 语言 | 中文 / 英文 |
| 触觉 | Godot joy vibration，事件触发 |
| 平台 | 当前主要为 macOS |

---

## 17. 本章节写作边界

不要写：

- “五关已经证明能测量五种合作能力”；
- “方向一致性代表合作质量”；
- “第 3 关是第 4 关严格 baseline”；
- “所有手柄都具有相同触觉反馈”；
- “门难度已经最终校准”；
- “五关时长已经达到目标”；
- “异步导出问题已经修复”。

可以写：

- 五关被设计为诱发五类行为；
- 系统记录相关操作化指标；
- 形成性试玩促成了难度调整；
- 当前 pilot 将验证可玩性、时长和测量完整性。

