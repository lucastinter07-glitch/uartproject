# UART Serial Transceiver (VHDL)

A parameterized **UART serial transceiver** written in VHDL-2008 and verified
end-to-end in simulation with **GHDL** and **GTKWave**. Implements full-duplex
8N1 framing at 9600 baud on a 50 MHz clock, with 16× oversampling, a
clock-domain-crossing input synchronizer, glitch rejection, and framing-error
detection. All features proven by a self-checking testbench suite.

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

![Architecture](<img width="1447" height="919" alt="IMG_0134" src="https://github.com/user-attachments/assets/a3f57841-904c-4372-bd2d-981ca814c029" />)


`uart_top` is purely structural. `uart_tx` and `uart_rx` each pair a **shift
register** (the datapath) with a **control FSM** (the controller). A single
`baud_gen` produces one 16× `sample_tick` that is shared by both FSMs, so they
count the same ticks per bit and can never drift apart. On the receive side,
`serial_in` is asynchronous, so it first passes through a **2-flip-flop
synchronizer** before the receiver logic reads it. There are no separate hold
registers — without a FIFO, the transmitter loads `tx_data` straight into its
shift register and the receiver latches each finished byte onto `rx_data`. The
loopback path (dashed) is tied only in the testbench.

| Module       | Role                                                              |
|--------------|------------------------------------------------------------------|
| `baud_gen`   | Divides the clock to a single 1-cycle `sample_tick` at 16× baud.  |
| `uart_tx`    | FSM + shift register that serializes a byte as an 8N1 frame (start, 8 data LSB-first, stop). |
| `uart_rx`    | 2-FF synchronizer + FSM + shift register that detects the start bit, samples each bit at its midpoint, and recovers the byte. |
| `uart_top`   | Structural top level; instantiates the three blocks and shares one tick. |

---

## Frame format (8N1)

![8N1 frame timing](<img width="1209" height="345" alt="IMG_0135" src="https://github.com/user-attachments/assets/2e475598-7dbc-4b7b-a54f-11d664cec524" />
)

The line idles high. A **start bit** (low) marks the beginning of a byte,
followed by **8 data bits sent LSB-first** (D0–D7), then a **stop bit** (high)
that returns the line to idle. The receiver samples each bit at its **midpoint**
(red), anchored from the middle of the start bit — the point farthest from the
switching edges, which gives maximum tolerance to clock mismatch between the two
ends.

---

## Repository layout

```
rtl/
  baud_gen.vhd          oversample tick generator
  uart_tx.vhd           transmitter FSM + shift register
  uart_rx.vhd           receiver FSM + shift register (+ 2-FF synchronizer)
  uart_top.vhd          structural top level
tb/
  tb_baud_gen.vhd       tick-spacing check
  tb_uart_tx.vhd        frame-format check
  tb_uart_rx.vhd        byte recovery + glitch/framing tests
  tb_uart_loopback.vhd  end-to-end loopback (real baud_gen)
run.ps1                 build + simulate harness
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
ghdl -i --std=08 rtl/*.vhd tb/*.vhd        # import: catalog the sources
ghdl -m --std=08 tb_uart_loopback          # make: analyze (dependency-ordered) + elaborate
ghdl -r --std=08 tb_uart_loopback --wave=tb_uart_loopback.ghw   # run
```

This uses GHDL's import/make flow (`-i`/`-m`) rather than the explicit
analyze/elaborate steps (`-a`/`-e`): `ghdl -m` works out the correct compile
order automatically, so `uart_top` (which instantiates the other modules) builds
without files being listed in dependency order by hand. The equivalent explicit
flow is `ghdl -a` (each file, in order) → `ghdl -e <top>` → `ghdl -r <top>`.

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

![Loopback simulation — full 8N1 frame](<img width="2687" height="1645" alt="Screenshot 2026-06-10 112757" src="https://github.com/user-attachments/assets/3d464627-6147-478c-a970-fe083029a190" />
)

Loopback simulation: a transmitted byte appears on `serial_line`, and the
receiver reproduces it on `rx_data` one frame later, accompanied by a
`data_valid` strobe. The two `state` rows (transmitter on top, receiver below)
advance in lockstep on the shared `sample_tick`, and `framing_error` stays low
throughout.

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
- **Synchronous reset** throughout (single clock domain).
- Datapath vs. control are kept separate: the shift registers hold and move the
  bits; the FSMs decide when to load, shift, sample, and signal.
- The transmitter and receiver each count `g_oversample` ticks per bit, so a
  single divisor governs all timing.
- The receiver validates the start bit at its midpoint (rejecting glitches
  shorter than half a bit) before committing to a frame.

## Possible extensions

- Parity (7E1 / 8O1) and configurable data width.
- TX/RX FIFOs with an AXI-Stream interface (this is where hold/buffer registers
  would reappear).
- Multi-channel instantiation.
- Runtime-configurable baud via a register interface.

## License

MIT — see `LICENSE`.
