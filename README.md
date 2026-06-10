# UART Serial Transceiver (VHDL)

A parameterized **UART serial transceiver** written in VHDL-2008 and verified
end-to-end in simulation with **GHDL** and **GTKWave**. Implements full-duplex
8N1 framing at 9600 baud on a 50 MHz clock, with 16× oversampling, a
clock-domain-crossing input synchronizer, glitch rejection, and framing-error
detection — all proven by a self-checking testbench suite.

> Status: core build complete. All four RTL modules implemented and verified
> (milestones M1–M4). FPGA hardware bring-up is in progress.

---

## Highlights

- **Two-process FSMs** (combinational next-state + clocked datapath/outputs) for
  both transmitter and receiver — registered outputs, no inferred latches.
- **Single coherent timebase:** one 16× oversample tick is generated and shared
  by TX and RX, so the two paths can never disagree on bit width.
- **Metastability-safe receiver:** a 2-flip-flop synchronizer re-times the
  asynchronous input before any logic reads it.
- **Correct midpoint sampling:** the receiver anchors at the middle of the start
  bit and samples each data bit a full bit-period later, at its own midpoint.
- **Robustness, tested:** directed tests prove the receiver rejects sub-half-bit
  line glitches and flags framing errors on malformed stop bits.
- **Fully parameterized** via generics (`g_clk_freq_hz`, `g_baud_rate`,
  `g_oversample`) — change baud rate or clock with a one-line edit.
- **Self-checking testbenches** with `assert`/`report`, self-terminating via
  `std.env.finish`.

---

## Architecture

```
                          uart_top
   ┌───────────────────────────────────────────────────────┐
   │  clk, rst ─► baud_gen ─► sample_tick (16× baud) ─┬──┐   │
   │                                                  │  │   │
   │  tx_data ─►┌──────────┐                          ▼  │   │
   │  tx_start ►│ uart_tx  │── serial_out ───────────────┼──►│ serial_out (pin)
   │  tx_busy ◄─└──────────┘                             │   │
   │                                                     ▼   │
   │  serial_in (pin) ─►[2-FF sync]►┌──────────┐  sample_tick│
   │                                │ uart_rx  │── rx_data ──┼──► rx_data
   │                                └──────────┘── data_valid┼──► data_valid
   │                                            ── framing_error──►
   └───────────────────────────────────────────────────────┘

   Loopback test: serial_out ─► serial_in (tied in the testbench)
```

| Module       | Role                                                              |
|--------------|------------------------------------------------------------------|
| `baud_gen`   | Divides the clock to a single 1-cycle `sample_tick` at 16× baud.  |
| `uart_tx`    | FSM that serializes a byte as an 8N1 frame (start, 8 data LSB-first, stop). |
| `uart_rx`    | FSM that synchronizes the input, detects the start bit, samples each bit at its midpoint, and recovers the byte. |
| `uart_top`   | Structural top level; wires the three blocks and shares one tick. |

---

## Repository layout

```
rtl/
  baud_gen.vhd        oversample tick generator
  uart_tx.vhd         transmitter FSM
  uart_rx.vhd         receiver FSM (+ 2-FF synchronizer)
  uart_top.vhd        structural top level
tb/
  tb_baud_gen.vhd     tick-spacing check
  tb_uart_tx.vhd      frame-format check
  tb_uart_rx.vhd      byte recovery + glitch/framing tests
  tb_uart_loopback.vhd  end-to-end loopback (real baud_gen)
run.ps1               build + simulate harness
README.md
```

---

## Build & simulate

Requires **GHDL** (≥ 5.0) and **GTKWave** on `PATH`.

```powershell
# Build + run any testbench (PowerShell harness)
.\run.ps1 tb_uart_loopback

# Inspect the waveform
gtkwave tb_uart_loopback.ghw
```

Or with raw GHDL:

```bash
ghdl -i --std=08 rtl/*.vhd tb/*.vhd
ghdl -m --std=08 tb_uart_loopback
ghdl -r --std=08 tb_uart_loopback --wave=tb_uart_loopback.ghw
```

The harness dumps **GHW** (not VCD) so enumerated FSM state signals are visible
in GTKWave.

---

## Verification

| Milestone | Testbench              | Proves                                              |
|-----------|------------------------|-----------------------------------------------------|
| M1        | `tb_baud_gen`          | Exact 16× tick spacing (326 cycles @ 9600/50 MHz).  |
| M2        | `tb_uart_tx`           | Correct 8N1 frame, LSB-first, for 0x55/AA/00/FF/41/61. |
| M3        | `tb_uart_rx`           | Byte recovery; glitch rejection; framing-error flag. |
| M4        | `tb_uart_loopback`     | TX→RX round trip through the real baud generator, per-byte and back-to-back burst. |

All testbenches are self-checking (`assert`/`report`) and self-terminating.

### Waveforms

![Single 0x55 frame, loopback](docs/img/loopback_frame.png)

*One frame: start bit, eight LSB-first data bits, stop bit, with `data_valid`
strobing the recovered byte onto `rx_data`. The TX and RX state machines run in
lockstep on the shared `sample_tick`.*

![Full 12-byte loopback run](docs/img/loopback_full.png)

*All twelve bytes (per-byte round trip + back-to-back burst). Each transmitted
byte reappears on `rx_data` one frame later; `framing_error` stays low throughout.*

---

## Configuration

All three blocks take generics; defaults target 9600 baud on a 50 MHz clock:

| Generic         | Default      | Meaning                          |
|-----------------|--------------|----------------------------------|
| `g_clk_freq_hz` | `50_000_000` | System clock frequency           |
| `g_baud_rate`   | `9_600`      | Target UART baud rate            |
| `g_oversample`  | `16`         | RX oversampling factor           |

The clock divisor is computed at elaboration (`round(clk / (baud × oversample))`)
and counter widths are sized automatically — so retargeting to, e.g., 115200
baud on a 100 MHz board is a one-line generic change.

---

## Design notes

- **8N1, LSB-first**, idle-high line.
- **Synchronous, active-high reset** throughout (single clock domain).
- The transmitter and receiver each count `g_oversample` ticks per bit, so a
  single divisor governs all timing.
- The receiver validates the start bit at its midpoint (rejecting glitches
  shorter than half a bit) before committing to a frame.

## Possible extensions

- Parity (7E1 / 8O1) and configurable data width.
- TX/RX FIFOs with an AXI-Stream interface.
- Multi-channel instantiation.
- Runtime-configurable baud via a register interface.

## License

MIT — see `LICENSE`.