# 实验数据字典

本文档对应原始 schema `3.1.0` 与分析版本 `2.0.0`。当前现场流程是单次可行性预实验（协议 `pilot-1.0`），详见 [预实验 SOP](pilot_experiment_protocol.md)。

一组实验（一次应用运行）只产生两类文件：

- **过程记录**（`raw/`）：不可覆盖，是唯一原始数据。
- **结果记录**（`results/`）：可从过程记录重算；无数据的表不会创建空文件。

人工复核不在默认产出里。跨多组实验的总表由汇总脚本生成，不要手工拼接各 session 目录。

## 1. 保存位置、编码与缺失值

- 每次应用运行创建唯一目录：
  `user://experiments/dyad-<组号>/<UTC时间>/`。
  - `raw/`：不可覆盖的过程记录 `session.csv`、`frames.csv`、`events.csv`。
  - `results/`：有数据才写出的结果表，以及 `analysis_manifest.json`。
  - `qc/`：仅在显式生成复核包时出现。
- 标题页「打开数据文件夹」打开 `user://experiments/`；结算页打开当次 session 目录。
- macOS 导出后的实际位置在 Godot 用户数据目录下，可用
  `ProjectSettings.globalize_path("user://experiments")` 转为绝对路径。
- 所有 CSV 使用 UTF-8、CRLF 行尾、逗号分隔和 RFC 4180 双引号转义；固定列顺序。
- 缺失值统一为空字段，不使用 `0`、`NA` 或 `-1` 代替未知值。状态/删失字段会解释为何为空。
- 布尔值写为 `0/1`。浮点数最多保留 9 位有效小数。
- `frames.csv` 与 `events.csv` 只追加并每秒 flush；分析器只覆盖可重算的结果文件。
- 每次进入、重开或结算重试创建新 `trial_id`；同一 session 内原始文件不换名、不覆盖旧行。

## 2. 标识符、时钟与通用约定

| 字段 | 类型 / 单位 | 定义 |
|---|---|---|
| `schema_version` | 字符串 | 原始表结构版本，当前为 `3.1.0`。 |
| `analysis_version` | 字符串 | 结果算法版本，当前为 `2.0.0`。 |
| `session_id` | 字符串 | 一次应用运行的唯一 ID，格式 `<组号>_<UTC文件夹名>`，例如 `S1-D001_2026-08-15_032500Z`。 |
| `trial_id` | 字符串 | 每次关卡启动的唯一 ID，格式 `<session>-T####`。 |
| `life_id` | 字符串 | trial 内生命 ID，格式 `<trial>-L###`；死亡重生递增，死亡不新建 trial。 |
| `level_id` | 字符串 | 稳定关卡标识。 |
| `level_attempt_index` | 整数 | 当前 session 内该关第几次启动，从 1 递增。 |
| `monotonic_time_us` | μs | `Time.get_ticks_usec()` 单调时钟；日志器保证跨 frames/events 严格递增。不可与墙钟互换，也不可跨 session 比较。 |
| `session_elapsed_ms` | ms | `monotonic_time_us - session 起点`。 |
| `trial_elapsed_ms` | ms | `monotonic_time_us - trial 起点`；暂停期间仍增长。 |
| `physics_frame` | 帧号 | `Engine.get_physics_frames()`；事件可与最近物理帧关联。 |
| `protocol_version` | 字符串 | 当前单一流程版本，预实验为 `pilot-1.0`。不再使用全局 Baseline/Perturbation 分组。 |

## 3. 过程记录

这三张表是唯一不可替代的原始数据。跨组研究不要直接拼接 `frames.csv`。

### 3.1 `session.csv`

每个 session 一行。主键：`session_id`。用途：身份、条件、设备与标定上下文；汇总时的 join 锚点。

