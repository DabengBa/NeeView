# NeeView 启动性能改造清单

## 目标

- 缩短冷启动到首帧时间
- 缩短可交互时间（用户可以开始操作的时间）
- 避免大目录、脚本目录、Susie 插件导致的启动阻塞
- 在不破坏现有启动语义的前提下，逐步引入延迟初始化

## 建议度量口径

- **T0**：进程启动
- **T1**：Splash 显示
- **T2**：`MainWindow.Show()`
- **T3**：`Loaded`
- **T4**：`ContentRendered`
- **T5**：首屏可交互
- **T6**：后台预热完成

> 当前 `Startup.Trace` 中的 `T3/T4/T5` 是 **从进程启动 `T0` 开始累计的绝对时间戳**，不是分段耗时。  
> 实际分析时应同时关注：
>
> - `T0 -> T3`
> - `T3 -> T4`
> - `T4 -> T5`

> 从本轮开始，正式验收口径调整为：
>
> - 默认 `Runs >= 20`
> - 同时输出 `Median / TrimmedMean / P90 / Max`
> - 同时统计 `TimeoutRunRate / TimeoutAttemptRate`
> - `Average` 只保留为辅助参考，不再作为主决策指标

> 建议先补齐日志埋点，再做结构改造；每一批改造都要保留 A/B 对比数据。

---

## 当前状态（2026-03-21）

- [x] 启动链路统一埋点已接入
- [x] Startup.Trace T3/T4/T5 分段实测已执行
- [x] ReadyToRun 发布开关已接入
- [x] ReadyToRun 自动对比脚本已接入
- [x] ReadyToRun `Runs=5` 实验已执行
- [x] 去掉 FolderList 启动阻塞等待
- [x] Susie 启动初始化改为按需触发
- [x] 启动脚本命令扫描后移到主窗口显示后
- [x] `MainViewBay` 改为按需创建
- [x] `ThumbnailResource` / `MouseTerminator` 预热后移到首帧之后
- [x] `Measure-StartupTrace.ps1` 已适配“当前工作树 vs BaselineRef”精确对比
- [x] `MainViewComponent` 非首屏控制器按需创建已进入实验态
- [x] SidePanel 初始化/恢复后移已进入实验态
- [x] `MainWindow.ContentRendered.ViewModel` / `LoadedAsync.Returned` 细分 trace 已接入
- [x] `FirstLoader.LoadFolder` / `BookmarkFolderList.UpdateItems` 已后移到 `T5` 之后
- [x] `Measure-StartupTrace.ps1` 已支持 `LoadedAsyncTail` 指标与超时重试
- [x] `Measure-StartupTrace.ps1` 默认输出 `T0 -> T3` / `T3 -> T4` / `T4 -> T5`
- [x] `Measure-StartupTrace.ps1` 默认 `Runs=20`，并输出 `Median / TrimmedMean / P90 / Max / TimeoutRate`
- [x] `InitializeComponent` / `ViewSources` / `MainViewComponent.Initialize.ViewModel` 深拆 trace 已接入
- [x] `SidePanelFrame.EnsureInitialized` / `CustomLayoutPanelManager.Restore` 深拆评估已完成
- [x] FolderList “加载中”状态与 `LoadCompleted` 回调已接入
- [x] `ProcessJobEngine.WaitPropertyAsync` 超时诊断与 10s fallback 已接入
- [x] `AddressBarView` 非首屏 popup 改为按需创建已进入实验态
- [x] `MenuBarView.WindowCaptionButtons` 已后移到 `DeferredWarmup`
- [x] MainMenu group 子菜单按首次展开创建已进入实验态
- [x] 新口径 `Runs=20` 正式复测已执行
- [x] `T3/T4/T5` 绝对时间戳口径已在文档中澄清
- [x] `PageSlider.PageMarkers` 改为 lazy 创建已进入实验态
- [x] `PageSliderView.Initialize` 细分 trace 已接入
- [x] `PageSliderView.PageMarkers.Source` 已后移到 `DeferredWarmup`
- [x] `PageSliderViewModel` 启动期字体参数依赖已移除
- [x] `PageSliderView.Source / Initialize` 新口径 `Runs=20` 正式复测已执行

**ReadyToRun 实测结果**

| Variant | PublishReadyToRun | Size | Startup Avg | Working Set Avg | Private Memory Avg |
|--|--:|--:|--:|--:|--:|
| `baseline-no-r2r` | false | 51.6 MB | 533.3 ms | 111.1 MB | 48.3 MB |
| `experiment-r2r` | true | 65.3 MB | 516.2 ms | 126.8 MB | 57.4 MB |

**结果解读**

- ReadyToRun 让启动均值缩短约 `17.1 ms`，约 `3.2%`
- 发布目录增大约 `13.7 MB`，约 `26.6%`
- 工作集增加约 `15.7 MB`
- 私有内存增加约 `9.1 MB`

**阶段性结论**

- ReadyToRun 对 NeeView 有小幅启动收益，但不是决定性收益
- 当前收益不足以成为后续启动优化的主攻方向
- 后续应把重点转到代码级启动阻塞链路，而不是继续深挖发布层微调

**历史主窗口句柄口径对比（首轮结果，ReadyToRun=On, `--blank`, `Runs=5`）**

| Variant | Size | Startup Avg | Working Set Avg | Private Memory Avg |
|--|--:|--:|--:|--:|
| `head-baseline` | 65.3 MB | 515.9 ms | 120.0 MB | 54.3 MB |
| `current-optimized` | 66.4 MB | 500.3 ms | 123.8 MB | 56.9 MB |

**当前代码改造结果**

- 当前工作树相对 `HEAD` 基线，主窗口可见时间缩短约 `15.6 ms`，约 `3.0%`
- 工作集增加约 `3.8 MB`
- 私有内存增加约 `2.6 MB`
- 该测试口径偏向“主窗口出现时间”，是首轮历史结果，不再代表当前最新工作树
- 当前判断应以下方 `Startup.Trace` 分段测试为准

---

