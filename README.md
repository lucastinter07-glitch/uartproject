# UART Serial Transceiver (VHDL)

A Universal Asynchronous Receiver/Transmitter implemented in VHDL and verified
entirely in simulation with GHDL and GTKWave. No FPGA hardware required.

## Architecture

Three RTL blocks wired together in `uart_top`:

- **baud_gen** — divides the system clock to a single 16x oversample tick.
- **uart_tx** — FSM that serializes a byte with 8N1 framing (LSB first).
- **uart_rx** — FSM that synchronizes the input, detects the start bit, samples
  each bit at its midpoint via 16x oversampling, and recovers the byte.

The headline test wires `serial_out` back into `serial_in` (loopback) and asserts
that every transmitted byte is received intact.

## Configuration

Defaults: 50 MHz system clock, 9600 baud, 16x oversampling, 8N1. All three are
entity generics (`g_clk_freq_hz`, `g_baud_rate`, `g_oversample`), so a different
baud rate is a one-line change.

## Layout

```
rtl/      synthesizable design sources
tb/       self-checking testbenches
run.ps1   build + simulate harness
```

## Build & simulate

Requires GHDL (>= 5.0) and GTKWave on PATH.

```powershell
.\run.ps1                    # build + run tb_baud_gen (default)
.\run.ps1 tb_uart_loopback   # build + run a specific testbench
gtkwave tb_baud_gen.vcd      # inspect the waveform
```

## Status

| Component     | Status      |
|---------------|-------------|
| baud_gen      | in progress |
| uart_tx       | not started |
| uart_rx       | not started |
| uart_top      | not started |
| loopback test | not started |

<!-- Phase 5: embed the annotated GTKWave loopback screenshot here. -->