| 字段 | 类型 / 单位 | 定义 |
|---|---|---|
| `schema_version` | 字符串 | 见通用约定。 |
| `app_version` | 字符串 | Godot 项目版本；开发构建未配置时为 `dev`。 |
| `session_id` | 字符串 | 见通用约定。 |
| `dyad_id` | 假名化编号 | 组号，规范为 `S<采集站>-D<至少三位序号>`，例如 `S1-D001`。研究员只输入数字 `1`，系统从永久保存的本站编号生成完整值。 |
| `participant_A`, `participant_B` | 假名化编号 | 由组号自动生成 `S1-D001-A` / `S1-D001-B`。A/B 是稳定身份，不随左右屏变化。不得填写姓名。 |
| `relation_condition` | 枚举 | 正式数据仅为 `strangers`、`friends`。`unspecified` 不能锁定。 |
| `protocol_version` | 字符串 | 当前为 `pilot-1.0`。 |
| `side_assignment` | 字符串 | `A=P1;B=P2` 或 `A=P2;B=P1`；由组号奇偶自动写入。P1=左屏/槽 0，P2=右屏/槽 1。 |
| `started_utc` | ISO 8601 UTC | 唯一用于审计的系统墙钟；不参与时差计算。 |
| `platform` | 字符串 | `OS.get_name()`。 |
| `deadzone` | 归一化幅度 | 输入死区阈值。 |
| `curve_gamma` | 无量纲 | 输入响应曲线指数。 |
| `force_max` | 游戏力单位 | 满幅输入对应的力标度；不是经校准的牛顿。 |
| `physics_ticks_per_second` | Hz | 目标物理更新频率。 |
| `missing_identity_fields` | 分号列表 | 缺失身份字段；正常实验应为空。 |

### 3.2 `frames.csv`

READY/RUNNING 阶段每个物理帧至多一行，A/B 按参与者而不是设备槽位排列。逻辑键：`(session_id, trial_id, life_id, monotonic_time_us)`。用途：可复算一切协调、路线与扰动指标的过程轨迹。

#### 3.2.1 时钟与系统质量

除通用字段外：

| 字段 | 类型 / 单位 | 定义 |
|---|---|---|
| `physics_delta_s` | s | 本物理步长。 |
| `render_fps` | Hz | 记录时渲染帧率估计。 |
| `phase` | 枚举 | `ready`、`running`、`dead`、`finished`、`failed`、`unknown`。 |
| `system_quality` | 枚举 | `ok`；物理步长超过标称值 1.5 倍时 `late`；任一参与者断连时 `disconnected`。 |

#### 3.2.2 A/B 输入字段

以下字段分别带 `A_` 和 `B_` 前缀：

| 后缀 | 类型 / 单位 | 定义 |
|---|---|---|
| `slot` | 0/1 | 当前参与者映射到的 P1/P2 输入槽。 |
| `source` | 枚举 | `keyboard_wasd`、`keyboard_arrows`、`joypad`、`none`。 |
| `device_id` | 整数 | Godot 手柄 ID；键盘/无设备时按 InputHub 约定。 |
| `connected` | 0/1 | 记录帧时设备是否可用。 |
| `raw_x`, `raw_y` | [-1,1] | 原始二维输入。 |
| `calibrated_x`, `calibrated_y` | 归一化 | 校准后的二维输入。 |
| `deadzone_magnitude` | [0,1] | 应用死区后的幅度 `m1`。 |
| `curve_magnitude` | [0,1] | 应用响应曲线后的幅度 `m2`。 |
| `gain` | 比例 | 条件增益；扰动时通常约 0.5。 |
| `force_x`, `force_y` | 游戏力单位 | 施加于核心的参与者力分量。 |
| `force_magnitude` | 游戏力单位 | `sqrt(force_x² + force_y²)`。 |

#### 3.2.3 核心与路线字段