**Startup.Trace 分段实测（ReadyToRun=On, trace-baseline vs current-optimized, `Runs=5`）**

> 口径：`T3 = MainWindow.Loaded end_ms`，`T4 = MainWindow.ContentRendered start_ms`，`T5 = MainWindow.ContentRendered.ViewModel end_ms`

| Variant | T3 | T4 | T5 | `LoadedAsync()` |
|--|--:|--:|--:|--:|
| `trace-baseline` | 1756.6 ms | 2021.2 ms | 2364.6 ms | 335.6 ms |
| `current-optimized` | 1753.4 ms | 2013.8 ms | 2051.8 ms | 37.0 ms |

**关键收益量化**

- `LoadedAsync()` 从 `335.6 ms` 降到 `37.0 ms`，减少 `298.6 ms`，约 `89.0%`
- `T5` 从 `2364.6 ms` 降到 `2051.8 ms`，减少 `312.8 ms`，约 `13.2%`
- `T3` 小幅改善：`-3.2 ms`
- `T4` 小幅改善：`-7.4 ms`

**分段解读**

- 本轮优化几乎没有改变 `T3/T4`，说明主收益不在“窗口更早出现”，而在 `ContentRendered` 之后更快进入可交互状态
- `trace-baseline` 中，`MainWindowModel.LoadedAsync.BookshelfFolderList.WaitAsync` 平均阻塞 `281.8 ms`，是 `LoadedAsync()` 的主要大头
- `current-optimized` 中，这段等待已移出关键路径；后台 `StartupWarmup.*WaitAsync` 在本次样本里平均仅观察到约 `1.6 ms + 1.6 ms` 的收尾等待
- `UserSettingTools.ApplyDeferredCommandCollection()` 后移后，在 `LoadedAsync()` 内平均仅约 `3 ms`
- `SusiePluginManager.Initialize()` 在这组样本里接近 `0 ms`，说明这次量化收益主要来自 FolderList 阻塞等待移出关键路径，而不是 Susie

**T0 -> T4 主链路最新拆解（current-optimized, `Runs=5`）**

- `MainWindow.Initialize.InitializeComponent`: 约 `401.4 ms`
- `MainWindow.Initialize.CustomLayoutPanelManager.Initialize`: 约 `48.8 ms`
- `MainWindow.Initialize.ViewSources`: 约 `39.4 ms`
- `MainWindow.Initialize.MainViewComponent.Initialize`: 约 `32.4 ms`
- `MainWindow.Initialize.StaticResources`: 已降到约 `1.0 ms`
- `MainWindow.DeferredWarmup.ThumbnailResource.InitializeStaticImages`: 已后移到首帧后，约 `7.2 ms`
- `MainWindow.DeferredWarmup.MouseTerminator`: 已后移到首帧后，约 `0.2 ms`

**本轮主链路结论**

- `ThumbnailResource.InitializeStaticImages()` 已不再占用 `T0 -> T4` 关键路径
- `MouseTerminator` 已不再占用 `MainWindow.Create`
- `MainViewBay` 已改为按需创建，但当前 trace 看不到显著单独收益，说明下一轮应继续盯 `InitializeComponent` / `CustomLayoutPanelManager.Initialize` / `ViewSources`

**涉及脚本**

- `MakePackage/Measure-StartupTrace.ps1`

---

**本轮 T5 收敛验证（2026-03-21，Baseline=`79ed2534f`，Optimized=`3f6381441`，ReadyToRun=On，`Runs=5`）**

> 口径同上；`trace-baseline = 修正前基线`，`current-optimized = 本轮修正后代码`

| Variant | T3 | T4 | T5 | `LoadedAsync()` | `LoadedAsync tail` |
|--|--:|--:|--:|--:|--:|
| `trace-baseline` | 1754.6 ms | 2047.6 ms | 2086.0 ms | 37.6 ms | 0.2 ms |
| `current-optimized` | 1705.8 ms | 1996.2 ms | 2019.4 ms | 19.4 ms | 2.8 ms |

**阶段差值口径（更适合判断真实收益）**

| Variant | `T0 -> T3` | `T3 -> T4` | `T4 -> T5` |
|--|--:|--:|--:|
| `trace-baseline` | 1754.6 ms | 293.0 ms | 38.4 ms |
| `current-optimized` | 1705.8 ms | 290.4 ms | 23.2 ms |

**阶段差值解读**

- `T3/T4/T5` 本身都大于 `1700 ms`，是因为它们是从 `T0` 开始累计的绝对时间戳
- 真正表示首屏后尾段是否健康的，是 `T4 -> T5`
- 本轮修正后：
  - `T0 -> T3` 改善 `48.8 ms`
  - `T3 -> T4` 再改善 `2.6 ms`
  - `T4 -> T5` 再改善 `15.2 ms`
- 因此当前问题已经不再是 `LoadedAsync()` 尾段，而是 `T0 -> T3/T4` 主链路仍然偏大

**这波改造的量化结果**

- `T3`：`-48.8 ms`，约 `-2.8%`
- `T4`：`-51.4 ms`，约 `-2.5%`
- `T5`：`-66.6 ms`，约 `-3.2%`
- `LoadedAsync()`：`-18.2 ms`，约 `-48.4%`
- `LoadedAsync tail`：`+2.6 ms`，`LoadedAsync -> ViewModel returned` 的尾段已基本收敛到接近基线

**分段结论**

- `MainViewComponent` lazy 化并不是 `LoadedAsync()` 结束后的主因；目前只观测到一次启动期 lazy init：
  - `MainViewComponent.Lazy.ViewPropertyControl`
  - caller: `MainMenu.CreateMainMenu -> MenuTreeTools.CreateCommandMenuControl -> ToggleIsAutoRotateLeftCommand.CreateIsCheckedBinding`
  - 发生时机：`MainWindow.Initialize.ViewSources` 阶段，而不是 `LoadedAsync()` 之后
- 真正把 `ContentRendered.ViewModel` 尾段拉长的是启动期的 `FolderList.RequestPlace()`：
  - `FirstLoader.LoadFolder()`
  - `BookmarkFolderList.UpdateItems()`
  这两条链原本在 `LoadedAsync()` 里排队到 UI Dispatcher，偶发会抢在 `LoadedAsync` continuation 之前执行
