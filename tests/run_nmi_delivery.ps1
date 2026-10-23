[CmdletBinding()]
param([string]$VerilatorBin = '', [switch]$NoBuild)

$ErrorActionPreference = 'Stop'
$repoPath = Split-Path -Parent $PSScriptRoot
$savedPath = $env:PATH
$savedVerilatorRoot = $env:VERILATOR_ROOT
Push-Location -LiteralPath $repoPath
try {
    if (!$VerilatorBin) {
        $ossPath = (Resolve-Path -LiteralPath '../../tools/oss-cad-suite').Path
        $devPath = (Resolve-Path -LiteralPath '../../tools/w64devkit').Path
        $env:PATH = "$devPath/bin;$ossPath/bin;$ossPath/lib;$env:PATH"
        $env:VERILATOR_ROOT = "$ossPath/share/verilator"
        $VerilatorBin = "$ossPath/bin/verilator_bin.exe"
    }
    if (!$NoBuild) {
        $sources = @(
            'P65C816_pkg.sv', 'P65C816.sv', 'AddrGen.sv', 'BCDAdder.v',
            'AddSubBCD.sv', 'ALU.sv', 'bit_adder.v', 'adder4.v', 'mcode.sv'
        ) | ForEach-Object { "rtl/65C816/$_" }
        & $VerilatorBin --binary --timing -j 1 --top-module apple_nmi_delivery_tb `
            -MAKEFLAGS 'OPT_FAST=-O0 OPT_SLOW=-O0 OPT_GLOBAL=-O0 OBJCACHE=' `
            -Wno-fatal -Irtl/65C816 --Mdir tests/obj_nmi_delivery `
            @sources tests/nmi_delivery_tb.sv *> tests/nmi_delivery_build.log
        if ($LASTEXITCODE -ne 0) {
            Get-Content -LiteralPath tests/nmi_delivery_build.log -Tail 25
            throw 'Verilator build failed.'
        }
    }
    $passed = 0
    $logPath = Join-Path $PSScriptRoot 'nmi_delivery_results.log'
    '' | Set-Content -LiteralPath $logPath
    foreach ($nested in @(0, 1)) {
        $phaseCount = if ($nested) { 28 } else { 196 }
        foreach ($native in @(0, 1)) {
            foreach ($divider in @(1, 14)) {
                for ($phase = 0; $phase -lt $phaseCount; $phase++) {
                    $caseArgs = @("+NATIVE=$native", "+CE_DIV=$divider", "+PHASE=$phase", "+NESTED=$nested")
                    ('$ ' + ($caseArgs -join ' ')) | Add-Content -LiteralPath $logPath
                    $result = & './tests/obj_nmi_delivery/Vapple_nmi_delivery_tb.exe' @caseArgs 2>&1
                    $caseExit = $LASTEXITCODE
                    $result | Add-Content -LiteralPath $logPath
                    if ($caseExit -ne 0 -or !($result -match '^RESULT ')) {
                        $result | Write-Output
                        throw "NMI delivery failed: native=$native divider=$divider phase=$phase nested=$nested"
                    }
                    $passed++
                }
            }
        }
    }
    Write-Output "PASS: $passed production-CPU NMI delivery cases (784 held-edge, 112 nested-edge)."
}
finally {
    Pop-Location
    $env:PATH = $savedPath
    $env:VERILATOR_ROOT = $savedVerilatorRoot
}
