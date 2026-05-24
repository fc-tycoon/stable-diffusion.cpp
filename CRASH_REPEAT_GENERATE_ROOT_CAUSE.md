# Repeated-Generation Crash Root Cause Report (`sd-cli`, CUDA + Vulkan)

## Scope
This report documents the second-call crash (`SD_CLI_REPEAT_GENERATE=2`) investigated and fixed inside this folder only:

- `stable-diffusion.cpp/`

No repository-wide scan was required for this fix.

## Symptom
Running `sd-cli` with two image generations in the same process crashed on call #2 with access violation (`0xC0000005`) on both backends:

- Vulkan path near `ggml_vk_tensor_subbuffer`
- CUDA path near backend buffer-type checks

## Root Cause
The failure was a lifecycle bug in parameter tensor backend pointers.

### What went wrong
1. `free_params_buffer()` released `params_buffer` memory.
2. Model tensors in `params_ctx` still retained stale backend fields (`tensor->buffer`, `tensor->data`, `tensor->extra`).
3. On the next generation call, compute code reused those tensors and reached backend code that treated those stale references as valid.
4. Vulkan ASan trace showed the invalid read in shared_ptr refcount increment while creating a tensor subbuffer during CLIP graph build.

### Why this crashed on call #2
The first call allocated and used valid backend buffers. After free/reuse, stale tensor metadata survived, so call #2 hit invalid backend state.

## Code Changes
File changed:

- `stable-diffusion.cpp/src/ggml_extend.hpp`

### 1) Clear tensor backend state when freeing params buffer
In `GGMLRunner::free_params_buffer()`, after `ggml_backend_buffer_free(params_buffer)`, clear all tensor backend fields in `params_ctx`:

- `t->buffer = nullptr`
- `t->data = nullptr`
- `t->extra = nullptr`

### 2) Re-allocate params buffer before compute reuse
In `GGMLRunner::compute(...)`, before offload/compute graph allocation:

- If params are not currently offloaded and `params_buffer == nullptr` and there are params tensors, call `alloc_params_buffer()`.

This guarantees a valid params backend allocation before any second-call graph execution.

## Evidence Collected

### ASan (Vulkan) before fix
ASan reported access violation in this path on call #2:

- `ggml_vk_tensor_subbuffer` (`ggml-vulkan.cpp`)
- `ggml_vk_op_f32` -> `ggml_vk_get_rows`
- `ggml_vk_build_graph`
- `GGMLRunner::compute`
- CLIP conditioner path (`get_learned_condition`)

### After fix
- Same ASan Vulkan repro executes both calls without sanitizer fault.
- Non-ASan Vulkan and CUDA binaries execute both calls without crash.

## Repro and Verification Commands
Run from:

- `<repo>/stable-diffusion.cpp`

Set model path used in these examples:

```powershell
$model = '<path-to-model>.safetensors'
$prompt = 'portrait photo, high detail'
```

### 1) Build Vulkan and CUDA `sd-cli`
```powershell
cmake --build build-cli-vulkan --config RelWithDebInfo --target sd-cli -j 8
cmake --build build-cli-cuda   --config RelWithDebInfo --target sd-cli -j 8
```

### 2) Two-call crash repro (now expected to pass)
```powershell
$env:SD_CLI_REPEAT_GENERATE='2'
.\build-cli-vulkan\bin\RelWithDebInfo\sd-cli.exe -m $model --type f16 --sampling-method euler_a --steps 24 --cfg-scale 7 --seed 12345 --width 256 --height 256 -p $prompt -o tmp\vulkan-fixed\baseline.png
.\build-cli-cuda\bin\RelWithDebInfo\sd-cli.exe   -m $model --type f16 --sampling-method euler_a --steps 24 --cfg-scale 7 --seed 12345 --width 256 --height 256 -p $prompt -o tmp\cuda-fixed\baseline.png
```

### 3) Variant sanity matrix (already run)
Artifacts:

- `tmp/sd-matrix-results-fixed.json`
- `tmp/sd-matrix-results-fixed-tail.json`

Interpretation notes:

- Early nonzero results for `scheduler_karras`/`ddim` were CLI flag token issues (`--schedule` and unsupported `ddim` token), not memory faults.
- Corrected checks passed with:
  - `--scheduler karras`
  - `--sampling-method ddim_trailing`

### 4) ASan verification (Vulkan)
If you want sanitizer-level verification again:

```powershell
cmake --build build-cli-vulkan-asan --config RelWithDebInfo --target sd-cli -j 8
$env:SD_CLI_REPEAT_GENERATE='2'
.\build-cli-vulkan-asan\bin\RelWithDebInfo\sd-cli.exe -m $model --type f16 --sampling-method euler_a --steps 24 --cfg-scale 7 --seed 12345 --width 256 --height 256 -p $prompt -o tmp\vulkan-asan-fixed.png
```

Expected result: both calls run, output image saved, no ASan access-violation report.

## What “port this patch to downstream Node addon project” means
It means applying the same lifecycle fix to whichever vendored upstream source that downstream project compiles against (its copy/submodule of `stable-diffusion.cpp`), then rebuilding that project and rerunning its local generation flow.

In short: same bug class, same patch pattern, in the source tree actually used by `facegen-sd15-cpp`.

## Minimal upstream PR contents
1. Patch in `src/ggml_extend.hpp` (the two changes above).
2. Repro steps using `SD_CLI_REPEAT_GENERATE=2`.
3. Before/after behavior summary.
4. Mention that corrected CLI options are:
   - `--scheduler karras`
   - `--sampling-method ddim_trailing`