- 本轮修正后，这两项已统一后移到 `BeginStartupWarmup()`，并保留 `FolderList.StartupRequestPlace.*` trace
- `LoadedAsyncResumeGap` 均值已收敛到 `1.8 ms`
- `LoadedAsyncTail` 均值已收敛到 `2.8 ms`

**当前工作树主链路拆解（`current-optimized`, `Runs=5`）**

- `MainWindow.Initialize.InitializeComponent`: 约 `394.0 ms`
- `MainWindow.Initialize.ViewSources`: 约 `53.0 ms`
- `MainWindow.Initialize.MainViewComponent.Initialize`: 约 `30 ms` 量级
- `MainWindow.DeferredWarmup.SidePanelFrame.EnsureInitialized`: 约 `27~28 ms`
- `MainWindow.DeferredWarmup.CustomLayoutPanelManager.Restore`: 约 `6 ms`
- `MainWindow.DeferredWarmup.ThumbnailResource.InitializeStaticImages`: 约 `7~8 ms`
- `FolderList.StartupRequestPlace.BookmarkFolderList`: 平均 `175.0 ms`
- `FolderList.StartupRequestPlace.BookshelfFolderList`: 平均 `294.2 ms`
- 但这两段现在已经落到 `T5` 之后：
  - `BookmarkFolderList` 平均排队延迟约 `140.8 ms`
  - `BookshelfFolderList` 平均排队延迟约 `22.2 ms`

**当前判断**

- 这波改造已经恢复为可提交状态
- `T3/T4/T5` 都重新回到正向收益，且 `LoadedAsync tail` 已基本压平
- 下一轮不再优先盯 `ContentRendered.ViewModel` 空档，而应回到 `T0 -> T4` 主链路瘦身
- 后续汇报和验收应优先使用 `T0 -> T3 / T3 -> T4 / T4 -> T5` 三段差值，避免误读绝对时间戳

---

**本轮观测 / 稳定性改造结果（2026-03-21，Baseline=`HEAD`，Optimized=`current working tree`，ReadyToRun=On，`Runs=5`）**

> 命令：`Measure-StartupTrace.ps1 -RunCount 5 -TraceTimeoutSeconds 120 -TraceRetryCount 4 -SkipPublish`
>
> 说明：
>
> - 本轮目标主要是 **默认输出 phase delta、细化热点归因、补齐启动稳定性保护**
> - `HEAD` 基线仍偶发卡在 `MainWindowModel.LoadedAsync.ProcessJobEngine.WaitPropertyAsync`
> - 因此这组数据更适合解读为“观测能力提升 + 启动保护生效”，而不是一次大幅提速

| Variant | `T0 -> T3` | `T3 -> T4` | `T4 -> T5` | `LoadedAsync()` | `LoadedAsync tail` |
|--|--:|--:|--:|--:|--:|
| `trace-baseline` | 1881.2 ms | 274.2 ms | 14.0 ms | 11.8 ms | 1.2 ms |
| `current-optimized` | 1875.0 ms | 284.8 ms | 11.2 ms | 10.0 ms | 0.2 ms |

**本轮差值**

- `T0 -> T3`：`-6.2 ms`
- `T3 -> T4`：`+10.6 ms`
- `T4 -> T5`：`-2.8 ms`
- `LoadedAsync()`：`-1.8 ms`
- `LoadedAsync tail`：`-1.0 ms`
- 工作集 / 私有内存：基本持平（`-0.1 MB / -0.1 MB`）

**这波改造的实际价值**

- `Measure-StartupTrace.ps1` 已默认输出三段 phase delta，后续验收不再需要手工换算
- `InitializeComponent` / `ViewSources` / `MainViewComponent.Initialize.ViewModel` 热点已经可直接归因
- `FolderList` 启动恢复链已具备“加载中”反馈与完成事件，后续可以继续做选中/聚焦收敛
- `ProcessJobEngine.WaitPropertyAsync` 即使再出现偶发超时，当前工作树也不会无限卡住启动

**最新热点拆解（`current-optimized`，run-1 代表样本）**

| 区段 | Trace | Duration |
|--|--|--:|
| 主路径 | `MainWindow.Initialize.InitializeComponent` | 448 ms |
| ctor 热点 | `MainWindow.InitializeComponent.AddressBarView` | 99 ms |
| ctor 热点 | `MainWindow.InitializeComponent.MenuBarView` | 84 ms |
| ViewSources | `MainWindow.Initialize.ViewSources` | 65 ms |
| ViewSources 热点 | `MainWindow.Initialize.ViewSources.MenuBar.Source` | 56 ms |
| ViewModel | `MainWindow.Initialize.MainViewComponent.Initialize` | 30 ms |
| ViewModel 热点 | `MainViewComponent.Initialize.ViewModel.New` | 8 ms |
| ViewModel 热点 | `MainViewViewModel.Initialize.ContextMenuHooks` | 7 ms |
| 首帧后预热 | `MainWindow.DeferredWarmup.SidePanelFrame.EnsureInitialized` | 32 ms |
| 首帧后预热 | `...CustomLayoutPanelManager.Initialize` | 16 ms |
| 首帧后预热 | `...SidePanelFrameViewModel` | 13 ms |
| 首帧后预热 | `MainWindow.DeferredWarmup.CustomLayoutPanelManager.Restore` | 6 ms |

**当前判断（更新）**

- 现在最值得继续压缩的已经不是 `LoadedAsync()`，而是：
  1. `PageSliderView.Source / Initialize`
  2. `AddressBarView` / `MenuBarView` 构造剩余成本
  3. `InitializeComponent` 内部 XAML / 绑定初始化成本
