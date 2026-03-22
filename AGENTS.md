# AGENTS

本文件面向在这个仓库中协作的代码代理与开发者，目的是减少误改、重复探索和对构建流程的误判。

## 仓库概览

- 这是一个 Xcode/macOS SwiftUI 项目，不是 Swift Package。
- 主目标是一个本地 ASR Demo。
- 模型不放在仓库里，构建时从本机目录复制进 App bundle。
- 运行时只读取 bundle 中的 `Model` 目录。

## 关键事实

- 工程文件：`mlx-models.xcodeproj`
- 应用源码目录：`mlx-models/`
- 默认模型仓库名：`mlx-community/Qwen3-ASR-0.6B-4bit`
- 默认本地模型根目录：`$(HOME)/models`
- 构建打包来源目录：`$(MODEL_ROOT)/$(MODEL_ORG)/$(MODEL_NAME)`
- Bundle 内目标目录：`Contents/Resources/Model`

## 主要代码分工

- `mlx-models/ContentView.swift`
  负责主界面、消息列表、状态栏和操作栏。
- `mlx-models/ASRSessionViewModel.swift`
  负责 UI 状态、模型预热、文件导入、录音转写、音频播放。
- `mlx-models/ASRService.swift`
  负责模型加载、缓存播种、视频转音频、调用 MLX ASR 推理。
- `mlx-models/AudioRecorder.swift`
  负责麦克风权限和录音文件落盘。
- `mlx-models/ModelLocator.swift`
  负责 bundle 模型目录定位，以及从 Info.plist 解析仓库名。

## 修改约束

- 不要假设运行时会直接读取 `~/models`。那只是构建输入，不是运行时依赖。
- 不要把本地模型目录、软链接或大文件加入 git。
- 如果修改模型相关逻辑，优先保持“构建时打包、运行时只读 bundle”这个约束不变。
- 如果修改 UI 文案，当前项目主要使用中文文案，新增内容保持一致。
- 这个仓库可能存在未提交的本地改动，避免回滚与当前任务无关的文件。

## 常见任务建议

### 新增或切换模型

- 优先改 Xcode target build settings：
  - `MODEL_ROOT`
  - `MODEL_ORG`
  - `MODEL_NAME`
- 一般不需要改 Swift 代码。

### 排查模型加载失败

先检查：

1. 构建日志里 Run Script 是否成功复制模型。
2. App bundle 中是否存在 `Contents/Resources/Model`。
3. `Model` 目录下是否包含 `config.json` 和 `.safetensors`。
4. `ASRModelRepository` 是否与模型目录对应。

### 排查导入/转写失败

- 导入视频时，先看 `ASRService.swift` 里的音频导出逻辑。
- 导入普通音频时，重点看 `AudioPreprocessor.prepareForTranscription`。
- 空转写结果会被显式视为错误。

### 排查录音失败

- 先确认麦克风权限。
- 再看 `AudioRecorder.startRecording()` 是否成功创建 `AVAudioRecorder`。

## 验证方式

仓库当前没有独立测试目标。做改动后，优先做这些验证：

1. Xcode 能正常构建。
2. 模型加载完成后状态从“加载模型”切到“空闲”。
3. 导入一个音频文件可以得到转写结果。
4. 录音、停止录音、播放录音链路可用。

## 文档约定

- 面向用户的说明写在 `README.md`，使用中文。
- 面向协作者的约束和仓库规则写在 `AGENTS.md`。