| 字段 | 类型 / 单位 | 定义 |
|---|---|---|
| `core_x`, `core_y` | px | 核心世界坐标。 |
| `velocity_x`, `velocity_y` | px/s | 核心线速度。 |
| `speed` | px/s | `sqrt(velocity_x² + velocity_y²)`。 |
| `angle_rad` | rad | 核心旋转角。 |
| `angular_velocity_rad_s` | rad/s | 核心角速度。 |
| `route_error_x`, `route_error_y` | px | 从路线最近投影点指向核心的误差向量。 |
| `route_signed_error` | px | 相对路线方向的有符号横向误差。 |
| `route_error_distance` | px | 误差向量长度。 |
| `route_progress` | [0,1] | 当前投影点沿中心线累计弧长比例。 |
| `route_max_progress` | [0,1] | 本生命截至当前的最大进度。 |
| `route_segment` | 整数 | 最近中心线线段索引。 |
| `inside_boundary` | 0/1 | `route_error_distance <= route_corridor_half_width`。 |
| `completion_dir_x`, `completion_dir_y` | 单位向量 | 关卡完成方向。 |
| `task_segment_id` | 字符串/空 | 当前主要实验路段 ID（`RouteSegmentZone`）。 |
| `task_segment_type` | 枚举/空 | `start`、`acceleration`、`brake_approach`、`left_turn`、`right_turn`、`recovery`、`perturb_candidate`、`choice_approach`、`choice_branch`。 |
| `active_gate_id` | 字符串/空 | 当前接触或判定中的门 ID。 |
| `active_choice_id` | 字符串/空 | 当前活跃岔路 ID。 |
| `current_branch` | 字符串/空 | 已提交分支标签（如 `narrow` / `wide`）。 |

### 3.3 `events.csv`

一行一事件。逻辑键：`(session_id, trial_id, monotonic_time_us, event_type)`。用途：试次结局、门/路段/岔路与扰动的权威离散源。

| 字段 | 类型 / 单位 | 定义 |
|---|---|---|
| `event_type` | 枚举 | 见下表。 |
| `phase` | 枚举/空 | 事件发生时的阶段。 |
| `slot` | 0/1/空 | 涉及的输入槽。 |
| `device_id` | 整数/空 | 涉及的手柄 ID。 |
| `gain` | 比例/空 | 扰动增益。 |
| `impact_strength` | 游戏碰撞单位/空 | 碰撞强度。 |
| `damage` | HP/空 | 实际伤害。 |
| `remaining_hp` | HP/空 | 伤害后的生命。 |
| `time_penalty_s` | s/空 | 死亡带来的时间扣减。 |
| `core_x`, `core_y` | px/空 | 事件位置。 |
| `outcome` | 枚举/空 | `success`、`timeout`、`restarted`、`quit`、`aborted`。 |
| `note` | 受控诊断文本/空 | 机器生成说明；参与者自由文本不得写入。 |
| `component_id` | 字符串/空 | 门 / 路段 / 岔路等组件 ID。 |
| `segment_id` | 字符串/空 | 关联实验路段 ID。 |
| `collision_category` | 枚举/空 | `ordinary_obstacle`、`breakable_gate`、`world_boundary`。 |
| `result_reason` | 受控枚举/空 | 如门失败原因 `speed_low`、`missing_A`、`missing_B`、`direction_conflict`、`off_axis`。 |
| `branch` | 字符串/空 | 岔路偏好或提交分支。 |
| `sequence_version` | 字符串/空 | 扰动隐藏序列版本。 |

#### 3.3.1 事件枚举

