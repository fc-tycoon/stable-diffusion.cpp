param(
    [switch]$IncludeServerFrontend
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$ggmlPath = Join-Path $repoRoot 'ggml'
$expectedParentBranch = 'fc-tycoon/custom'

function Get-GitOutput {
    param(
        [string]$RepoPath,
        [string[]]$GitArgs
    )

    $output = & git -C $RepoPath @GitArgs
    if ($LASTEXITCODE -ne 0) {
        throw "git -C '$RepoPath' $($GitArgs -join ' ') failed with exit code $LASTEXITCODE"
    }

    return ($output | Out-String).Trim()
}

$parentBranch = Get-GitOutput -RepoPath $repoRoot -GitArgs @('branch', '--show-current')
if ($parentBranch -ne $expectedParentBranch) {
    throw "Parent repo is on '$parentBranch'. Switch to '$expectedParentBranch' before building."
}

$submodules = @(
    'ggml',
    'thirdparty/libwebp',
    'thirdparty/libwebm'
)

if ($IncludeServerFrontend) {
    $submodules += 'examples/server/frontend'
}

$updateArgs = @('-C', $repoRoot, 'submodule', 'update', '--init', '--') + $submodules
& git @updateArgs
if ($LASTEXITCODE -ne 0) {
    throw "Failed to initialize build submodules: $($submodules -join ', ')"
}

$expectedGgmlCommit = Get-GitOutput -RepoPath $repoRoot -GitArgs @('rev-parse', ':ggml')
$actualGgmlCommit = Get-GitOutput -RepoPath $ggmlPath -GitArgs @('rev-parse', 'HEAD')
if ($expectedGgmlCommit -ne $actualGgmlCommit) {
    throw "ggml is at '$actualGgmlCommit' but the parent repo pins '$expectedGgmlCommit'. Run 'git -C `"$repoRoot`" submodule update --init -- ggml' and retry."
}

$ggmlBranch = Get-GitOutput -RepoPath $ggmlPath -GitArgs @('rev-parse', '--abbrev-ref', 'HEAD')
$parentDirty = Get-GitOutput -RepoPath $repoRoot -GitArgs @('status', '--short')

Write-Host "Parent branch: $parentBranch"
Write-Host "ggml pinned commit: $actualGgmlCommit"

if ($ggmlBranch -eq 'HEAD') {
    Write-Host 'ggml checkout: detached at the pinned commit (correct build state)'
} elseif ($ggmlBranch -eq $expectedParentBranch) {
    Write-Host "ggml checkout: $ggmlBranch at the pinned commit"
} else {
    Write-Warning "ggml is on branch '$ggmlBranch'. Detached HEAD or '$expectedParentBranch' is expected for FC Tycoon builds."
}

if ($parentDirty) {
    Write-Warning 'Parent repo has local modifications. The build will use working-tree content, not just committed history.'
}

Write-Host "Initialized submodules: $($submodules -join ', ')"
Write-Host 'FC Tycoon build state looks good.'