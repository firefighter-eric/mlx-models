# mlx-models

This app bundles exactly one MLX model into the app at build time.

## Local model layout

Store local models outside the repo under:

```text
~/models/<org>/<model>/
```

The project expects MLX-style model directories and defaults to:

```text
~/models/mlx-community/Qwen3-ASR-0.6B-4bit
```

## Project-local symlink

Create a local symlink for browsing models from inside the project:

```sh
ln -s ~/models /Users/eric/projects/mlx-models/mlx-models/Models
```

The symlink is intentionally ignored by git and is not added as an Xcode resource.

## Selecting the bundled model

The Xcode target defines these build settings:

- `MODEL_ROOT`
- `MODEL_ORG`
- `MODEL_NAME`

At build time, a Run Script phase copies only:

```text
$(MODEL_ROOT)/$(MODEL_ORG)/$(MODEL_NAME)
```

into the app bundle as:

```text
Contents/Resources/Model
```

To switch models, change `MODEL_ORG` or `MODEL_NAME` in the target build settings. No code changes are required.

## Runtime behavior

The app only looks for the bundled model at `Bundle.main.resourceURL/Model`. It does not read directly from `~/models`.
