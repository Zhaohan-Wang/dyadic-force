# 实验数据字典

本文档对应原始 schema `2.0.0` 与分析版本 `1.0.0`。原始数据只有
`session.csv`、`frames.csv`、`events.csv`；其余文件均可从这三份原始 CSV 重算。

## 1. 保存位置、编码与缺失值

- 每次应用运行创建唯一目录：
  `user://experiments/dyad-<组号>/<UTC时间>/`。
  - `raw/`：不可覆盖的原始日志 `session.csv`、`frames.csv`、`events.csv`。
  - `analysis/`：可重算的派生 CSV 与复核 SVG。
- 标题页「打开数据文件夹」打开 `user://experiments/`；结算页打开当次 session 目录。
- macOS 导出后的实际位置在 Godot 用户数据目录下，可用
  `ProjectSettings.globalize_path("user://experiments")` 转为绝对路径。
- 旧版扁平目录 `user://experiment_logs/<session_id>/` 仍可被恢复与重算读取。
- 所有 CSV 使用 UTF-8、CRLF 行尾、逗号分隔和 RFC 4180 双引号转义；固定列顺序。
- 缺失值统一为空字段，不使用 `0`、`NA` 或 `-1` 代替未知值。状态/删失字段会解释为何为空。
- 布尔值写为 `0/1`。浮点数最多保留 9 位有效小数。
- `frames.csv` 与 `events.csv` 只追加并每秒 flush；分析器只覆盖可重算的派生文件。
- 每次进入、重开或结算重试创建新 `trial_id`；同一 session 内原始文件不换名、不覆盖旧行。

## 2. 标识符、时钟与通用约定

| 字段 | 类型 / 单位 | 定义 |
|---|---|---|
| `schema_version` | 字符串 | 原始表结构版本，当前为 `2.0.0`。 |
| `analysis_version` | 字符串 | 派生算法版本，当前为 `1.0.0`。 |
| `session_id` | 字符串 | 一次应用运行的唯一 ID，格式 `<组号>_<UTC文件夹名>`，例如 `101_2026-08-13_051600Z`。 |
| `trial_id` | 字符串 | 每次关卡启动的唯一 ID，格式 `<session>-T####`。 |
| `life_id` | 字符串 | trial 内生命 ID，格式 `<trial>-L###`；死亡重生递增，死亡不新建 trial。 |
| `level_id` | 字符串 | 稳定关卡标识。 |
| `level_attempt_index` | 整数 | 当前 session 内该关第几次启动，从 1 递增。 |
| `monotonic_time_us` | μs | `Time.get_ticks_usec()` 单调时钟；日志器保证跨 frames/events 严格递增。不可与墙钟互换。 |
| `session_elapsed_ms` | ms | `monotonic_time_us - session 起点`。 |
| `trial_elapsed_ms` | ms | `monotonic_time_us - trial 起点`；暂停期间仍增长。 |
| `physics_frame` | 帧号 | `Engine.get_physics_frames()`；事件可与最近物理帧关联。 |
| `experiment_condition` | 枚举 | `baseline` 或 `perturbation`。 |

## 3. `session.csv`

每个 session 一行。

| 字段 | 类型 / 单位 | 定义 |
|---|---|---|
| `schema_version` | 字符串 | 见通用约定。 |
| `app_version` | 字符串 | Godot 项目版本；开发构建未配置时为 `dev`。 |
| `session_id` | 字符串 | 见通用约定。 |
| `dyad_id` | 去标识编号 | 二人组短编号。 |
| `participant_A`, `participant_B` | 去标识编号 | 参与者短编号，不得填写姓名。 |
| `relation_condition` | 枚举 | `unspecified`、`strangers`、`friends`、`partners`。 |
| `experiment_condition` | 枚举 | `baseline` 或 `perturbation`。 |
| `side_assignment` | 字符串 | `A=P1;B=P2` 或 `A=P2;B=P1`；P1=左屏/槽 0，P2=右屏/槽 1。 |
| `started_utc` | ISO 8601 UTC | 唯一用于审计的系统墙钟；不参与时差计算。 |
| `platform` | 字符串 | `OS.get_name()`。 |
| `deadzone` | 归一化幅度 | 输入死区阈值。 |
| `curve_gamma` | 无量纲 | 输入响应曲线指数。 |
| `force_max` | 游戏力单位 | 满幅输入对应的力标度；不是经校准的牛顿。 |
| `physics_ticks_per_second` | Hz | 目标物理更新频率。 |
| `missing_identity_fields` | 分号列表 | 缺失身份字段；正常实验应为空。 |