| 事件 | 含义 |
|---|---|
| `trial_created` | 创建不可覆盖的新 trial。 |
| `intro_dismissed` | 开场说明关闭；无说明时 note=`no_intro`。 |
| `run_start` | READY 后首次有效输入，正式计时开始。 |
| `collision` | 核心发生碰撞。 |
| `damage` | 碰撞产生实际伤害。 |
| `death_collision` | 最后致伤碰撞使 HP 到 0。 |
| `respawn_start`, `respawn_end` | 死亡演出开始、下一生命交还控制。 |
| `time_penalty` | 正式关死亡扣时。 |
| `pause`, `resume` | 暂停与恢复。单调 trial 时间包含暂停段。 |
| `restart_requested` | 暂停菜单请求重开；随后 `trial_end(restarted)`。 |
| `quit_mid_trial` | 中途返回选关或关卡树意外退出；随后 `trial_end(quit)`。 |
| `controller_disconnect`, `controller_reconnect` | 手柄热插拔；slot 尽量保留断开前映射。 |
| `perturb_on`, `perturb_off` | 第 4 关真实干扰开始/结束。补偿与恢复用干扰前 200 ms 局部基线。 |
| `perturb_candidate_enter` | 进入扰动候选路段并准备判定。 |
| `perturb_skipped` | 候选路段不合格而跳过。 |
| `segment_enter`, `segment_leave` | 球心进入/离开不可见实验路段。 |
| `gate_attempt`, `gate_failed`, `gate_opened` | 可撞门尝试 / 失败 / 成功开门。 |
| `choice_started` | 进入岔路观察区。 |
| `choice_preference_A`, `choice_preference_B` | A/B 初始持续输入偏好。 |
| `choice_conflict` | 双方初始偏好不一致。 |
| `branch_committed` | 球穿过确认线，锁定最终分支。 |
| `branch_reversal` | 退出已选分支并改走另一支。 |
| `goal_enter`, `goal_leave` | 进入/离开终点区域。 |
| `success` | 达成目标。 |
| `timeout_failure` | 限时耗尽。 |
| `app_abort` | 活跃 trial 随应用/窗口关闭而终止。 |
| `aborted_recovered` | 下次启动检测到缺失 `trial_end` 后追加的恢复标记。 |
| `trial_end` | trial 唯一逻辑终点，`outcome` 必填。 |

## 4. 结果记录

结果表均可从 `raw/` 重算。列顺序为：主键/条件 → 核心结果 → 质量控制 → 探索性指标。

研究时以核心字段为主要终点；质量字段解释缺失与样本是否可用；探索性字段供后续分析，不要默认当成主终点。

`analysis_manifest.json` 记录 schema/分析版本、阈值、各文件行数与 `written`/`omitted` 状态。它是机器审计清单，不是实验表。

### 4.1 核心结果：`trial_results.csv`

每个 `trial_id` 一行。所有关卡都写这张表。跨组研究的第一选择。

