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