- `MenuBar.Source` 已被压到 `3~4 ms` 量级，不再是当前主攻对象
- `SidePanelFrame.EnsureInitialized` 总量约 `28~30 ms`，仍值得观察，但优先级已经低于 `PageSliderView.Source`
- `FolderList.StartupRequestPlace.*` 自身耗时依旧不小（约 `173~327 ms`），但已落到 `T5` 之后；下一步重点是体验收敛、虚拟化与分批提交，而不是重新搬回关键路径
- `ProcessJobEngine` 在本轮 `Runs=20` 中未复现 timeout，但护栏不等于修复；后续仍要继续做根因定位

---

**AddressBar / MenuBar 主路径减量快测（2026-03-21，Baseline=`HEAD`，Optimized=`current working tree`，ReadyToRun=On，`Runs=1`）**

> 命令：`Measure-StartupTrace.ps1 -RunCount 1 -TraceTimeoutSeconds 120 -TraceRetryCount 4`
>
> 说明：
>
> - 这一轮是 **方向性快测**，用于确认 `AddressBarView` / `MenuBarView` / `MenuBar.Source` 的首轮减量是否生效
> - `Runs=1` 不能作为最终验收；正式结论仍需补一轮 `Runs=5`

| Variant | `T0 -> T3` | `T3 -> T4` | `T4 -> T5` | `LoadedAsync()` | Working Set | Private Memory |
|--|--:|--:|--:|--:|--:|--:|
| `trace-baseline` | 1749.0 ms | 288.0 ms | 10.0 ms | 9.0 ms | 164.3 MB | 102.3 MB |
| `current-optimized` | 1653.0 ms | 271.0 ms | 20.0 ms | 19.0 ms | 161.6 MB | 98.5 MB |

**本轮快测差值**

- `T0 -> T3`：`-96.0 ms`
- `T3 -> T4`：`-17.0 ms`
- `T4 -> T5`：`+10.0 ms`
- `T5` 绝对时间戳：`2047.0 -> 1944.0 ms`，改善 `103.0 ms`
- 工作集 / 私有内存：`-2.7 MB / -3.8 MB`

**当前样本热点（run-1）**

| 区段 | Trace | Duration |
|--|--|--:|
| 主路径 | `MainWindow.Initialize.InitializeComponent` | 374 ms |
| ctor 热点 | `MainWindow.InitializeComponent.AddressBarView` | 78 ms |
| ctor 热点 | `MainWindow.InitializeComponent.MenuBarView` | 56 ms |
| ViewSources | `MainWindow.Initialize.ViewSources` | 32 ms |
| ViewSources 热点 | `MainWindow.Initialize.ViewSources.PageSliderView.Source` | 27 ms |
| ViewSources 热点 | `MainWindow.Initialize.ViewSources.MenuBar.Source` | 3 ms |
| 首帧后预热 | `MainWindow.DeferredWarmup.MenuBarView.WindowCaptionButtons` | 4 ms |
| 可交互尾段 | `MainWindow.ContentRendered.ViewModel` | 19 ms |

**快测结论**

- `AddressBarView` 的关闭态 popup 已不再在启动时实例化；`BookPopupContent` / `PageSortModePalette` 已移出 `InitializeComponent` 主路径
- `MenuBarView.WindowCaptionButtons` 已后移到 `DeferredWarmup`，当前样本里不再占用 `T0 -> T4`
- `MenuBar.Source` 当前样本仅 `3 ms`，说明主菜单 group 按首次展开构造已经明显压平这段成本
- 当前新的 `ViewSources` 首要热点已经转到 `PageSliderView.Source`（`27 ms`）
- 这组数据对 `T0 -> T3 / T3 -> T4` 是明确正向，但 `T4 -> T5` 与 `LoadedAsync()` 单样本有回升，下一步必须先做 `Runs=5` 复测，避免把噪声误判成回退

**本轮已落地实现**

- `AddressBarView`
  - `PageSortModePalette` 改为 `PageSortModePopup` 打开时创建
  - `BookPopupContent` 改为 `BookPopup` 打开时创建
- `MenuBarView`
  - `WindowCaptionButtons` 改为 `Loaded + DispatcherPriority.Background` 后创建
  - watermark 使用静态冻结 brush，减少构造期临时对象
- `MainMenu`
  - group 子菜单改为首次展开时再创建，避免启动时一次性构造整棵菜单树
- `MainWindow`
  - DPI 更新改为通过 `MenuBar.UpdateWindowCaptionButtonsStrokeThickness()` 兼容延后创建后的标题栏按钮

**本轮已完成验证**

- 已使用用户级 `.NET 10 SDK` 执行 `dotnet build NeeView.sln -c Release -p:Platform=x64`
- 当前结果：`0 warning / 0 error`
- 已执行 1 轮 `Startup.Trace` 快测，结果已记录在本节

---

**度量口径升级进展（2026-03-21）**

- `Measure-StartupTrace.ps1` 默认 `RunCount` 已从 `5` 提升到 `20`
- 新增统计：
  - `Median`
  - `TrimmedMean`（按 `TrimRatio=0.1` 去头去尾）
  - `P90`
  - `Max`
  - `TimeoutRunRate / TimeoutAttemptRate`
- 控制台默认输出已切换为：
  - `T0 -> T3`
  - `T3 -> T4`
  - `T4 -> T5`
  - `LoadedAsync()`
  的 `TrimmedMean / P90 / Max`
- `Average` 仍保留在结果 JSON 中，但降级为辅助指标
- 已用 `Measure-StartupTrace.ps1 -RunCount 1 -TraceRetryCount 1 -SkipPublish` 验证新统计输出与 JSON 字段
- 已完成基于新口径的正式 `Runs=20` 对比，结果见下节

---

**AddressBar / MenuBar 正式复测（2026-03-21，Baseline=`HEAD`，Optimized=`current working tree`，ReadyToRun=On，`Runs=20`）**

> 命令：`Measure-StartupTrace.ps1 -RunCount 20 -TraceTimeoutSeconds 120 -TraceRetryCount 4`
>
> 口径：
>
> - 以 `TrimmedMean / P90 / Max` 为主
> - 同时观察 `TimeoutRunRate / TimeoutAttemptRate`
> - `Average` 仅作辅助，不作为主决策依据