| 字段 | 层级 | 单位 / 枚举 | 定义或公式 |
|---|---|---|---|
| `analysis_version`, `session_id`, `trial_id`, `level_id`, `level_attempt_index`, `protocol_version` | 键 | — | 版本与键。 |
| `outcome` | 核心 | 枚举 | 最后一个 `trial_end.outcome`；缺失时 `incomplete`。重开/退出看这里，不再单独计数。 |
| `completion_time_ms` | 核心 | ms/空 | `trial_duration_ms - run_start_ms`；缺少 `run_start` 时为空。 |
| `direction_cosine_mean`, `direction_cosine_median` | 核心 | [-1,1] | 双方幅度均大于 0.20 时，`F_A·F_B/(|F_A||F_B|)` 的均值/中位数。 |
| `conflict_ratio` | 核心 | [0,1]/空 | 同时活动且余弦 `< -0.50` 的时长 / 同时活动时长。分母为 0 时为空。 |
| `startup_difference_ms` | 核心 | ms/空 | `B_start_ms - A_start_ms`；正数表示 A 先启动。 |
| `startup_status` | 核心 | 枚举 | `ok`、`missing_A`、`missing_B`、`missing_both`。 |
| `trial_leader` | 核心 | 枚举 | 启动领先、互相关领先、纠偏贡献 >60% 三项多数决；平票为 `ambiguous`。 |
| `collision_count`, `death_count` | 核心 | 次 | 对应事件计数。 |
| `mean_route_error` | 核心 | px | 路线绝对误差均值。 |
| `max_progress` | 核心 | [0,1] | 最大 `route_max_progress`。 |
| `trial_duration_ms` | 质量 | ms | frames/events 中最大 `trial_elapsed_ms`。 |
| `direction_valid_ms` | 质量 | ms | 方向余弦有效帧的 `physics_delta_s` 总和。 |
| `simultaneous_active_ms` | 质量 | ms | 双方同时超过活动阈值的时长。 |
| `xcorr_status` | 质量 | 枚举 | `ok` 或 `low_activity`。 |
| `A_start_ms`, `B_start_ms` | 探索 | ms/空 | 首次幅度 `>0.20` 且连续至少 100 ms 的候选起点。 |
| `intensity_difference_mean`, `intensity_difference_p95`, `intensity_difference_max` | 探索 | 归一化幅度 | 有效帧 `abs(|F_A|/force_max - |F_B|/force_max)`。 |
| `xcorr_lag_ms` | 探索 | ms/空 | 平滑后力变化率在 ±1000 ms 内归一化互相关绝对峰值的 lag；正值表示 A 领先。 |
| `xcorr_peak` | 探索 | [-1,1]/空 | 峰值的带符号相关。 |
| `xcorr_leader` | 探索 | 枚举 | `A`、`B`、`ambiguous`。 |
| `xcorr_confidence` | 探索 | [0,1] | 峰强度与第一/第二峰分离度的组合评分。 |
| `correction_A`, `correction_B` | 探索 | 归一化力·ms | 误差至少 2 px 时，各自沿 `-error` 正投影的时间积分。 |
| `p95_route_error`, `max_route_error` | 探索 | px | 路线绝对误差分位与最大。 |
| `outside_boundary_ms` | 探索 | ms | `inside_boundary=0` 帧的步长总和。 |
| `route_length` | 探索 | px | 连续核心坐标间欧氏距离总和。 |

不要使用：单 session 二次汇总表。组间比较请用 `_aggregate/trials.csv` 或 `dyads.csv`。

### 4.2 专项结果：仅有数据时生成

这些表按关卡机制出现。没有对应事件时文件不存在，不要补空表。

#### 4.2.1 `perturbation_results.csv`

每个真实 `perturb_on` 一行；`perturbation_id=<trial>-P###`。第 4 关的主结果。用干扰前 200 ms 局部基线计算补偿与恢复。

| 字段 | 层级 | 单位 / 枚举 | 定义 |
|---|---|---|---|
| `onset_ms`, `offset_ms` | 键 | ms | 扰动开始及同 slot 后续 `perturb_off`；无 off 时为观察终点。 |
| `perturbed_participant`, `perturbed_slot`, `gain` | 键 | — | 受扰者 A/B、设备槽和增益。 |
| `compensation_status` | 核心 | 枚举 | `valid`、`no_valid_compensation`、`not_eligible`、`censored`。 |
| `compensation_onset_ms` | 核心 | ms/空 | 未受扰者相对扰动前 200 ms 中位力的 `ΔF`，沿 `-error` 投影 ≥0.12 且持续 100 ms 的起点；还要求 400 ms 后误差至少下降 5%。 |
| `compensation_reaction_ms` | 核心 | ms/空 | `compensation_onset_ms - onset_ms`。 |
| `recovery_status` | 核心 | 枚举 | `recovered`、`censored`、`not_eligible`。 |
| `recovery_time_ms` | 核心 | ms/空 | 误差、速度、角速度均回到扰动前中位数 ± `max(协议下限, 3×MAD)` 并持续 500 ms 的稳定段起点相对 onset。 |
| `recovery_censored` | 质量 | 0/1 | trial 结束前未确认 500 ms 稳定则为 1。 |
| `recovery_observation_ms` | 质量 | ms | 实际观察上限；恢复时为确认稳定的时点，删失时为最后观测。 |
| `compensation_peak_projection` | 探索 | 归一化力/空 | 观察期最大 `ΔF·(-error_unit)/force_max`。 |
| `overshoot_status` | 探索 | 枚举 | `overshoot`、`none`、`not_eligible`。初始有符号误差小于 2 px 不适用。 |
| `overshoot_first_reverse_max` | 探索 | px/空 | 首次到达反侧后观测到的最大反向绝对误差。 |
| `overshoot_ratio` | 探索 | 比例/空 | `first_reverse_max / abs(扰动前有符号误差中位数)`。 |
| `overshoot_round_trips` | 探索 | 次 | 使用 2 px 滞回检测的跨侧次数整除 2。 |

