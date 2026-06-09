# run.ps1 - UART project build + simulation harness
#
# Usage:
#   .\run.ps1                   # build + run tb_baud_gen (default)
#   .\run.ps1 tb_uart_tx        # build + run a specific testbench
#
# Requires GHDL and GTKWave on PATH.

param(
    [string]$Top = "tb_baud_gen"
)

$ErrorActionPreference = "Stop"
$Std = "--std=08"

# Run GHDL and abort if it returns a non-zero exit code (PowerShell's Stop
# preference does NOT catch native-exe failures on its own).
function Invoke-GHDL {
    param([string[]]$GhdlArgs)
    & ghdl @GhdlArgs
    if ($LASTEXITCODE -ne 0) {
        throw "GHDL failed (exit $LASTEXITCODE): ghdl $($GhdlArgs -join ' ')"
    }
}

$Sources = Get-ChildItem -Path rtl\*.vhd, tb\*.vhd -ErrorAction SilentlyContinue
if (-not $Sources) { throw "No .vhd files found in rtl\ or tb\." }

Write-Host "==> Importing $($Sources.Count) source file(s)..." -ForegroundColor Cyan
Invoke-GHDL (@('-i', $Std) + $Sources.FullName)

Write-Host "==> Building $Top (dependency-ordered analyze + elaborate)..." -ForegroundColor Cyan
Invoke-GHDL @('-m', $Std, $Top)

Write-Host "==> Running $Top..." -ForegroundColor Cyan
Invoke-GHDL @('-r', $Std, $Top, "--vcd=$Top.ghw")

Write-Host ""
Write-Host "==> PASS: GHDL exited cleanly. Inspect the waveform with:" -ForegroundColor Green
Write-Host "    gtkwave $Top.ghw"