# Booth Multiplier — In-Depth Project Report

> **Platform:** Xilinx Vivado 2024.2 | **Target:** Basys-3 (Artix-7 XC7A35T)
> **Language:** Verilog HDL | **Style:** Structural + RTL, fully synthesizable

---

## Table of Contents

1. [What Does This Project Do?](#1-what-does-this-project-do)
2. [Architecture](#2-architecture)
3. [Algorithm Walkthrough](#3-algorithm-walkthrough)
4. [Module-by-Module Breakdown](#4-module-by-module-breakdown)
5. [Known Issues & Bugs](#5-known-issues--bugs)
6. [Will It Synthesize?](#6-will-it-synthesize)
7. [Resource Estimate](#7-resource-estimate)
8. [Future Work & How to Do It](#8-future-work--how-to-do-it)
9. [Optimizations](#9-optimizations)
10. [Design Reasoning Cheatsheet](#10-design-reasoning-cheatsheet)

---

## 1. What Does This Project Do?

This project implements **Booth's Multiplication Algorithm** as a synthesizable, parameterized RTL design in Verilog.

### The Problem It Solves

Multiplying two signed binary numbers in two's complement is not straightforward. Naive shift-and-add works only for unsigned numbers. Extending it to signed inputs requires either sign extension tricks or handling MSB separately — both messy.

**Booth's algorithm solves this cleanly:**
- Treats the multiplier's bits in overlapping pairs (`q0` and `qn1`, i.e., current bit and the previously shifted-out bit).
- Encodes runs of identical bits as pure shifts — no addition needed. Only transitions between 0→1 and 1→0 require arithmetic.
- Naturally handles both positive and negative (two's complement) signed operands without any special-casing.

### What This Design Computes

Given two signed n-bit inputs, it produces a correct signed 2n-bit product using sequential shift-and-add operations controlled by a Moore FSM.

**Example (from simulation):**
```
multiplicand  =  15  (01111)
multiplier    = -14  (10010)
product       = -210 (1100101110 in 10-bit two's complement)
```

---

## 2. Architecture

The design uses the classic **ASM (Algorithmic State Machine) split** — the two most important RTL partitioning rules applied together:

```
Booth_Multiplier (top)
├── Booth_Control_Unit  — Moore FSM, 7 states, emits control signals only
└── Booth_Datapath      — registers + arithmetic, consumes control signals, emits status
    ├── n_bit_adder_subtractor  — parameterized n-bit signed add/subtract
    │   └── full_adder ×n      — structural gate-level 1-bit full adder
    └── sequence_counter        — parameterized down-counter for iteration tracking
```

### Why Split Control from Datapath?

This is not just a style preference — it has real engineering consequences:

| Concern | Consequence of Mixing | Benefit of Splitting |
|---|---|---|
| **Testability** | Can't test FSM transitions independently of arithmetic bugs | FSM and datapath can each be verified in isolation |
| **Reuse** | Control logic tied to a specific word size | Parameterized datapath can be swapped while FSM stays the same |
| **Synthesis** | Tool sees tangled sequential/combinational logic, harder to pipeline | Clean boundary between state registers and logic cones |
| **Readability** | Intent is hidden inside a monolithic always block | FSM transitions tell the algorithm story, datapath tells the data story |

### Signal Taxonomy

This distinction matters enormously in interviews and code reviews:

| Type | Direction | Signals | Meaning |
|---|---|---|---|
| **Control signals** | Control unit → Datapath | `ldAC`, `clrAC`, `ldQR`, `ldBR`, `clrff`, `cin`, `ldCNT`, `ashr`, `decr`, `addsub_inst`, `done` | *"Do this."* |
| **Status signals** | Datapath → Control unit | `q0`, `qn1`, `cntz` | *"Here's the data condition, you decide what's next."* |
| **External input** | User → Top module | `start` | Neither control nor status — an external command from outside the whole module |

The control unit **never touches arithmetic data**. The datapath **never makes algorithmic decisions**. Each block only knows exactly what it needs to know.

---

## 3. Algorithm Walkthrough

Booth's algorithm inspects two bits per cycle:

| `q0` (QR LSB) | `qn1` (bit shifted out last cycle) | Action |
|---|---|---|
| 0 | 0 | No-op (shift only) |
| 1 | 0 | **Subtract** BR from AC (`AC ← AC − BR`) |
| 0 | 1 | **Add** BR to AC (`AC ← AC + BR`) |
| 1 | 1 | No-op (shift only) |

After every add/subtract/no-op decision, the entire concatenated register `{AC, QR, qn1}` is **arithmetically** shifted right by 1. This:
- Moves QR's LSB into `qn1` (ready for next cycle's comparison).
- Preserves AC's sign bit at the MSB (arithmetic, not logical shift).
- Counts down the sequence counter by 1.

After exactly **n** such passes, `{AC, QR}` holds the full 2n-bit signed product.

### Why Arithmetic Shift and Not Logical?

A logical shift inserts `0` at the MSB. If `AC` is negative (possible after a subtract), this silently flips it positive — producing a wrong result. Arithmetic shift re-inserts the sign bit (`AC[n-1]`), preserving correctness across all signed inputs.

---

## 4. Module-by-Module Breakdown

### `Booth_Control_Unit` — The FSM

A 7-state **Moore FSM**. Outputs depend only on the current state, never directly on `q0`, `qn1`, or `cntz` — those influence only which state is entered next.

```
S0 (IDLE) ──start──→ S1 (LOAD)
S1                 → S2 (INIT)
S2 ──{q0,qn1}=01──→ S3 (ADD)
S2 ──{q0,qn1}=10──→ S4 (SUB)
S2 ──else──────────→ S5 (SHIFT)
S3                 → S5
S4                 → S5
S5 ──cntz──────────→ S6 (DONE)
S5 ──{q0,qn1}=01──→ S3
S5 ──{q0,qn1}=10──→ S4
S5 ──else──────────→ S5
S6                 → S6 (holds)
```

**Outputs per state:**

| State | Signals Asserted |
|---|---|
| S0 | (none) — IDLE, nothing should fire |
| S1 | `ldBR`, `ldQR` — latch operands |
| S2 | `clrAC`, `clrff`, `ldCNT` — initialise AC=0, qn1=0, counter=n |
| S3 | `addsub_inst=1`, `cin=0`, `ldAC` — add BR to AC |
| S4 | `addsub_inst=1`, `cin=1`, `ldAC` — subtract BR from AC |
| S5 | `ashr`, `decr` — shift and decrement counter |
| S6 | `done` — signal completion |

### `Booth_Datapath` — The Registers

Holds all state data (`AC`, `BR`, `QR`, `qn1`). The critical lines:

```verilog
if (ashr)
    {AC, QR, qn1} <= {AC[n-1], AC, QR};  // arithmetic right shift, all 3 regs together
```

This is a **single (2n+1)-bit shift**. Doing it as one statement guarantees that QR's outgoing LSB lands in `qn1` on the same clock edge, so the very next cycle's `{q0, qn1}` is already correct.

**`ashred` flag** — a 1-cycle pulse that fires one clock after `ashr`, used to trigger the counter decrement and `partial_product` capture with correct timing.

### `n_bit_adder_subtractor` — Structural, Gate-Level

Add/subtract are unified via XOR trick: for subtraction, XOR each bit of `b` with the control line, then set carry-in to 1. This is equivalent to two's complement negation.

```verilog
xor x1 [n-1:0] (bxor, b, c);              // flip bits of b if c=1 (subtract mode)
and a1 [n-1:0] (band, bxor, {n{addsub_inst}});  // gate: only use the XORed value when addsub_inst=1
buf b1(carry_bus[0], c);                   // carry-in = c (0 for add, 1 for subtract)
full_adder fa [n-1:0] (...);               // structural chain
```

> **Note on `cin` wiring**: In subtract mode (S4), `addsub_inst=1` and `cin=1`. The `cin` connects to both the XOR inputs (flipping `b`) and `carry_bus[0]`. This correctly produces `a + (~b) + 1 = a - b`.

### `sequence_counter` — Down Counter

Loads `n` when `ldCNT` fires (state S2). Decrements on each `decr` pulse (state S5 via `ashred`). When it hits 0, `cntz` goes high, telling the FSM to transition to DONE.

---

## 5. Known Issues & Bugs

### Bug 1 — `initial state = S0` (Not ASIC-portable)

**What's wrong:** Using `initial` to set `state` relies on FPGA flip-flop power-up initialisation. This is a Xilinx Vivado feature, not a Verilog language guarantee. On an ASIC, `initial` blocks in synthesized code are simply ignored — the state register comes up at an undefined value.

**Fix:**
```verilog
// Add a reset input
always @(posedge clk) begin
    if (!reset)
        state <= S0;
    else begin
        // ... case statement
    end
end
```

---

### Bug 2 — S6 Loops Forever (No Way to Restart)

**What's wrong:** `S6: state <= S6;` is a deadlock. Once `done` is asserted, the FSM is stuck there permanently. A second multiplication can never be started without a full hardware reset.

**Fix:**
```verilog
S6: if (!start) state <= S0;   // return to IDLE once start is released
     else       state <= S6;
```

This creates a natural handshake: user sees `done`, releases `start`, FSM returns to IDLE ready for the next operation.

---

### Bug 3 — `sequence_counter` Wired to `ashred` Instead of `decr`

**What's wrong (original code):**
```verilog
sequence_counter #(n) cnt(.ldCNT(ldCNT), .clk(clk), .decr(ashred), .SC(SC));
```
`decr` is the port declared in `sequence_counter`. The control unit drives `decr`. But the datapath feeds `ashred` (the 1-cycle delayed pulse) to that port. This adds a 1-cycle delay to every decrement — the counter runs one cycle behind, causing a potential off-by-one in the number of Booth iterations.

**Fix:** Wire it directly to `decr`:
```verilog
sequence_counter #(n) cnt(.ldCNT(ldCNT), .clk(clk), .decr(decr), .SC(SC));
```

> In practice this delay is compensated by other timing, which is why the simulation still shows a correct result — but it is incorrect by design intent.

---

### Bug 4 — `decr & SC>0` (Bitwise vs. Logical Operator)

**What's wrong:**
```verilog
else if (decr & SC>0)   // bitwise &, not logical &&
```
Due to Verilog operator precedence, `SC>0` evaluates first (a 1-bit boolean), then `decr & (1-bit result)`. It works here by coincidence since both are 1-bit, but `&&` is the correct operator for boolean/conditional logic.

**Fix:**
```verilog
else if (decr && (SC > 0))
```

---

### Bug 5 — `product` Output Valid for Only 1 Cycle

**What's wrong:** The current implementation:
```verilog
assign product = {2*n{done}} & {AC, QR};
```
`done` is a Moore FSM output — it is only HIGH while the FSM is in S6. The moment the FSM transitions back to S0 (after the Bug 2 fix), `done` goes LOW and the product reverts to `0`. Any downstream logic that isn't reading the product in that exact cycle will miss it.

**Fix — register the product:**
```verilog
reg signed [2*n-1:0] product_reg;
reg product_valid;

always @(posedge clk) begin
    if (done) begin
        product_reg  <= {AC, QR};
        product_valid <= 1'b1;
    end
    else if (start)
        product_valid <= 1'b0;   // invalidate at start of new computation
end

assign product = product_reg;
```

A **register** captures `{AC, QR}` once at the clock edge when `done` is first asserted and holds it indefinitely — correct. A **latch** (level-sensitive) would continuously pass `{AC, QR}` through while `done` is HIGH — wrong, because the data changes.

---

### Bug 6 — `done` Asserted Even When No Operation Has Run

**What's wrong:** `done` is a combinational output of the FSM: it is HIGH in state S6. But if the design reuses the product register without invalidation (before Bug 5 fix), the stale product from a previous run remains visible and `done` could mislead downstream logic.

**Fix:** Already covered by the `product_valid` register in the Bug 5 fix — a downstream consumer checks `product_valid`, not just `done`.

---

## 6. Will It Synthesize?

**Yes — with two caveats.**

### Synthesizable As-Is (FPGA/Vivado)

The current code targets Xilinx Vivado targeting the Basys-3 Artix-7 (`XC7A35T`). All constructs used are synthesizable on this platform:

| Construct | Synthesizable on FPGA? | Notes |
|---|---|---|
| `reg ashred = 0;` (init value) | ✅ Yes | FPGA FFs support power-up init |
| `initial state = S0;` | ✅ Yes | Vivado honours this in synthesis |
| Gate-level primitives (`xor`, `and`, `or`, `buf`) | ✅ Yes | Tool maps these to LUTs, re-optimises |
| Parameterized array instances (`fa [n-1:0]`) | ✅ Yes | Vivado unrolls these |
| Combinational `always @(*)` with blocking `=` | ✅ Yes | Correct pattern, as explained below |

### Not Portable to ASIC

| Construct | ASIC Status | Fix |
|---|---|---|
| `initial state = S0;` | ❌ Ignored | Use explicit active-low reset |
| `reg ashred = 0;` | ❌ Ignored | Use reset to initialise |

### On the Blocking `=` in the Output Block

The control unit's output logic uses:
```verilog
always @(*) begin
    {ldAC, ...} = 11'b0;   // default all to 0
    case (state)
        // selective overrides using =
    end
end
```
This is **correct**. The default-then-override pattern depends on sequential in-order execution, which only blocking `=` guarantees inside a combinational block. Using non-blocking `<=` here would be wrong — `<=` schedules updates at end-of-time-step, so the default and the override would race.

---

## 7. Resource Estimate

For `n = 8`:

| Register | Width | Flip-Flops |
|---|---|---|
| `state` (FSM) | 3 bits | 3 |
| `AC` | 8 bits | 8 |
| `BR` | 8 bits | 8 |
| `QR` | 8 bits | 8 |
| `qn1` | 1 bit | 1 |
| `ashred` (pulse flag) | 1 bit | 1 |
| `SC` (sequence counter) | 8 bits | 8 |
| `partial_product` | 8 bits | 8 |
| **Subtotal** | | **~45 FFs** |
| `product_reg` (recommended fix) | 16 bits | 16 |
| `product_valid` (recommended fix) | 1 bit | 1 |
| **Total with fixes** | | **~62 FFs** |

**Combinational:**
- FSM output decode: 7-state, 11-signal decode → ~a handful of LUTs
- Adder-subtractor: 8 full adders in structural chain → ~8–16 LUTs depending on tool optimisation

**Bottom line:** This comfortably fits inside a tiny slice of the Basys-3's Artix-7 (`XC7A35T` has ~33,280 logic cells). Resource utilisation would be well under 1% of available LUTs.

---

## 8. Future Work & How to Do It

### 8.1 Explicit Synchronous Reset

**What to do:** Add `input wire reset` to both `Booth_Multiplier` and `Booth_Control_Unit`. Replace `initial state = S0` with `if (!reset) state <= S0` inside the sequential block. Add similar reset paths for `ashred`, `partial_product`.

**Why it matters:** Required for ASIC portability and for proper FPGA operation in multi-run scenarios.

---

### 8.2 Registered Product Output with Valid Flag

**What to do:** As described in Bug 5, replace the combinational `assign product = {2*n{done}} & {AC,QR}` with a registered capture that fires once when `done` goes HIGH, then holds.

**How:**
```verilog
// In Booth_Datapath or Booth_Multiplier top level:
always @(posedge clk) begin
    if (!reset)      product_valid <= 0;
    else if (done)   { product_reg, product_valid } <= { {AC, QR}, 1'b1 };
    else if (start)  product_valid <= 0;
end
```

---

### 8.3 Radix-4 (Modified) Booth Encoding

**What to do:** Instead of examining 1 bit pair per cycle, examine 3-bit overlapping windows (`{q1, q0, qn1}`). This halves the number of partial products from `n` to `n/2`.

**How it works:** Each 3-bit window encodes one of `{0, +1, -1, +2, -2}`. The `+2`/`-2` case is handled by a 1-bit left shift of the multiplicand (no multiplier needed). This effectively doubles throughput without increasing clock frequency.

**Implementation path:**
1. Modify control unit to decode 3-bit windows.
2. Add a `shift_BR_left1` path in the datapath.
3. Halve the counter initial load to `n/2`.

---

### 8.4 Pipelining the Adder-Subtractor

**What to do:** The critical path is `AC → n_bit_adder_subtractor → AC2 → ldAC`. For large `n`, the ripple-carry adder gets slow. Options:

| Approach | Complexity | Gain |
|---|---|---|
| **Carry-lookahead adder (CLA)** | Medium | Reduces adder depth from O(n) to O(log n) |
| **Carry-select adder** | Medium | Precomputes two results (add/subtract), muxes the correct one |
| **Replace with Xilinx DSP48E1** | Low (IP reuse) | Uses dedicated DSP slice — fast, free on Basys-3 |

For an n=8 target on FPGA, the Xilinx `CARRY4` chain (used automatically by Vivado for `+`/`-` operators) is already fast — this only matters for n ≥ 32 where the ripple delay becomes the critical path.

---

### 8.5 AXI-Stream or Handshake Interface

**What to do:** Replace the bare `start`/`done` protocol with a standard valid/ready handshake (or AXI-Stream). This makes the multiplier compatible with any SoC-style interconnect.

**How:**
```verilog
// Input side
input  wire        s_valid,
output wire        s_ready,
// Output side
output wire        m_valid,
input  wire        m_ready
```

Map `s_valid && s_ready` to the current `start` condition; `m_valid` to `done`; `m_ready` to downstream acknowledgement before returning to IDLE.

---

### 8.6 Self-Checking Testbench with Coverage

**What to do:** The current testbench tests a single case (`15 × −14`). A proper testbench should:
1. Loop over all `2^(2n)` input combinations (feasible for small `n`).
2. Compute expected product in the testbench using `$signed(a) * $signed(b)`.
3. Compare with DUT output and assert on mismatch.

```verilog
integer a, b;
for (a = -(2**(n-1)); a < 2**(n-1); a = a + 1) begin
    for (b = -(2**(n-1)); b < 2**(n-1); b = b + 1) begin
        // drive inputs, wait done, compare
        expected = $signed(a[n-1:0]) * $signed(b[n-1:0]);
        if (product !== expected) $display("FAIL: %0d × %0d = %0d, expected %0d", a, b, $signed(product), expected);
    end
end
```

---

## 9. Optimizations

### 9.1 State Encoding — Binary vs. One-Hot

The current implementation uses binary encoding (`3'b000`–`3'b110`). An alternative is one-hot encoding (1 FF per state, `7'b0000001`–`7'b1000000`).

| Encoding | FFs Used | Decoder Logic | Best For |
|---|---|---|---|
| Binary (current) | 3 | Requires decoder LUTs | ASIC, small state count |
| One-hot | 7 | Near-zero (each state bit is its own enable) | FPGA (LUT-abundant), speed-critical |

The repo includes `Booth_Multiplier_onehot.v` as a companion experiment. On FPGAs, one-hot is often preferred because the FPGA's LUT structure handles single-bit enables efficiently.

### 9.2 Remove `partial_product` Port if Not Used Externally

`partial_product` is an intermediate snapshot of `AC` after each shift — useful for debugging but adds an 8-bit port and an extra registered assignment. If the design is used as a black-box IP, this port can be removed to reduce interface clutter.

### 9.3 Eliminate `ashred` with Careful Port Rewiring

`ashred` exists because `decr` (the counter's enable) needs to fire one cycle after `ashr` to give the shift time to propagate. If the counter is changed to decrement on `ashr` directly (by moving the decrement to the same clock edge using a registered counter with a 1-cycle shift flag in the counter itself), `ashred` becomes redundant and saves 1 FF + logic.

### 9.4 Power: Clock Gating

For power-sensitive applications, gate the clock to the datapath registers when the FSM is in S0 (IDLE). This prevents the registers from switching even when nothing useful is happening. On Xilinx, this is done with the `BUFGCE` primitive or the tool's clock enable inference.

---

## 10. Design Reasoning Cheatsheet

| Question | Answer |
|---|---|
| **What does it compute?** | Signed 2n-bit product of two n-bit two's-complement numbers using Booth's algorithm |
| **Why Booth?** | Handles signed operands natively; reduces operations by encoding bit-runs as shifts |
| **Moore or Mealy?** | Moore — output block depends only on `state`, never directly on `q0`/`qn1`/`cntz` |
| **Why arithmetic shift?** | AC can be negative after subtract; logical shift would corrupt the sign bit |
| **Cycle count?** | Variable: n+3 (best, all no-ops) to 2n+3 (worst, every bit pair triggers add/subtract) |
| **Why single combined shift?** | `{AC,QR,qn1} <= {AC[n-1],AC,QR}` — QR's outgoing LSB lands in `qn1` on same edge |
| **Why blocking `=` in output block?** | Default-then-override pattern requires in-order execution; `<=` would race |
| **Why no `else` on data registers?** | Sequential block holds value naturally — hold is correct for data regs |
| **Why `else` on `ashred`?** | It must be a 1-cycle pulse; without `else`, it stays HIGH and counter runs continuously |
| **Synthesizable?** | Yes on Vivado/FPGA; portable to ASIC after adding explicit reset |
| **Resource usage (n=8)?** | ~45–62 FFs, small LUT footprint, well under 1% of Basys-3 Artix-7 capacity |

