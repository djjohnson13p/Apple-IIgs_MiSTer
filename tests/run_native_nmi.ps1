[CmdletBinding()]
param([string]$VerilatorBin = '', [switch]$NoBuild)

$ErrorActionPreference = 'Stop'
$repoPath = Split-Path -Parent $PSScriptRoot
$savedPath = $env:PATH
$savedVerilatorRoot = $env:VERILATOR_ROOT
Push-Location -LiteralPath $repoPath
try {
    # Use the locally installed lab toolchain when a custom binary is omitted.
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
        & $VerilatorBin --binary --timing --top-module native_nmi_tb `
            -Wno-fatal -Irtl/65C816 --Mdir tests/obj_native_nmi `
            @sources tests/native_nmi_tb.sv *> tests/native_nmi_build.log
        if ($LASTEXITCODE -ne 0) {
            Get-Content -LiteralPath tests/native_nmi_build.log -Tail 30
            throw 'Verilator build failed.'
        }
    }
    $results = @()
    foreach ($m in @(0, 1)) {
        foreach ($sp in @('1ff0', '0103', '0004', 'ffff')) {
            foreach ($mode in @(0, 1)) {
                $result = & './tests/obj_native_nmi/Vnative_nmi_tb.exe' `
                    "+M=$m" "+SP=$sp" "+MODE=$mode" 2>&1
                $results += $result
                if ($LASTEXITCODE -ne 0) {
                    $results | Set-Content -LiteralPath tests/native_nmi_results.log
                    $result | Write-Output
                    throw "Native NMI test failed: M=$m SP=$sp MODE=$mode"
                }
                $result | Where-Object { "$_" -match '^PASS' } | Write-Output
            }
        }
    }
    $results | Set-Content -LiteralPath tests/native_nmi_results.log
    Write-Output 'PASS: 16 production-CPU native NMI diagnostic cases.'
}
finally {
    Pop-Location
    $env:PATH = $savedPath
    $env:VERILATOR_ROOT = $savedVerilatorRoot
}
