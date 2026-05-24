# FC Tycoon stable-diffusion.cpp Fork Workflow

This document describes the fork layout used in the FC Tycoon workspace, the custom patches that currently exist, and the safe update flow for pulling vendor changes while keeping FC Tycoon changes isolated.

## Repository Shape

The clone uses a two-layer vendor structure:

- `stable-diffusion.cpp/` is the parent repo.
- `stable-diffusion.cpp/ggml/` is a nested git submodule repo with its own fork and branch workflow.

Both repos use the same branch model:

- `master` is the clean vendor branch.
- `fc-tycoon/custom` carries FC Tycoon-specific changes.

Both repos also use the same remote naming:

- `origin` is the FC Tycoon fork used for pushes.
- `upstream` is the vendor repo used for fetch and rebase.

Current remote intent:

- Parent repo `upstream`: `https://github.com/leejet/stable-diffusion.cpp`
- Parent repo `origin`: `git@github.com:fc-tycoon/stable-diffusion.cpp.git`
- `ggml` repo `upstream`: `https://github.com/leejet/ggml.git`
- `ggml` repo `origin`: `git@github.com:fc-tycoon/ggml.git`

## Why The Branches Are Split

The goal is to keep vendor history and FC Tycoon changes separate.

- `master` stays rebased-free and custom-change-free.
- `fc-tycoon/custom` is the only branch that should absorb local commits.
- Rebases happen onto `upstream/master`, not onto local `master` after ad hoc edits.

That shape avoids the common failure mode where vendor updates and local fixes are mixed together on one branch and become hard to reason about.

## Current FC Tycoon Changes

### `ggml` custom branch

Branch: `fc-tycoon/custom`

Custom commit:

- `c1fc29aa` `build(ggml-hip): gate MMF template sources`

Behavioral intent:

- Adds a `GGML_HIP_NO_MMF` gate in `src/ggml-hip/CMakeLists.txt`.
- Avoids compiling MMF template sources when that backend path is intentionally disabled.

### `stable-diffusion.cpp` custom branch

Branch: `fc-tycoon/custom`

Custom commit:

- `d34835d` `fix: preserve fc-tycoon stable-diffusion runtime fixes`

Included changes:

- CLI support for repeating image generation through `SD_CLI_REPEAT_GENERATE`.
- Preview callback start-step support so preview generation can begin from a controlled step rather than always step 1.
- Backend/device information accessors exported from the public API.
- GGML abort logging hook during backend initialization.
- LoRA diff-state pruning so zero-diff entries do not trigger unnecessary reloads.
- Final latent persistence before compute-buffer teardown.
- Parent repo submodule pointer updated to `ggml` commit `c1fc29aa`.

## Local Scratch Files

These are intentionally not part of the preserved code history:

- `CRASH_REPEAT_GENERATE_ROOT_CAUSE.md`
- `UPSTREAM_PR_DESCRIPTION_GENERIC.md`
- `tmp/`

`tmp/` is ignored in `.gitignore` because it contains generated outputs and investigation artifacts rather than source.

## Safe Update Flow

Always update `ggml` first, then the parent repo.

### 1. Inspect incoming vendor changes

`ggml`:

```powershell
git -C "C:\dev\fc-tycoon-go\stable-diffusion.cpp\ggml" fetch upstream
git -C "C:\dev\fc-tycoon-go\stable-diffusion.cpp\ggml" log --oneline fc-tycoon/custom..upstream/master
```

Parent repo:

```powershell
git -C "C:\dev\fc-tycoon-go\stable-diffusion.cpp" fetch upstream
git -C "C:\dev\fc-tycoon-go\stable-diffusion.cpp" log --oneline fc-tycoon/custom..upstream/master
```

### 2. Rebase the `ggml` custom branch

```powershell
git -C "C:\dev\fc-tycoon-go\stable-diffusion.cpp\ggml" switch fc-tycoon/custom
git -C "C:\dev\fc-tycoon-go\stable-diffusion.cpp\ggml" rebase upstream/master
```

If conflicts appear:

- resolve them in `ggml`
- run `git -C "C:\dev\fc-tycoon-go\stable-diffusion.cpp\ggml" add <files>`
- continue with `git -C "C:\dev\fc-tycoon-go\stable-diffusion.cpp\ggml" rebase --continue`

When the rebase is complete:

```powershell
git -C "C:\dev\fc-tycoon-go\stable-diffusion.cpp\ggml" push --force-with-lease origin fc-tycoon/custom
```

### 3. Update the parent repo to the rebased `ggml` pointer

Once `ggml` rebases cleanly, the parent repo will see the submodule pointer move.

```powershell
git -C "C:\dev\fc-tycoon-go\stable-diffusion.cpp" status --short
```

That `ggml` pointer change should be committed together with any parent-repo conflict resolutions caused by the vendor update.

### 4. Rebase the parent custom branch

```powershell
git -C "C:\dev\fc-tycoon-go\stable-diffusion.cpp" switch fc-tycoon/custom
git -C "C:\dev\fc-tycoon-go\stable-diffusion.cpp" rebase upstream/master
```

If conflicts appear:

- resolve the parent repo files
- make sure the `ggml` submodule pointer stays on the intended rebased custom commit
- continue with `git -C "C:\dev\fc-tycoon-go\stable-diffusion.cpp" rebase --continue`

When the rebase is complete:

```powershell
git -C "C:\dev\fc-tycoon-go\stable-diffusion.cpp" push --force-with-lease origin fc-tycoon/custom
```

## Daily Working Rules

- Do not commit FC Tycoon changes on `master` in either repo.
- Do not use plain `git pull` on `fc-tycoon/custom` unless the configured pull behavior is explicitly what you intend.
- Prefer `fetch`, inspect, then `rebase`.
- Rebase `ggml` before rebasing the parent repo.
- Keep generated investigation output under `tmp/` so it stays ignored.

## Quick Recovery Checks

Check remotes:

```powershell
git -C "C:\dev\fc-tycoon-go\stable-diffusion.cpp" remote -v
git -C "C:\dev\fc-tycoon-go\stable-diffusion.cpp\ggml" remote -v
```

Check branch roles:

```powershell
git -C "C:\dev\fc-tycoon-go\stable-diffusion.cpp" branch -vv
git -C "C:\dev\fc-tycoon-go\stable-diffusion.cpp\ggml" branch -vv
```

Check current deltas against vendor:

```powershell
git -C "C:\dev\fc-tycoon-go\stable-diffusion.cpp" log --oneline upstream/master..fc-tycoon/custom
git -C "C:\dev\fc-tycoon-go\stable-diffusion.cpp\ggml" log --oneline upstream/master..fc-tycoon/custom
```