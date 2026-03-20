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

**当前实验波次（未提交工作树 vs `HEAD`, ReadyToRun=On, `Runs=5`）**

> 口径同上；`trace-baseline = HEAD`，`current-optimized = 当前工作树`

| Variant | T3 | T4 | T5 | `LoadedAsync()` | `LoadedAsync tail` |
|--|--:|--:|--:|--:|--:|
| `trace-baseline` | 1754.6 ms | 2047.6 ms | 2086.0 ms | 37.6 ms | 0.2 ms |
| `current-optimized` | 1705.8 ms | 1996.2 ms | 2019.4 ms | 19.4 ms | 2.8 ms |

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
- [ ] 增加“列表加载中”状态，避免用户误判卡死

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

---

## P2：结构型优化

### 10. 命令系统瘦身

- [ ] 评估将“命令元数据”和“命令实例”分离
- [ ] 降低启动期 200+ 命令对象一次性构造成本
- [ ] 仅在真正需要绑定/执行时实例化命令对象

**涉及文件**

- `NeeView/Command/CommandTable.cs`
- `NeeView/Command/CommandElement.cs`
- `NeeView/Command/RoutedCommandTable.cs`

---

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

1. 继续深拆 `MainWindow.Initialize.InitializeComponent` / `ViewSources` / `MainViewComponent.Initialize.ViewModel`，把下一轮优化重点放回 `T0 -> T4`
2. 评估 `SidePanelFrame.EnsureInitialized` / `CustomLayoutPanelManager.Restore` 是否还能继续后移或减量，避免首帧后立刻出现新的 UI 热点
3. 为 FolderList 增加“加载中”状态与完成回调，补齐 UI 反馈和选中/聚焦收敛
4. 单独跟踪 `ProcessJobEngine.WaitPropertyAsync` 的偶发超时，确认这是测量噪声还是仍有真实启动不稳定点

### Next Success Criteria

- 在保持当前 `T5` 不回退的前提下，继续压低 `T3/T4`
- 新一轮优化不能重新引入 `LoadedAsync tail` 的明显回升
- 大目录/网络目录恢复时首屏不再被列表稳定等待阻塞
- 功能行为与现有多开、脚本、Susie 使用路径保持一致

---

## 推荐实施顺序

1. 启动埋点补齐
2. `T0 -> T4` 主链路瘦身
3. FolderList 完成回调 / 加载中反馈
4. `InitializeComponent` / `ViewSources` 深拆
5. `ProcessJobEngine` 波动排查
6. 侧边栏深度 lazy / 命令系统瘦身

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