| Variant | Timeout Run | `T0 -> T3` TM / P90 / Max | `T3 -> T4` TM / P90 / Max | `T4 -> T5` TM / P90 / Max |
|--|--:|--:|--:|--:|
| `trace-baseline` | `0%` | `1881.8 / 2000.4 / 2193.0 ms` | `277.8 / 301.1 / 312.0 ms` | `14.8 / 20.3 / 23.0 ms` |
| `current-optimized` | `0%` | `1708.2 / 1783.0 / 1824.0 ms` | `264.8 / 280.3 / 289.0 ms` | `16.8 / 18.1 / 20.0 ms` |

**正式结果解读**

- `T0 -> T3`
  - `TrimmedMean`: `-173.6 ms`
  - `P90`: `-217.4 ms`
  - `Max`: `-369.0 ms`
- `T3 -> T4`
  - `TrimmedMean`: `-13.0 ms`
  - `P90`: `-20.8 ms`
  - `Max`: `-23.0 ms`
- `T4 -> T5`
  - `TrimmedMean`: `+2.0 ms`
  - `P90`: `-2.2 ms`
  - `Max`: `-3.0 ms`
- `LoadedAsync()`
  - `TrimmedMean`: `12.4 -> 15.8 ms`，回升 `3.4 ms`
  - `P90`: `16.2 -> 17.1 ms`，回升 `0.9 ms`
  - `Max`: `18.0 -> 19.0 ms`，回升 `1.0 ms`
- `LoadedAsync tail`
  - `P90`: `4.0 -> 0.1 ms`
  - 尾段恢复明显更平
- 内存
  - `WorkingSet Median`: `163.0 -> 159.8 MB`
  - `PrivateMemory Median`: `102.8 -> 100.6 MB`
- 稳定性
  - `TimeoutRunRate = 0%`
  - `TimeoutAttemptRate = 0%`
  - 本轮 20 次内未复现 `ProcessJobEngine` timeout

**正式结论**

- 这轮 `AddressBar / MenuBar` 改造对主路径是稳定正收益，不是快测噪声：
  - `T0 -> T3` 明确大幅下降
  - `T3 -> T4` 明确小幅下降
- `T4 -> T5` 的 `TrimmedMean` 有轻微回升，但 `P90 / Max` 反而更好，说明尾部体验没有变差，快测中的“首屏后回退”没有被 20 次正式复测放大
- `LoadedAsync()` 主体略有回升，但 `LoadedAsync tail` 的 `P90` 被显著压平，说明当前问题不再是 continuation 尾段抖动
- `MenuBar.Source` 已经压平；下一个真正值得继续打的热点是 `PageSliderView.Source / Initialize`

**当前工作树热点（`current-optimized`, `Runs=20`）**

| 区段 | Trace | Median | P90 | Max |
|--|--|--:|--:|--:|
| 主路径 | `MainWindow.Initialize.InitializeComponent` | 380 ms | 418 ms | 443 ms |
| ctor 热点 | `MainWindow.InitializeComponent.AddressBarView` | 73.5 ms | 83 ms | 88 ms |
| ctor 热点 | `MainWindow.InitializeComponent.MenuBarView` | 58 ms | 65 ms | 70 ms |
| ViewSources | `MainWindow.Initialize.ViewSources` | 30.5 ms | 33 ms | 39 ms |
| ViewSources 热点 | `MainWindow.Initialize.ViewSources.PageSliderView.Source` | 26 ms | 29 ms | 34 ms |
| ViewSources 热点 | `MainWindow.Initialize.ViewSources.MenuBar.Source` | 3 ms | 4 ms | 25 ms |
| 首帧后预热 | `MainWindow.DeferredWarmup.MenuBarView.WindowCaptionButtons` | 4 ms | 5 ms | 6 ms |
| 可交互尾段 | `MainWindow.ContentRendered.ViewModel` | 17 ms | 18 ms | 20 ms |

---

**PageSlider 正式复测（2026-03-21，Baseline=`HEAD`，Optimized=`current working tree`，ReadyToRun=On，`Runs=20`）**

> 命令：`Measure-StartupTrace.ps1 -RunCount 20 -TraceTimeoutSeconds 120 -TraceRetryCount 4`
>
> 说明：
>
> - 这轮是 `PageSliderView.Source / Initialize` 改造后的正式复测
> - `HEAD` 基线在本轮出现 `3/20` 次 timeout retry，因此这组对比同时反映了 **主路径减量** 和 **当前工作树启动稳定性更好**
> - 是否“PageSlider 已经打穿”不能只看总链路 delta，还要直接看 `PageSlider` 自身 trace 指标

**本轮已落地实现**

- `PageSlider.PageMarkers` 改为 lazy 创建，避免 `PageSlider` 构造阶段提前拉起 marker 模型
- `PageSliderView.Initialize` 已拆分 `ViewModel.New / AssignDataContext / PageMarkers.Queue` trace
- `PageMarkersView.Source` 改为 `Loaded + DispatcherPriority.Background` 后赋值，只在 playlist mark 可见时才真正初始化
- `PageMarkersView.Initialize` 增加单次初始化保护与 trace，避免重复构造
- `PageSliderViewModel` 不再在启动期触发 `FontParameters.Current` 与 `SliderConfig.Thickness` 链路
- `SliderTextBox.FontSize` 改为直接使用 `DynamicResource DefaultFontSize`

| Variant | Timeout Run | `T0 -> T3` TM / P90 / Max | `T3 -> T4` TM / P90 / Max | `T4 -> T5` TM / P90 / Max |
|--|--:|--:|--:|--:|
| `trace-baseline` | `15%` | `2529.6 / 3261.1 / 4209 ms` | `373.6 / 480.2 / 1749 ms` | `16.2 / 25.7 / 98 ms` |
| `current-optimized` | `0%` | `1809.2 / 2141.8 / 3824 ms` | `307.3 / 360.9 / 478 ms` | `20.4 / 24.3 / 29 ms` |

**正式结果解读**

