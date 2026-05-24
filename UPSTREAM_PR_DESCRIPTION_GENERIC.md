## Title
Fix repeated-generation crash by resetting freed params tensor backend pointers

## Summary
This patch fixes a same-process repeated-generation crash (e.g. `SD_CLI_REPEAT_GENERATE=2`) caused by stale backend tensor state after parameter-buffer free/reuse.

Crash signature before patch:
- Access violation on second generation call in backend buffer/tensor paths
- Reproduced on CUDA and Vulkan

## Root Cause
`free_params_buffer()` freed the params backend buffer but left parameter tensors in `params_ctx` with stale backend fields:
- `tensor->buffer`
- `tensor->data`
- `tensor->extra`

On a later generation call, compute paths could reuse those stale references and enter backend code that treated them as valid.

## Fix
File:
- `src/ggml_extend.hpp`

Changes:
1. In `GGMLRunner::free_params_buffer()`, clear backend fields for all tensors in `params_ctx` after freeing `params_buffer`.
2. In `GGMLRunner::compute(...)`, lazily re-allocate params buffer when needed before graph/offload work:
   - if not currently offloaded,
   - and `params_buffer == nullptr`,
   - and params tensors exist.

## Repro (Before)
From `stable-diffusion.cpp` folder:

```powershell
$env:SD_CLI_REPEAT_GENERATE='2'
./build-cli-vulkan/bin/RelWithDebInfo/sd-cli.exe ...
./build-cli-cuda/bin/RelWithDebInfo/sd-cli.exe ...
```

Observed: second call crashes with access violation.

## Verification (After)
- Vulkan: two-call generation runs and saves output.
- CUDA: two-call generation runs and saves output.
- ASan Vulkan build: no access-violation report for the same two-call repro.

Representative command options validated:
- `--sampling-method euler_a`
- `--scheduler karras`
- `--sampling-method ddim_trailing`

## Notes
- Earlier nonzero matrix entries during validation were from invalid CLI option tokens, not memory faults.
- This patch is narrowly scoped to params buffer lifecycle and does not alter model math or scheduler behavior.
