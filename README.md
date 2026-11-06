# Booth Multiplier — Verilog RTL Implementation

> Parameterized, synthesizable implementation of **Booth's Multiplication Algorithm** using a Moore FSM + Datapath split.
> Designed and simulated on **Xilinx Vivado 2024.2** targeting the **Basys-3 (Artix-7 XC7A35T)**.

---

## What It Does

Booth's algorithm multiplies two signed n-bit two's-complement numbers to produce a correct signed 2n-bit product — without any special-casing for negative inputs.

It works by inspecting the multiplier's bits in overlapping pairs (`q0`, `qn1`). Runs of identical bits become pure shifts (free). Only transitions between 0→1 and 1→0 trigger an add or subtract. This reduces the number of arithmetic operations compared to naive shift-and-add, and handles signed inputs natively.

**Simulation result:**

| Input | Value |
|---|---|
| `multiplicand` | +15 (`01111`) |
| `multiplier` | −14 (`10010`) |
| `product` | −210 (`1100101110`) |

![Booth Multiplier Simulation Waveform](sim/waveforms/simulated_waveform.png)

The waveform shows `start` triggering the FSM, `SC` counting down from `n` to 0 across shift cycles, `partial_product` updating after each arithmetic shift, and `done` asserting when `{AC, QR}` holds the final result.

---

## Module Hierarchy

```
Booth_Multiplier  (top)
├── Booth_Control_Unit     — 7-state Moore FSM, control signals only
└── Booth_Datapath         — registers + arithmetic, status signals only
    ├── n_bit_adder_subtractor  — parameterized n-bit signed adder/subtractor (structural)
    │   └── full_adder ×n       — gate-level 1-bit full adder (xor/and/or primitives)
    └── sequence_counter        — parameterized down-counter, tracks iteration depth
```

The design uses a strict **ASM control-unit + datapath split**:
- Control unit only emits control signals (`ldAC`, `ashr`, `done`, …) — it never touches data.
- Datapath only consumes control signals and emits status signals (`q0`, `qn1`, `cntz`) — it never makes algorithmic decisions.

---

## Project Structure

```
Booth_Multiplier_Project/
├── src/
│   ├── Booth_Multiplier.v          ← Top-level, connects datapath ↔ control unit
│   ├── Booth_Control_Unit.v        ← Moore FSM (7 states)
│   ├── Booth_Datapath.v            ← AC, BR, QR registers + shift + product
│   ├── n_bit_adder_subtractor.v    ← Structural n-bit add/subtract
│   ├── sequence_counter.v          ← Iteration down-counter
│   └── full_adder.v                ← Gate-level 1-bit full adder
├── sim/
│   ├── testbench/
│   │   └── Booth_Multiplier_tb.v   ← Cycle-by-cycle trace testbench
│   └── waveforms/
│       └── simulated_waveform.png  ← Vivado simulation screenshot
├── docs/
│   └── PROJECT_REPORT.md           ← Full in-depth design analysis
├── .gitignore
└── README.md
```

---

## FSM State Table

| State | Action | Signals Asserted |
|---|---|---|
| S0 | IDLE — wait for `start` | (none) |
| S1 | Load operands | `ldBR`, `ldQR` |
| S2 | Initialise | `clrAC`, `clrff`, `ldCNT` |
| S3 | Add: `AC ← AC + BR` | `addsub_inst=1`, `cin=0`, `ldAC` |
| S4 | Subtract: `AC ← AC − BR` | `addsub_inst=1`, `cin=1`, `ldAC` |
| S5 | Arithmetic shift right + decrement counter | `ashr`, `decr` |
| S6 | DONE | `done` |

**Booth decision table** (determines S3/S4/S5 from S2 or S5):

| `q0` | `qn1` | Transition |
|---|---|---|
| 0 | 0 | → S5 (shift only) |
| 1 | 1 | → S5 (shift only) |
| 0 | 1 | → S3 (add) |
| 1 | 0 | → S4 (subtract) |

---

## Running the Simulation

1. Open Vivado → Create Project → Add all files from `src/` as **Design Sources**.
2. Add `sim/testbench/Booth_Multiplier_tb.v` as a **Simulation Source**.
3. Set `Booth_Multiplier_tb` as the top simulation module.
4. **Run Simulation → Run Behavioral Simulation**.

The testbench prints a cycle-by-cycle table of `AC`, `QR`, `BR`, `SC`, `qn1`, all control signals, and the final product.

### Changing Bit-Width

The design is fully parameterized. In the testbench:
```verilog
parameter n = 8;   // change to any bit-width
```

---

## Known Issues

| # | Issue | Status |
|---|---|---|
| 1 | `initial state = S0` — not ASIC-portable, relies on FPGA power-up init | Open — fix: add explicit synchronous reset |
| 2 | S6 loops forever — FSM cannot restart without hardware reset | Open — fix: `S6: if (!start) state <= S0` |
| 3 | Sequence counter wired to `ashred` instead of `decr` — adds 1-cycle delay | Open |
| 4 | `decr & SC>0` — bitwise `&` instead of logical `&&` | Open |
| 5 | `product` output is combinational, only valid for 1 cycle while in S6 | Open — fix: register product on done edge |

> See [`docs/PROJECT_REPORT.md`](docs/PROJECT_REPORT.md) for the full analysis of each bug, the design reasoning behind every decision, synthesizability notes, resource estimates, and future work.

---

## Synthesizability

**Fully synthesizable on Vivado/Basys-3.** No `#delays`, no `$display`, no `===` in the design sources. Gate-level primitives (`xor`, `and`, `or`, `buf`) are supported — Vivado maps them to LUTs during synthesis.

For ASIC portability, replace `initial` blocks with explicit synchronous resets.

**Resource estimate (n=8):** ~45–62 flip-flops + small LUT footprint. Well under 1% of the Basys-3 Artix-7's 33,280 logic cells.

---

## Future Work

- **Explicit reset** — add active-low synchronous reset for ASIC portability
- **Registered product output** — capture `{AC, QR}` into a register on the `done` edge so it persists across state transitions
- **Radix-4 (Modified) Booth** — examine 3-bit windows to halve the number of partial products and roughly double throughput
- **Faster adder** — replace ripple-carry chain with carry-lookahead or Xilinx DSP48E1 for large `n`
- **Valid/ready handshake** — replace bare `start`/`done` with an AXI-Stream compatible interface
- **Self-checking testbench** — exhaustively verify all `2^(2n)` input combinations with automated pass/fail

---

## Author

> **Digital System Design — Booth Multiplier Project**
> Implemented in Verilog | Simulated & synthesized on Xilinx Vivado 2024.2