## 4. `frames.csv`

READY/RUNNING 阶段每个物理帧至多一行，A/B 按参与者而不是设备槽位排列。

### 4.1 时钟与系统质量

除通用字段外：

| 字段 | 类型 / 单位 | 定义 |
|---|---|---|
| `physics_delta_s` | s | 本物理步长。 |
| `render_fps` | Hz | 记录时渲染帧率估计。 |
| `phase` | 枚举 | `ready`、`running`、`dead`、`finished`、`failed`、`unknown`。 |
| `system_quality` | 枚举 | `ok`；物理步长超过标称值 1.5 倍时 `late`；任一参与者断连时 `disconnected`。 |

### 4.2 A/B 输入字段

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

### 4.3 核心与路线字段

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

## 5. `events.csv`

事件行包含全部通用时钟字段，以及：

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

### 5.1 事件枚举

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
| `perturb_on`, `perturb_off` | 输入缩减段开始/结束。 |
| `goal_enter`, `goal_leave` | 进入/离开终点区域。 |
| `success` | 达成目标。 |
| `timeout_failure` | 限时耗尽。 |
| `app_abort` | 活跃 trial 随应用/窗口关闭而终止。 |
| `aborted_recovered` | 下次启动检测到缺失 `trial_end` 后追加的恢复标记。 |
| `trial_end` | trial 唯一逻辑终点，`outcome` 必填。 |

## 6. 派生文件

### 6.1 `trial_summary.csv`

每个 `trial_id` 一行。

| 字段 | 单位 / 枚举 | 定义或公式 |
|---|---|---|
| `analysis_version`, `session_id`, `trial_id`, `level_id`, `level_attempt_index`, `experiment_condition` | — | 版本与键。 |
| `outcome` | 枚举 | 最后一个 `trial_end.outcome`；缺失时 `incomplete`。 |
| `trial_duration_ms` | ms | frames/events 中最大 `trial_elapsed_ms`。 |
| `completion_time_ms` | ms | `trial_duration_ms - run_start_ms`；缺少 `run_start` 时为空。 |
| `direction_cosine_mean`, `direction_cosine_median` | [-1,1] | 双方幅度均大于 0.20 时，`F_A·F_B/(|F_A||F_B|)` 的均值/中位数。 |
| `direction_valid_ms` | ms | 方向余弦有效帧的 `physics_delta_s` 总和。 |
| `intensity_difference_mean`, `intensity_difference_p95`, `intensity_difference_max` | 归一化幅度 | 有效帧 `abs(|F_A|/force_max - |F_B|/force_max)`。 |
| `conflict_ratio` | [0,1] | 同时活动且余弦 `< -0.50` 的时长 / 同时活动时长。分母为 0 时为空。 |
| `simultaneous_active_ms` | ms | 双方同时超过活动阈值的时长。 |
| `A_start_ms`, `B_start_ms` | ms/空 | 首次幅度 `>0.20` 且连续至少 100 ms 的候选起点。 |
| `startup_difference_ms` | ms/空 | `B_start_ms - A_start_ms`；正数表示 A 先启动。 |
| `startup_status` | 枚举 | `ok`、`missing_A`、`missing_B`、`missing_both`。 |
| `xcorr_lag_ms` | ms/空 | 平滑后力变化率在 ±1000 ms 内归一化互相关绝对峰值的 lag；正值表示 A 领先。 |
| `xcorr_peak` | [-1,1]/空 | 峰值的带符号相关。 |
| `xcorr_leader` | 枚举 | `A`、`B`、`ambiguous`。 |
| `xcorr_confidence` | [0,1] | 峰强度与第一/第二峰分离度的组合评分。 |
| `xcorr_status` | 枚举 | `ok` 或 `low_activity`（活动少于 500 ms/样本不足）。 |
| `correction_A`, `correction_B` | 归一化力·ms | 误差至少 2 px 时，各自沿 `-error` 正投影的时间积分。 |
| `trial_leader` | 枚举 | 启动领先、互相关领先、纠偏贡献 >60% 三项多数决；平票为 `ambiguous`。 |
| `collision_count`, `death_count`, `restart_count`, `quit_count` | 次 | 对应事件计数。 |
| `mean_route_error`, `p95_route_error`, `max_route_error` | px | 路线绝对误差统计。 |
| `max_progress` | [0,1] | 最大 `route_max_progress`。 |
| `outside_boundary_ms` | ms | `inside_boundary=0` 帧的步长总和。 |
| `route_length` | px | 连续核心坐标间欧氏距离总和。 |

