param(
    [Parameter(Mandatory=$true)][string]$RendererSource,
    [Parameter(Mandatory=$true)][string]$BuildDirectory,
    [ValidateRange(1, 64)][int]$Parallel = 4
)
# Run in a VS x64 developer shell with LLVM 23.1.3, CMake and Ninja on PATH.
$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $RendererSource).Path
$build = [IO.Path]::GetFullPath($BuildDirectory)
$revision = git -C $source rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Cannot read the renderer checkout revision' }
switch ($revision) {
    '3e2b8d76d2c38b5da09aadf5b8be7ff76d7f6d64' {
        $patchName = 'rx6600xt-renderer.patch'
        $diagnostics = 'ON'
        $targets = @('ryty_gpu', 'ryty_np')
        $artifacts = @('libSceVideoOut.prx', 'libSceNpAuth.prx')
    }
    '5305aa61b80a5392302e9b50e7d7e80ebf04981c' {
        $patchName = 'rx6600xt-renderer-5305aa6.patch'
        $diagnostics = 'AUTO'
        $targets = @('ryty_gpu')
        $artifacts = @('libSceVideoOut.prx')
    }
    default { throw "Unsupported renderer revision $revision" }
}
$patch = Join-Path $PSScriptRoot $patchName
# Accept a fresh checkout or a repeat build with this patch already applied.
git -C $source apply --reverse --check --quiet $patch
if ($LASTEXITCODE -ne 0) {
    git -C $source apply $patch
    if ($LASTEXITCODE -ne 0) { throw 'Renderer sources do not match the patch' }
}
$llvm = Split-Path (Split-Path (Get-Command clang-cl.exe).Source -Parent) -Parent
$builtins = Get-ChildItem "$llvm/lib/clang" -Recurse -Filter clang_rt.builtins-x86_64.lib | Select-Object -First 1
if (!$builtins -or !$env:VCINSTALLDIR) { throw 'A VS x64 developer shell and LLVM compiler runtime are required' }
$oldLib = $env:LIB
try {
    $env:LIB = "$($builtins.DirectoryName);$oldLib"
    $ninja = (Get-Command ninja.exe).Source.Replace('\','/')
    $rc = (Get-Command rc.exe).Source.Replace('\','/')
    cmake -S $source -B $build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang-cl -DCMAKE_CXX_COMPILER=clang-cl -DCMAKE_LINKER=lld-link "-DCMAKE_MAKE_PROGRAM=$ninja" "-DCMAKE_RC_COMPILER=$rc" -DCMAKE_NINJA_CMCLDEPS_RC=0 -DSHADGT_RYTY_GPU=ON "-DSHADGT_DIAGNOSTICS=$diagnostics" -DHAVE_ENDIAN_H=OFF -DENABLE_DISCORD_RPC=ON
    if ($LASTEXITCODE -ne 0) { throw 'Renderer configuration failed' }
    cmake --build $build --target @targets --parallel $Parallel
    if ($LASTEXITCODE -ne 0) { throw 'Renderer build failed' }
    foreach ($file in $artifacts) {
        Get-FileHash -LiteralPath (Join-Path $build $file)
    }
} finally { $env:LIB = $oldLib }
