# mlx-models

一个基于 SwiftUI 的 macOS 本地语音转写示例项目。应用在构建阶段将一个 MLX ASR 模型打包进 App，运行时只从应用 bundle 中加载模型，不直接读取 `~/models`。

## 项目功能

- 支持加载随应用一起打包的 MLX ASR 模型
- 支持导入音频或视频文件进行转写
- 支持麦克风录音后立即转写
- 支持回放导入或录制的音频
- 以聊天流形式展示系统消息、输入消息和 ASR 结果

## 项目结构

```text
mlx-models/
├── AGENTS.md
├── README.md
├── mlx-models.xcodeproj
└── mlx-models/
    ├── mlx_modelsApp.swift
    ├── ContentView.swift
    ├── ASRSessionViewModel.swift
    ├── ASRService.swift
    ├── AudioRecorder.swift
    ├── ModelLocator.swift
    └── ChatMessage.swift
```

## 环境要求

- macOS
- Xcode
- Apple Silicon 机器更适合运行 MLX 模型
- 本地准备好的 MLX 模型目录

Swift Package 依赖已在工程中配置，主要包括：

- `mlx-audio-swift`
- `mlx-swift`
- `swift-huggingface`

## 本地模型目录

默认模型目录约定如下：

```text
~/models/<org>/<model>/
```

当前工程默认值为：

```text
~/models/mlx-community/Qwen3-ASR-0.6B-4bit
```

模型目录需要是可被 MLX Audio 读取的完整模型目录，通常至少应包含：

- `config.json`
- 一个或多个 `.safetensors` 文件

## 构建时打包模型

Xcode target 里定义了以下构建设置：

- `MODEL_ROOT`
- `MODEL_ORG`
- `MODEL_NAME`

当前默认值分别为：

- `$(HOME)/models`
- `mlx-community`
- `Qwen3-ASR-0.6B-4bit`

构建时，Run Script 会把下面这个目录复制进 App bundle：

```text
$(MODEL_ROOT)/$(MODEL_ORG)/$(MODEL_NAME)
```

复制后的 bundle 路径为：

```text
Contents/Resources/Model
```

如果目录不存在，构建会直接失败。

## 如何切换模型

如果要切换到别的模型，不需要改 Swift 代码，只需要修改 target build settings 中的：

- `MODEL_ORG`
- `MODEL_NAME`

应用启动后会通过 Info.plist 中的 `ASRModelRepository` 读取对应仓库名，并将 bundle 内的模型预热到应用缓存目录后再加载。

## 运行时行为

应用运行时只依赖 bundle 内的模型目录：

- 模型查找路径：`Bundle.main.resourceURL/Model`
- 缓存目录：`~/Library/Application Support/<bundle-id>/MLXAudioCache`

也就是说：

- `~/models` 只在构建阶段使用
- App 启动后不会直接从 `~/models` 读取模型

## 使用方式

1. 在本地准备好模型目录。
2. 用 Xcode 打开 `mlx-models.xcodeproj`。
3. 确认 target 的 `MODEL_ROOT`、`MODEL_ORG`、`MODEL_NAME` 设置正确。
4. 构建并运行应用。
5. 首次启动等待模型加载完成。
6. 通过“导入文件”或“开始录音”进行转写。

## 可选：项目内查看模型目录

如果你希望在 Finder 或 Xcode 中方便浏览本地模型，可以手动创建一个项目内软链接：

```sh
ln -s ~/models /Users/eric/projects/mlx-models/mlx-models/Models
```

这个软链接仅用于本地浏览，不应加入 git，也不是 Xcode 资源的一部分。

## 当前实现说明

- `ContentView.swift` 负责界面和交互
- `ASRSessionViewModel.swift` 负责会话状态、录音、转写和播放控制
- `ASRService.swift` 负责模型准备、音频预处理和转写
- `AudioRecorder.swift` 负责麦克风录音
- `ModelLocator.swift` 负责 bundle 内模型定位与仓库名解析

## 常见问题

### 启动后提示模型未就绪

通常是以下原因之一：

- 构建时没有成功复制模型到 App bundle
- `MODEL_ROOT`、`MODEL_ORG`、`MODEL_NAME` 配置错误
- 模型目录内容不完整

### 构建时报找不到模型目录

检查下面这个路径是否真实存在：

```text
$(HOME)/models/$(MODEL_ORG)/$(MODEL_NAME)
```

### 录音失败

请确认应用已获得麦克风权限。