### 6.2 `perturbation_summary.csv`

每个 `perturb_on` 一行；`perturbation_id=<trial>-P###`。

| 字段 | 单位 / 枚举 | 定义 |
|---|---|---|
| `onset_ms`, `offset_ms` | ms | 扰动开始及同 slot 后续 `perturb_off`；无 off 时为观察终点。 |
| `perturbed_participant`, `perturbed_slot`, `gain` | — | 受扰者 A/B、设备槽和增益。 |
| `compensation_status` | 枚举 | `valid`、`no_valid_compensation`、`not_eligible`、`censored`。 |
| `compensation_onset_ms` | ms/空 | 未受扰者相对扰动前 200 ms 中位力的 `ΔF`，沿 `-error` 投影 ≥0.12 且持续 100 ms 的起点；还要求 400 ms 后误差至少下降 5%。 |
| `compensation_reaction_ms` | ms/空 | `compensation_onset_ms - onset_ms`。 |
| `compensation_peak_projection` | 归一化力/空 | 观察期最大 `ΔF·(-error_unit)/force_max`。 |
| `recovery_status` | 枚举 | `recovered`、`censored`、`not_eligible`。 |
| `recovery_time_ms` | ms/空 | 误差、速度、角速度均回到扰动前中位数 ± `max(协议下限, 3×MAD)` 并持续 500 ms 的稳定段起点相对 onset。 |
| `recovery_observation_ms` | ms | 实际观察上限；恢复时为确认稳定的时点，删失时为最后观测。 |
| `recovery_censored` | 0/1 | trial 结束前未确认 500 ms 稳定则为 1。 |
| `overshoot_status` | 枚举 | `overshoot`、`none`、`not_eligible`。初始有符号误差小于 2 px 不适用。 |
| `overshoot_first_reverse_max` | px/空 | 首次到达反侧后观测到的最大反向绝对误差。 |
| `overshoot_ratio` | 比例/空 | `first_reverse_max / abs(扰动前有符号误差中位数)`。 |
| `overshoot_round_trips` | 次 | 使用 2 px 滞回检测的跨侧次数整除 2。 |

### 6.3 `dyad_summary.csv`

`scope=all` 一行，并为每个关卡输出 `scope=level` 一行。字段包括 trial/success/restart/quit
计数、成功率、A/B/ambiguous 领导计数与比例、非模糊试次中同一领导者比例
`same_leader_stability=max(A_count,B_count)/(A_count+B_count)`，以及完成时间、路线误差和
最大进度的均值。完成时间均值只纳入非空值。

### 6.4 复核文件