#### 4.2.2 `gate_results.csv`

每个 trial × `gate_id` 一行。第 1/3/5 关专项。主键：`(trial_id, gate_id)`。

| 字段 | 层级 | 定义 |
|---|---|---|
| `attempt_count`, `fail_count`, `opened` | 核心 | 尝试次数、失败次数、是否开门。 |
| `result_reason` | 核心 | 首次失败原因，或开门后为 `opened`。 |
| `first_forward_speed`, `first_direction_cosine` | 探索 | 首次尝试时的前进速度与方向余弦；当前实现可能为空，需后续从 frames 补齐。 |

#### 4.2.3 `segment_results.csv`

每个进入/离开配对的实验路段一行。第 2/3/4 关弯道与减速共用，用 `segment_type` 区分。未闭合的 `segment_enter` 不写行。

| 字段 | 层级 | 定义 |
|---|---|---|
| `segment_id`, `segment_type` | 键 | 路段 ID 与类型。 |
| `enter_ms`, `exit_ms` | 核心 | 进入/离开时间。 |
| `entry_speed`, `mean_speed` | 核心 | 进入速度与路段内均速。 |
| `outside_hits` | 探索 | 路段内越界次数；当前实现记 0，需后续从 frames 补齐。 |

#### 4.2.4 `choice_results.csv`

每个 trial × `fork_id` 一行。第 5 关专项。

| 字段 | 层级 | 定义 |
|---|---|---|
| `pref_a`, `pref_b`, `conflict` | 核心 | A/B 初始偏好与是否冲突。 |
| `committed_branch` | 核心 | 最终锁定分支。 |
| `reversal_count` | 核心 | 改道次数。 |

## 5. 人工复核（按需，`qc/`）

默认结算和重算**不**生成复核文件。需要扰动效度验证时再运行：

```bash
godot --headless --path . --script res://tools/generate_review_package.gd -- \
  --session-dir "/absolute/path/to/experiments/dyad-S1-D001/2026-08-15_032500Z"
```

- `review_queue.csv`：按 `sha256(session_id|perturbation_id)` 稳定排序，抽取 `ceil(扰动数×0.20)`。自动字段不可手改；人工填写 `manual_valid`、`manual_onset_ms`、`manual_recovery_ms`、`note`。
- `review_<perturbation_id>.svg`：复核折线图。
- `review_report.json`：已填写样本的一致性统计（分类一致率、起点容差、差值均值/中位数）。没有人工填写时这些比率为空。

不要使用已删除的 `review_windows.csv`：窗口数据可从 `frames.csv` 按 `onset_ms ± 2000 ms` 切片。重算复核包会按 `perturbation_id` 保留四个人工字段。

## 6. 跨组汇总

全部实验完成后，不要手工合并各 session 的结果表。运行：

```bash
godot --headless --path . --script res://tools/aggregate_experiments.gd -- \
  --root "/absolute/path/to/experiments" \
  --out "/absolute/path/to/experiments/_aggregate" \
  [--reanalyze-missing] [--dyad S1-D001]
```

输出到 `_aggregate/`：