- `T0 -> T3`
  - `TrimmedMean`: `-720.4 ms`
  - `P90`: `-1119.3 ms`
  - `Max`: `-385 ms`
- `T3 -> T4`
  - `TrimmedMean`: `-66.3 ms`
  - `P90`: `-119.3 ms`
- `T4 -> T5`
  - `TrimmedMean`: `+4.2 ms`
  - `P90`: `-1.4 ms`
  - `Max`: `29 ms`，明显低于基线的 `98 ms`
- `LoadedAsync()`
  - `TrimmedMean`: `14.2 -> 19.0 ms`
  - `P90`: `20.9 -> 22.4 ms`
- `LoadedAsync tail`
  - `P90`: `2.3 -> 0.1 ms`
- 稳定性
  - `TimeoutRunRate`: `15% -> 0%`
  - `TimeoutAttemptRate`: `13% -> 0%`

**PageSlider 自身指标（`current-optimized`, `Runs=20`）**

| Trace | Median | TM | P90 | Max |
|--|--:|--:|--:|--:|
| `MainWindow.Initialize.ViewSources.PageSliderView.Source` | `0 ms` | `0.2 ms` | `1 ms` | `1 ms` |
| `MainWindow.Initialize.ViewSources.PageSliderView.Initialize` | `0 ms` | `0.2 ms` | `1 ms` | `1 ms` |
| `MainWindow.Initialize.ViewSources.PageSliderView.Initialize.ViewModel.New` | `0 ms` | `0 ms` | `0 ms` | `0 ms` |
| `MainWindow.DeferredWarmup.PageSliderView.PageMarkers.Source` | `0 ms` | `0.2 ms` | `1 ms` | `1 ms` |

**当前工作树热点（`current-optimized`, `Runs=20`）**

- `MainWindow.Initialize.InitializeComponent`: `TM 414.2 ms / P90 508 ms / Max 681 ms`
- `MainWindow.InitializeComponent.AddressBarView`: `TM 81.9 ms / P90 101 ms / Max 139 ms`
- `MainWindow.InitializeComponent.MenuBarView`: `TM 62.5 ms / P90 77 ms / Max 97 ms`
- `MainWindow.Initialize.ViewSources.MenuBar.Source`: `TM 12.4 ms / P90 28 ms / Max 41 ms`
- `MainWindow.DeferredWarmup.SidePanelFrame.EnsureInitialized`: `TM 41.0 ms / P90 49 ms / Max 74 ms`
- `MainWindow.DeferredWarmup.CustomLayoutPanelManager.Restore`: `TM 5.2 ms / P90 7 ms / Max 10 ms`

**正式结论**

- `PageSliderView.Source / Initialize` 已经不再是主路径热点。即使在 `Runs=20` 下，其自身 trace 也稳定落在 `0~1 ms`
- `PageSlider` 这轮改造可以视为**已经验收通过**
- 当前真正还值得继续打的，是 `InitializeComponent` 主链路里的 `AddressBarView` / `MenuBarView`
- `HEAD` 基线这轮暴露出明显启动不稳定性；当前工作树 `TimeoutRunRate / TimeoutAttemptRate = 0%`，说明当前护栏和路径收敛已经带来了稳定性收益
- 后续汇报不应再把 `PageSlider` 作为主要悬而未决项，而应把焦点转回 `InitializeComponent`、`ProcessJobEngine` 根因、FolderList 收敛与命令系统瘦身

---

## P0：优先落地项

### 1. 启动链路埋点补齐

- [x] 在 `App.InitializeAsync()` 内对以下阶段增加稳定埋点
  - [x] `LoadBootSetting`
  - [x] `CreateUserSetting`
  - [x] `InitializeTextResource`
  - [x] `InitializeCommandTable`
  - [x] `UserSettingTools.Restore`
  - [x] `InitializeTheme`
- [x] 在 `MainWindow` 生命周期增加稳定埋点
  - [x] 构造函数开始/结束
  - [x] `OnSourceInitialized`
  - [x] `Loaded`
  - [x] `ContentRendered`
- [x] 在 `MainWindowModel.LoadedAsync()` 内拆分埋点
  - [x] `CustomLayoutPanelManager.Restore`
  - [x] `SusiePluginManager.Initialize`
  - [x] `LoadFolderConfig`
  - [x] `LoadHistory`
  - [x] `LoadBookmark`
  - [x] `PlaylistHub.Initialize`
  - [x] `FirstLoader.LoadBook`
  - [x] `BookmarkFolderList.WaitAsync`
  - [x] `BookshelfFolderList.WaitAsync`
- [x] 在 `MainWindow.ContentRendered.ViewModel` 内拆分埋点
  - [x] `MainWindowViewModel.InitializeAsync.Model.LoadedAsync.Returned`
  - [x] `MainWindowViewModel.InitializeAsync.Model.ContentRendered.Call`
- [x] 为启动期 FolderList 排队链增加 trace
  - [x] `FolderList.StartupRequestPlace.BookmarkFolderList`
  - [x] `FolderList.StartupRequestPlace.BookshelfFolderList`
  - [x] `MainWindowModel.StartupWarmup.FirstLoader.LoadFolder`
  - [x] `MainWindowModel.StartupWarmup.BookmarkFolderList.UpdateItems`

**涉及文件**

- `NeeView/App.xaml.cs`
- `NeeView/MainWindow/MainWindow.xaml.cs`
- `NeeView/MainWindow/MainWindowModel.cs`
- `MakePackage/Measure-StartupTrace.ps1`

**日志格式**

- `Startup.Trace|<Label>|start_ms=<n>`
- `Startup.Trace|<Label>|end_ms=<n>|duration_ms=<n>`
- `Startup.Trace|<Label>|mark_ms=<n>`

---

### 2. 发布构建启用 ReadyToRun 试验

- [x] 为 `Release`/发布流程增加可切换的 ReadyToRun 构建参数
- [x] 增加自动对比脚本，输出包体积、启动时间、工作集、私有内存
- [x] 在具备 `.NET 10 SDK` 与完整 submodule 的环境中执行正式对比
- [x] 形成阶段性结论：保留 ReadyToRun 开关，但不作为下一步主要优化方向