- `review_queue.csv`：按 `sha256(session_id|perturbation_id)` 稳定排序，抽取
  `ceil(扰动数×0.20)`。自动字段不可手改；人工填写
  `manual_valid`、`manual_onset_ms`、`manual_recovery_ms`、`note`。
- `review_windows.csv`：每个入选事件前 2000 ms、后 2000 ms 的长表窗口，包含误差、速度、
  角速度、A/B 力、补偿投影和自动起点/恢复标记。
- `review_<perturbation_id>.svg`：无需第三方库的复核折线图。
- `review_agreement.csv`：已填写样本数、分类一致率、人工/自动起点在 ±100 ms 内的一致率，
  以及起点和恢复差值的均值/中位数。
- 重算前分析器会按 `perturbation_id` 读取旧 `review_queue.csv`，保留四个人工填写字段。

### 6.5 `analysis_metadata.csv`

记录本次 `analysis_version` 与全部阈值：活动 0.20、冲突余弦 -0.50、启动持续 100 ms、
力平滑 100 ms、互相关范围 ±1000 ms/最少活动 500 ms、扰动基线 200 ms、补偿投影 0.12/
持续 100 ms/400 ms 后检查/误差下降 5%/最小误差 2 px、恢复持续 500 ms/MAD 倍数 3/
误差下限 3 px/速度下限 8 px/s/角速度下限 0.15 rad/s、过冲滞回 2 px、复核比例 20%、
复核窗口前后各 2000 ms、人工起点容差 100 ms。

## 7. 删失、失败和恢复规则

- 扰动前窗口为空或基线误差向量 `<2 px`：补偿、恢复、过冲为 `not_eligible`。
- 400 ms 误差检查窗口尚未完整观察到：补偿为 `censored`，而不是“无补偿”。
- trial 结束前未出现连续 500 ms 回稳：`recovery_censored=1`，保存实际
  `recovery_observation_ms`。
- 中断恢复只追加 `aborted_recovered` 和 `trial_end(outcome=aborted)`，不修改既有行；
  随后自动重算派生文件。
- 任何派生写出或 SVG 写出失败都会使导出状态失败；结算页显示失败而不是静默宣称已保存。

## 8. 隐私与数据治理

- 只允许 1–16 位数字编号；禁止姓名、字母缩写、邮箱、电话、学号或自由文本身份信息。
- `dyad_id`、`participant_A/B` 是研究方自建的去标识编号，不应能由文件本身反查个人。
- `device_id` 是本次系统运行的输入设备编号，不是受试者身份。
- `started_utc` 可能构成间接标识；共享前按伦理审批要求降精度或单独保管映射信息。
- 不要把编号映射表放进 session 目录或版本控制。
- SVG 和派生 CSV 含行为轨迹，应按原始实验数据同等级保护。

## 9. 重算与人工复核流程

1. 备份整个 session 目录；确认三个原始 CSV 可由标准 CSV 解析器读取。
2. 在项目根目录运行：

   ```bash
   "/Users/wangzhaohan/Downloads/Godot_mono.app/Contents/MacOS/Godot" \
     --headless --path . --script res://tools/reanalyze_experiment.gd -- \
     --session-dir "/absolute/path/to/experiments/dyad-101/2026-08-13_051600Z"
   ```

3. 检查命令输出 `EXPERIMENT_REANALYSIS_OK`、`analysis_metadata.csv` 的版本和阈值。
4. 打开 `review_queue.csv`，只填写 `manual_*` 与 `note`；不要改自动字段或原始 CSV。
5. 再次运行同一重算命令，人工字段会按 `perturbation_id` 保留，并生成
   `review_agreement.csv`。
6. 用 `review_windows.csv` 或对应 SVG 核对自动起点、恢复点及删失原因。

分析协议升级时应同时提升 `ANALYSIS_VERSION`、更新本字典、保留旧派生结果副本；原始
schema 未改变时不应修改 `session.csv`、`frames.csv`、`events.csv`。