| 文件 | 来源 | 说明 |
|---|---|---|
| `sessions.csv` | 各 `raw/session.csv` | session 索引 + 路径、trial 数、原始完整性、缺失 `trial_end` 数。 |
| `trials.csv` | `trial_results.csv` | 研究主表；补齐 `dyad_id`、参与者、关系条件、`started_utc`、`session_dir`。 |
| `perturbations.csv` / `gates.csv` / `segments.csv` / `choices.csv` | 对应专项表 | 仅当至少一行时写出；同样补齐身份列。 |
| `dyads.csv` | 由 `trials.csv` 重算 | 按 `(dyad_id, protocol_version, level_id)` 汇总成功率、领导稳定性与均值。 |
| `aggregate_report.json` | 汇总过程 | 纳入/跳过/错误 session 与行数。 |

规则：

- 只纳入 schema `3.1.0` 且 analysis `2.0.0` 的 session。
- 版本不一致时拒绝静默混合，只写报告。
- 主键必须唯一：`session_id`、`trial_id`、`perturbation_id`，以及组件表的复合键。
- `monotonic_time_us` 不可跨 session 比较；跨组分析用 `started_utc` 与 `trial_elapsed_ms`。

## 7. 删失、失败和恢复规则

- 扰动前窗口为空或基线误差向量 `<2 px`：补偿、恢复、过冲为 `not_eligible`。
- 400 ms 误差检查窗口尚未完整观察到：补偿为 `censored`，而不是“无补偿”。
- trial 结束前未出现连续 500 ms 回稳：`recovery_censored=1`，保存实际 `recovery_observation_ms`。
- 中断恢复只追加 `aborted_recovered` 和 `trial_end(outcome=aborted)`，不修改既有行；随后自动重算结果文件。
- 任何结果写出失败都会使导出状态失败；结算页显示失败而不是静默宣称已保存。

## 8. 隐私与数据治理

- 只允许假名化编号：组号 `S1-D001`，参与者 `S1-D001-A` / `S1-D001-B`。允许字符为数字、`S`/`D`/`A`/`B` 与连字符。禁止姓名、邮箱、电话、学号或自由文本。
- `dyad_id`、`participant_A/B` 是假名化编号，不是匿名数据；编号映射不进 session 目录或 git。
- `device_id` 是本次系统运行的输入设备编号，不是受试者身份。
- `started_utc` 可能构成间接标识；共享前按伦理审批要求降精度或单独保管映射信息。
- 不要把编号映射表放进 session 目录或版本控制。
- SVG 和结果 CSV 含行为轨迹，应按原始实验数据同等级保护。

## 9. 重算与人工复核流程

1. 备份整个 session 目录；确认三个原始 CSV 可由标准 CSV 解析器读取。
2. 在项目根目录运行：

   ```bash
   godot --headless --path . --script res://tools/reanalyze_experiment.gd -- \
     --session-dir "/absolute/path/to/experiments/dyad-S1-D001/2026-08-15_032500Z"
   ```

3. 检查命令输出 `EXPERIMENT_REANALYSIS_OK`，并核对 `results/analysis_manifest.json` 的版本、阈值和 `outputs`。
4. 需要扰动复核时再运行 `generate_review_package.gd`。打开 `qc/review_queue.csv`，只填写 `manual_*` 与 `note`。
5. 再次运行复核命令，人工字段会按 `perturbation_id` 保留，并更新 `review_report.json`。
6. 用对应 SVG 或从 `frames.csv` 切片核对自动起点、恢复点及删失原因。
7. 全部实验结束后运行 `aggregate_experiments.gd`，以 `_aggregate/trials.csv` 做研究分析。

分析协议升级时应同时提升 `ANALYSIS_VERSION`、更新本字典、保留旧结果副本；原始 schema 未改变时不应修改 `session.csv`、`frames.csv`、`events.csv`。
