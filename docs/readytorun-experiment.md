# ReadyToRun 试验说明

## 目的

这份试验用于回答三个问题：

1. ReadyToRun 是否改善 NeeView 的启动时间
2. ReadyToRun 会让发布产物增大多少
3. ReadyToRun 对启动后的工作集/私有内存是否有明显影响

## 当前项目状态

当前 `FolderProfile-x64.pubxml` 已经包含：

```xml
<PublishReadyToRun>true</PublishReadyToRun>
```

这意味着原有发布流程默认就是 ReadyToRun。  
本次改造的重点不是“开启”，而是：

- 给发布流程增加 **On / Off / Default** 的显式切换
- 增加一份可重复执行的对比脚本

## 发布流程开关

`MakePackage/MakePackage.ps1` 现已支持以下参数：

- `-readyToRun Default`
- `-readyToRun On`
- `-readyToRun Off`
- `-readyToRunShowWarnings`
- `-readyToRunComposite`
- `-readyToRunEmitSymbols`

### 示例

默认行为：

```powershell
./MakePackage/MakePackage.ps1 -Target Zip
```

强制开启 ReadyToRun：

```powershell
./MakePackage/MakePackage.ps1 -Target Zip -readyToRun On
```

强制关闭 ReadyToRun：

```powershell
./MakePackage/MakePackage.ps1 -Target Zip -readyToRun Off
```

显示 ReadyToRun 缺失依赖警告：

```powershell
./MakePackage/MakePackage.ps1 -Target Zip -readyToRun On -readyToRunShowWarnings
```

## 自动对比脚本

新增脚本：

- `MakePackage/Measure-ReadyToRun.ps1`

它会自动做两套发布：

- `baseline-no-r2r`
- `experiment-r2r`

并对两套产物执行：

- 发布目录体积统计
- 启动到主窗口出现的时间统计
- 启动后工作集与私有内存统计

## 当前结果（`Runs=5`）

| Variant | PublishReadyToRun | Size | Startup Avg | Working Set Avg | Private Memory Avg |
|--|--:|--:|--:|--:|--:|
| `baseline-no-r2r` | false | 51.6 MB | 533.3 ms | 111.1 MB | 48.3 MB |
| `experiment-r2r` | true | 65.3 MB | 516.2 ms | 126.8 MB | 57.4 MB |

**结果解读**

- ReadyToRun 让主窗口出现时间缩短约 `17.1 ms`，约 `3.2%`
- 发布目录增大约 `13.7 MB`，约 `26.6%`
- 工作集增加约 `15.7 MB`
- 私有内存增加约 `9.1 MB`

**当前结论**

- ReadyToRun 对 NeeView 有小幅收益，但不是启动优化的主收益来源
- 当前项目已经保留 ReadyToRun 开关，方便发布时显式切换
- 后续启动优化重点已转向代码级关键路径，而不是继续深挖 ReadyToRun 微调
- 最新代码级分段测试见 `docs/startup-performance-checklist.md`

## 与当前代码级启动优化的关系（2026-03-21）

ReadyToRun 结论在最近一轮代码级观测 / 稳定性改造后仍然没有变化：

- ReadyToRun 仍然只是“小幅收益 + 明显体积/内存代价”
- `Measure-StartupTrace.ps1` 现在默认会输出 `T0 -> T3`、`T3 -> T4`、`T4 -> T5`
- 当前真正值得继续优化的，已经明确落在代码级主路径：
  - `InitializeComponent`
  - `MenuBar.Source`
  - `AddressBarView` / `MenuBarView` 构造

最新 `Startup.Trace` 对比见 `docs/startup-performance-checklist.md`。  
截至 2026-03-21 的最新一轮（Baseline=`HEAD`，Optimized=`current working tree`，`Runs=5`）：

- `T0 -> T3`: `1881.2 -> 1875.0 ms`
- `T3 -> T4`: `274.2 -> 284.8 ms`
- `T4 -> T5`: `14.0 -> 11.2 ms`
- `LoadedAsync()`: `11.8 -> 10.0 ms`

这组结果说明：

- 本轮的主要产出是 **phase delta 默认化、热点归因、FolderList 加载反馈、ProcessJobEngine 启动保护**
- 并不是一次显著的 ReadyToRun 相关收益放大

因此当前推荐策略不变：

- 保留 ReadyToRun 开关
- 但后续优化优先级继续放在代码级关键路径和延迟初始化

## 前置条件

- 需要安装与项目目标框架匹配的 .NET SDK
  - 当前项目目标是 `net10.0-windows`
- 需要先初始化仓库 submodule

```powershell
git submodule update --init --recursive
```

如果前置条件不满足，`Measure-ReadyToRun.ps1` 会直接报错并停止。

## 当前脚本约定

- 如果存在 `C:\Users\<User>\.dotnet\dotnet.exe`，脚本会优先使用这套用户级 SDK
- 测量启动时会显式传入 `DOTNET_ROOT` / `DOTNET_ROOT_X64`
- `NeeView.Susie.Server` 是 `x86 + AOT` 发布，保持它自己的发布方式，不参与 ReadyToRun 开关对比

## 运行方式

```powershell
./MakePackage/Measure-ReadyToRun.ps1
```

可选参数：

```powershell
./MakePackage/Measure-ReadyToRun.ps1 -Runs 5
./MakePackage/Measure-ReadyToRun.ps1 -SelfContained
./MakePackage/Measure-ReadyToRun.ps1 -OutputRoot .\artifacts\readytorun-experiment
```

## 测量口径

### 体积

- 统计发布目录内全部文件总大小

### 启动时间

- 从进程启动开始计时
- 到主窗口句柄出现为止

### 内存

- 主窗口出现后等待约 1 秒
- 读取：
  - 工作集 `WorkingSet64`
  - 私有内存 `PrivateMemorySize64`

## 注意事项

- 该脚本使用隔离的 `NEEVIEW_PROFILE`，不会污染当前用户真实配置
- 脚本测到的是“同机可重复对比”的启动结果，不等于严格的系统级冷启动基准
- 如果需要更严格的冷启动测试，建议在以下条件下复测
  - 重启后执行
  - 固定 Defender/索引器状态
  - 固定显示器和 DPI 环境
  - 固定 `Runs`

## 推荐解读方式

如果出现以下结果，通常说明 ReadyToRun 值得保留：

- 启动时间明显下降
- 包体积增长可接受
- 工作集增长不明显，或增长小于启动收益

如果结果相反：

- 启动时间改善很小
- 包体积增长明显
- 内存增幅不可接受

则应考虑：

- 保持当前默认值但不继续扩大使用范围
- 或进一步做 Composite / TieredCompilation / 更细粒度的实验

## 相关文档

- `docs/startup-performance-checklist.md`
- `MakePackage/Measure-StartupTrace.ps1`
