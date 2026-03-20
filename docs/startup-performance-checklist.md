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

## P0：优先落地项

### 1. 启动链路埋点补齐

- [ ] 在 `App.InitializeAsync()` 内对以下阶段增加稳定埋点
  - [ ] `LoadBootSetting`
  - [ ] `CreateUserSetting`
  - [ ] `InitializeTextResource`
  - [ ] `InitializeCommandTable`
  - [ ] `UserSettingTools.Restore`
  - [ ] `InitializeTheme`
- [ ] 在 `MainWindow` 生命周期增加稳定埋点
  - [ ] 构造函数开始/结束
  - [ ] `OnSourceInitialized`
  - [ ] `Loaded`
  - [ ] `ContentRendered`
- [ ] 在 `MainWindowModel.LoadedAsync()` 内拆分埋点
  - [ ] `CustomLayoutPanelManager.Restore`
  - [ ] `SusiePluginManager.Initialize`
  - [ ] `LoadFolderConfig`
  - [ ] `LoadHistory`
  - [ ] `LoadBookmark`
  - [ ] `PlaylistHub.Initialize`
  - [ ] `FirstLoader.Load`
  - [ ] `BookmarkFolderList.WaitAsync`
  - [ ] `BookshelfFolderList.WaitAsync`

**涉及文件**

- `NeeView/App.xaml.cs`
- `NeeView/MainWindow/MainWindow.xaml.cs`
- `NeeView/MainWindow/MainWindowModel.cs`

---

### 2. 发布构建启用 ReadyToRun 试验

- [x] 为 `Release`/发布流程增加可切换的 ReadyToRun 构建参数
- [x] 增加自动对比脚本，输出包体积、启动时间、工作集、私有内存
- [ ] 在具备 `.NET 10 SDK` 与完整 submodule 的环境中执行正式对比
- [ ] 如果收益稳定，再决定是否默认开启

**涉及文件**

- `MakePackage/MakePackage.ps1`
- `MakePackage/Measure-ReadyToRun.ps1`
- `docs/readytorun-experiment.md`

**验收**

- [ ] 冷启动 T2/T5 有可重复改善
- [ ] 包体增长在可接受范围内

---

### 3. Susie 插件初始化改为按需触发

- [ ] 启动时仅恢复 Susie 配置，不立即连接远程插件服务
- [ ] 第一次出现以下场景时再初始化
  - [ ] 打开 Susie 支持的图片
  - [ ] 打开 Susie 支持的归档
  - [ ] 打开 Susie 插件设置页
- [ ] 明确初始化状态，避免重复初始化
- [ ] 首次按需初始化失败时，保留现有错误提示行为

**涉及文件**

- `NeeView/MainWindow/MainWindowModel.cs`
- `NeeView/Susie/Client/SusiePluginManager.cs`
- `NeeView/Archiver/ArchiveManager.cs`
- `NeeView/Picture/PictureProfile.cs`

**风险**

- 首次打开 Susie 文件时会发生一次性延迟

---

### 4. 启动脚本命令扫描后移

- [ ] 启动阶段只恢复脚本相关配置
- [ ] `ScriptManager.UpdateScriptCommands()` 改到主窗口显示后执行
- [ ] 保证 `OnStartup.nvjs` 的执行时序仍然可控
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

- [ ] 评估移除以下等待的影响
  - [ ] `BookmarkFolderList.Current.WaitAsync(...)`
  - [ ] `BookshelfFolderList.Current.WaitAsync(...)`
- [ ] 改为“先显示 UI，后异步填充列表”
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

## 推荐实施顺序

1. 启动埋点补齐
2. ReadyToRun A/B 试验
3. Susie lazy init
4. 脚本命令扫描后移
5. 移除 FolderList 启动阻塞等待
6. `LoadedAsync()` 拆关键路径与预热
7. `MainViewComponent` lazy 化
8. 侧边栏深度 lazy / 命令系统瘦身

---

## 本文档产出目标

- 用于后续分批开发
- 用于每批改造的验收对照
- 用于避免“只做局部微优化、未处理关键串行链路”的偏差