**涉及文件**

- `MakePackage/MakePackage.ps1`
- `MakePackage/Measure-ReadyToRun.ps1`
- `docs/readytorun-experiment.md`

**验收**

- [x] 冷启动 T2/T5 有可重复改善
- [ ] 包体增长在可接受范围内

**备注**

- 当前 `Runs=5` 结果显示，启动收益存在但较小，包体与内存代价较明显
- 是否调整默认发布策略，需要结合安装包体积、内存预算、分发方式单独评审

---

### 3. Susie 插件初始化改为按需触发

- [x] 启动时仅恢复 Susie 配置，不立即连接远程插件服务
- [x] 第一次出现以下场景时再初始化
  - [x] 打开 Susie 支持的图片
  - [x] 打开 Susie 支持的归档
  - [x] 打开 Susie 插件设置页
- [x] 明确初始化状态，避免重复初始化
- [x] 首次按需初始化失败时，保留现有错误提示行为

**涉及文件**

- `NeeView/MainWindow/MainWindowModel.cs`
- `NeeView/Susie/Client/SusiePluginManager.cs`
- `NeeView/Archiver/ArchiveManager.cs`
- `NeeView/Picture/PictureProfile.cs`

**风险**

- 首次打开 Susie 文件时会发生一次性延迟

---

### 4. 启动脚本命令扫描后移

- [x] 启动阶段只恢复脚本相关配置
- [x] `ScriptManager.UpdateScriptCommands()` 改到主窗口显示后执行
- [x] 保证 `OnStartup.nvjs` 的执行时序仍然可控
- [ ] 如有必要，定义两个阶段事件
  - [ ] `CoreStartupCompleted`
  - [ ] `BackgroundWarmupCompleted`

**涉及文件**

- `NeeView/SaveData/UserSettingTools.cs`
- `NeeView/Command/CommandTable.cs`
- `NeeView/Script/ScriptManager.cs`
- `NeeView/MainWindow/MainWindowModel.cs`

**风险**

- 脚本依赖的命令注册时机可能变化，需要回归验证

---

### 5. 去掉启动阶段对 FolderList 稳定的阻塞等待

- [x] 评估移除以下等待的影响
  - [x] `BookmarkFolderList.Current.WaitAsync(...)`
  - [x] `BookshelfFolderList.Current.WaitAsync(...)`
- [x] 改为“先显示 UI，后异步填充列表”
- [ ] 列表完成后再更新选中项/聚焦/可见状态
- [x] 增加“列表加载中”状态，避免用户误判卡死
- [x] 增加 `LoadCompleted` 回调，供启动预热与后续 UI 收敛使用

**涉及文件**

- `NeeView/MainWindow/MainWindowModel.cs`
- `NeeView/SidePanels/Bookshelf/FolderList/FolderList.cs`
- `NeeView/SidePanels/Bookmark/BookmarkFolderList.cs`
- 相关 View / Presenter

**预期收益**

- 大目录、网络目录、归档目录恢复时显著改善 T5

---

## P1：第二批优化

### 6. `LoadedAsync()` 拆分为关键路径与后台预热

- [ ] 定义“启动关键路径”最小集合
  - [ ] 恢复主窗口
  - [ ] 恢复首本/首目录
  - [ ] 允许用户开始操作
- [ ] 后移以下内容到后台预热
  - [ ] `LoadHistory`
  - [ ] `LoadBookmark`
  - [ ] `PlaylistHub.Initialize`
  - [ ] 兼容性 `ProcessJobEngine` 等待/任务
- [ ] 预热结束后仅做增量刷新，不整体打断 UI

**涉及文件**

- `NeeView/MainWindow/MainWindowModel.cs`
- `NeeView/SaveData/SaveData.cs`
- `NeeView/Playlist/PlaylistHub.cs`

---

### 7. `MainViewComponent` 非首屏依赖改为懒加载

- [ ] 盘点首屏真正必需组件
- [ ] 对以下候选项做 lazy 化评估
  - [ ] `PrintController`
  - [ ] `ViewCopyImage`
  - [ ] `ViewWindowControl`
  - [ ] 其他非首屏命令控制器
- [ ] 保证首次访问时线程模型正确

**涉及文件**

- `NeeView/MainView/MainViewComponent.cs`

---

### 8. `RoutedCommandTable` 更新时机后移

- [ ] 评估 `UpdateInputGestures()` 是否必须在窗口构造期完成
- [ ] 尝试延后到 `Loaded` 或 `DispatcherPriority.Background`
- [ ] 确认首屏快捷键、鼠标、触摸输入不受影响

**涉及文件**

- `NeeView/MainWindow/MainWindow.xaml.cs`
- `NeeView/Command/RoutedCommandTable.cs`

---

### 9. 侧边栏默认内容进一步 lazy 化

- [ ] 盘点默认展开的停靠面板
- [ ] 仅在面板真正显示时才触发 `LayoutPanel.Content.Value`
- [ ] 避免窗口初始化时构造完整 `FolderListView` / `BookmarkListView`

**涉及文件**

- `NeeView/SidePanels/SidePanelFrameView.xaml`
- `NeeView/NeeView/Runtime/LayoutPanel/LayoutDockPanel.cs`
- `NeeView/NeeView/Runtime/LayoutPanel/LayoutPanelContainer.xaml`

**风险**

- 这是结构性改造，容易影响停靠/拖拽/自动隐藏行为

### P1-补充：XAML 冻结与空壳化审计

- [ ] 全量审计首屏相关 `Brush / Geometry / DrawingImage / Path`，可冻结的统一冻结
- [ ] 对非首屏必需的视觉树使用空壳 `ContentControl` / 延后赋值，而不是首屏直接进视觉树
- [ ] 优先检查以下区域
  - [ ] `PageSliderView`
  - [ ] `SidePanel`
  - [ ] `AddressBarView`
  - [ ] `MenuBarView`
- [ ] 记录“延后创建”和“只是后移到首帧后”的差异，避免把 UI 卡顿从 `T0 -> T4` 转移到用户第一次交互

**备注**

- WPF 这里不使用 `x:Load` 口径；应以“空壳容器 + 按需赋 Content / View”实现真正的首屏剥离

### P1-补充：FolderList 虚拟化与分批提交

- [ ] 确认列表控件虚拟化真实生效
  - [ ] `VirtualizingStackPanel.IsVirtualizing`
  - [ ] `VirtualizingPanel.VirtualizationMode=Recycling`
  - [ ] 检查是否被自定义面板 / 分组 / ScrollViewer 破坏
- [ ] 评估后台加载完成后是否需要分批提交（chunking）
- [ ] 避免 `LoadCompleted` 后一次性把大量项目塞入 UI，导致首屏后立刻布局抖动

### P1-补充：`ProcessJobEngine` 偶发超时根因定位

- [x] 为启动期 job 增加 `queue / start / end` trace
- [x] 为启动等待前后增加 engine 状态输出
- [x] 为 `WaitPropertyAsync` 增加 10 秒 timeout fallback，避免启动永久卡死
- [ ] 归类 timeout 时对应的 job 类型、输入场景与复现路径
- [ ] 评估是否只等待“启动关键 job”，把非关键 job 明确后移到后台

**涉及文件**

- `NeeView/System/ProcessJobEngine.cs`
- `NeeView/MainWindow/MainWindowModel.cs`
- `MakePackage/Measure-StartupTrace.ps1`

---

### P1-补充：命令系统瘦身（优先级上调）

- [ ] 评估将“命令元数据”和“命令实例”分离
- [ ] 降低启动期 200+ 命令对象一次性构造成本
- [ ] 仅在真正需要绑定/执行时实例化命令对象

**涉及文件**

- `NeeView/Command/CommandTable.cs`
- `NeeView/Command/CommandElement.cs`
- `NeeView/Command/RoutedCommandTable.cs`

---

## P2：结构型优化

### 11. BootSetting 独立轻量缓存

- [ ] 评估将启动必需设置拆到独立小文件
- [ ] 只保留语言、Splash、多开等启动必要项
- [ ] 避免每次启动都解析完整用户配置 JSON

**涉及文件**

- `NeeView/SaveData/BootSetting.cs`
- `NeeView/SaveData/UserSettingResource.cs`
- `NeeView/SaveData/UserSettingTools.cs`

**备注**

- 当前 `LoadBootSetting()` 已复用同一份 bytes 缓存，因此该项优先级低于前述方案

---

## 回归验证清单

- [ ] 无配置文件启动
- [ ] 大配置文件启动
- [ ] 冷启动 / 热启动
- [ ] 默认目录恢复
- [ ] 大目录恢复
- [ ] 网络目录恢复
- [ ] 归档目录恢复
- [ ] Susie 开 / 关
- [ ] 脚本目录空 / 多脚本
- [ ] `OnStartup.nvjs` 正常执行
- [ ] 多开模式正常
- [ ] 首次交互无明显卡顿

---

## 下一步计划

### Next Iteration

1. 回到 `InitializeComponent` 主路径，继续拆 `AddressBarView` / `MenuBarView` 内部剩余成本，重点看 `BreadcrumbBar`、history menu、样式/资源合并与首屏空壳化
2. 继续对 `ProcessJobEngine.WaitPropertyAsync.Timeout` 做根因定位，不把 10s fallback 当作修复结论；下一步要补 dump / 调度链证据
3. 用 `FolderList.LoadCompleted` 把选中项 / 聚焦 / 可见状态收敛补齐，并核对列表虚拟化 / 分批提交是否需要补强
4. 提前推进“命令元数据 / 命令实例分离”，避免后续菜单与手势系统重新把启动路径拉重
5. 把 `SidePanelFrame.EnsureInitialized` / `CustomLayoutPanelManager.Restore` 保持为次优先级观察项；若前述热点继续下降后它们重新升位，再回头处理
6. 继续做首屏 XAML 冻结与空壳化审计，避免只是把卡顿从 `T0 -> T4` 转移到第一次交互后

### Next Success Criteria

- `T0 -> T3` 与 `T3 -> T4` 的正式优势保持不回退
- `T4 -> T5` 与 `LoadedAsync()` 不出现新的尾部恶化；继续以 `P90 / Max` 为主验收
- `TimeoutRunRate / TimeoutAttemptRate` 继续保持为 `0%`，或在复现时能直接定位到具体 job / 调度链
- `PageSliderView.Source / Initialize` 继续保持在 `0~1 ms` 量级，不重新升回主热点
- `InitializeComponent` 主路径的下一批热点能被明确收敛到更小集合，而不是继续在 `ViewSources` 上分散
- 不重新引入 `LoadedAsync tail` 明显回升，也不把 FolderList 阻塞重新搬回关键路径
- `FolderList` 在大目录 / 网络目录恢复时，UI 有明确加载中状态且最终能正确收敛选中 / 聚焦
- `ProcessJobEngine` timeout 如再次出现，日志中能直接定位到具体 job

---

## 推荐实施顺序

1. 启动埋点补齐
2. 统一 `T0 -> T3 / T3 -> T4 / T4 -> T5` 验收口径
3. `PageSlider` 改造正式复测通过后维持低位，不再作为首要热点
4. `AddressBarView` / `MenuBarView` / `InitializeComponent` 内部剩余成本继续下钻
5. `ProcessJobEngine` 波动排查 / dump / 调度链核对
6. FolderList 完成回调后的选中 / 聚焦收敛 + 虚拟化确认
7. 命令元数据 / 命令实例分离
8. 侧边栏深度 lazy / XAML 空壳化

**已完成但不再作为当前重点**

- ReadyToRun A/B 试验
- Startup.Trace T3/T4/T5 分段验证
- 移除 FolderList 启动阻塞等待
- Susie lazy init
- 启动脚本命令扫描后移

---

## 本文档产出目标

- 用于后续分批开发
- 用于每批改造的验收对照
- 用于避免“只做局部微优化、未处理关键串行链路”的偏差
