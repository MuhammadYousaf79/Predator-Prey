# Real-Time Digital Simulator – Generator 1 on FPGA (Vivado HLS)

Hardware-in-the-loop co-simulation of **generator 1 of the Kundur 4-machine,
11-bus system** (`TA_Simulation.m`). The generator's differential equations are
solved on a Nexys A7-100T FPGA every **1 ms** in **Q8.24 fixed point**; the CPU
solves the rest of the system and the two exchange data over **UART at
2 000 000 baud**.

```
 ┌──────────────────────── CPU (pc_side.py) ─────────────────────┐
 │ network / other machines  →  V, θ of generator bus            │
 └───────────────┬─────────────────────────────────▲─────────────┘
       STEP: 0x5A V θ  (9 B)        OUT: 0xC3 X(k+1) Pg Qg (45 B)
       INIT: 0xA5 X0 Vref Pref      │
                 │   UART 2 Mbaud   │
 ┌───────────────▼──────────────────┴─── FPGA (rtds_gen_top) ────┐
 │ uart_rx → frame parser → state regs ──► gen_step (HLS core) ──┐│
 │ 1 ms tick ─► step sequencer ── ap_start / ap_done (done_o) ◄──┘│
 │ uart_tx ◄── result frame sequencer ◄── X(k+1), Pg, Qg          │
 └────────────────────────────────────────────────────────────────┘
```

---

## 1. Features

| Feature | Details |
|---|---|
| Generator model | Two-axis machine + exciter + governor + PSS — 9 states: δ, ω, Eq′, Ed′, Efd, Pm, x7, x8, x9 (identical to `daefun` in `TA_Simulation.m`) |
| Integration | Forward Euler, h = 1 ms, one step per 1 ms hardware tick |
| Number format | Q8.24 (signed 32-bit, 8 integer / 24 fraction bits) on every port, state and UART word |
| Pipelining | HLS function pipeline, **II = 1**, depth 67 → result 0.66 µs after `ap_start` |
| Done signal | HLS `ap_done` → `step_done` pulse internally, stretched to 1 µs on PMOD **JA1** (`done_o`) |
| Communication | UART 8N1, 2 000 000 baud, framed packets with header bytes and timeout re-sync |
| Inputs from CPU | Initial state + Vref, Pref (once); bus V and θ (every step) |
| Outputs to CPU | X(k+1) (9 states) + Pg, Qg every step |
| Step modes | Lock-step (default) or hard real-time free-run (`FREE_RUN = 1`) |
| Status LEDs | LD0 initialised · LD1 toggles per step · LD2 UART frame error · LD3 1 ms deadline missed |
| Timing | Place & route at 100 MHz on xc7a100tcsg324-1: **WNS +1.623 ns, WHS +0.025 ns**, 0 failing endpoints |
| Resources | 8.3 k LUT (13 %), 9.2 k FF (7 %), 108 DSP (45 %), 0 BRAM |
| Verification | C-sim vs. double reference, C/RTL co-sim, full-system RTL sim over the UART pins |

---

## 2. Folder layout

```
HLS/
├── TA_Simulation.m          Original MATLAB model (reference)
├── README.md                This file
├── hls/                     Vivado HLS (C++) part
│   ├── gen_params.h         Machine-1 parameters + h-scaled coefficients
│   ├── gen_step.h           Fixed-point types and top-function prototype
│   ├── gen_step.cpp         The pipelined generator core (HLS top: gen_step)
│   ├── gen_step_tb.cpp      C testbench + golden-file generator
│   └── run_hls.tcl          csim → csynth → cosim script
├── rtl/                     Hand-written SystemVerilog around the HLS core
│   ├── rtds_gen_top.sv      Top level: tick, parser, sequencer, TX framing
│   ├── uart_rx.sv           UART receiver
│   └── uart_tx.sv           UART transmitter
├── tb/
│   ├── rtds_gen_top_tb.sv   System testbench (plays the CPU over UART)
│   └── run_sim.bat          xsim compile + run
├── constr/
│   └── nexys_a7.xdc         Pins and clock for Nexys A7-100T
├── vivado/
│   └── build.tcl            Non-project synth → impl → timing check → bitstream
└── script/
    └── pc_side.py           CPU side of the co-simulation (Python)
```

Generated folders (ignored by git): `hls/gen_step_prj/`, `tb/work/`, `vivado/out/`.

---

## 3. How to run

Tools: **Vivado / Vivado HLS 2018.2** (`C:\Xilinx\Vivado\2018.2`), Python 3 with
`pyserial`, `numpy`, `matplotlib`. Open a terminal where Vivado is on the path
(`C:\Xilinx\Vivado\2018.2\settings64.bat`).

### Step 1 – HLS: C simulation, synthesis, co-simulation
```bat
cd HLS\hls
set PATH=%SystemRoot%\system32;%SystemRoot%
call C:\Xilinx\Vivado\2018.2\settings64.bat
vivado_hls -f run_hls.tcl
```
Expected output: `*** TEST PASSED ***` (csim), `Final II = 1, Depth = 67`,
`C/RTL co-simulation finished: PASS`.
The Verilog of the core is written to `hls/gen_step_prj/solution1/syn/verilog/`
and the golden file `gen_step_golden.hex` to `.../csim/build/`.

Run only some steps with the `HLS_STEPS` environment variable:
```bat
set HLS_STEPS=csim csynth
vivado_hls -f run_hls.tcl
```
> Note: `open_solution -reset` clears previous results, so a csim-only run
> deletes the synthesised RTL. Run the full script before steps 2 and 3.

### Step 2 – RTL system simulation (optional but recommended)
```bat
HLS\tb\run_sim.bat
```
Expected output:
```
step 0: delta=0.752301 omega=1.000000 Pg=6.999355 Qg=2.947713
...
*** RTL TEST PASSED (4 steps) ***
done_o pulses: 4
```

### Step 3 – Vivado implementation and bitstream
```bat
cd HLS\vivado
vivado -mode batch -source build.tcl
```
Prints worst setup / hold slack and **stops with an error if either is
negative**. Outputs in `vivado/out/`: `rtds_gen_top.bit`,
`timing_summary.rpt`, `utilization.rpt`, `drc.rpt`, checkpoints.

### Step 4 – Run on the board
1. Program `vivado/out/rtds_gen_top.bit` with Hardware Manager.
2. Edit `PORT` in `script/pc_side.py` (e.g. `COM4`).
3. `python script/pc_side.py`, type `s` + Enter.
4. LD0 lights after INIT, LD1 glows while stepping, LD2/LD3 must stay off.
   A scope on JA1 shows one `done_o` pulse per step.

> Tip: the FTDI USB-UART has a 16 ms latency timer by default. Set it to 1 ms
> (Device Manager → Ports → USB Serial Port → Advanced) to speed up the PC
> round-trip.

---

## 4. UART protocol

8N1, 2 000 000 baud, every word is **signed Q8.24, big-endian (MSB first)**.
Value ↔ word: `word = round(value · 2^24)`, `value = word / 2^24`.

| Direction | Frame | Bytes | Content |
|---|---|---|---|
| CPU → FPGA | **INIT** | 1 + 44 | `0xA5`, δ, ω, Eq′, Ed′, Efd, Pm, x7, x8, x9, Vref, Pref |
| CPU → FPGA | **STEP** | 1 + 8 | `0x5A`, V, θ (terminal bus magnitude [pu], angle [rad]) |
| FPGA → CPU | **OUT** | 1 + 44 | `0xC3`, δ, ω, Eq′, Ed′, Efd, Pm, x7, x8, x9 (= X(k+1)), Pg, Qg (at step k) |

- INIT may be sent again at any time to restart the simulation.
- A frame that stalls for 20 byte-times mid-way is dropped and the parser waits
  for the next header byte.
- OUT takes 225 µs on the wire, well inside the 1 ms step.

### Step timing
- **Lock-step (`FREE_RUN = 0`, default):** a step runs on the next 1 ms tick
  after a complete STEP frame. The CPU sends STEP, waits for OUT, computes, and
  sends the next STEP — the FPGA can never run ahead of a slow CPU (same
  scheme as the predator-prey design).
- **Free-run (`FREE_RUN = 1`):** a step runs on *every* tick, using the last
  received V, θ if no new STEP arrived. This is hard real-time; the CPU must
  keep up.

If a tick arrives while the previous result is still being transmitted or
computed, LD3 (deadline miss) latches on.

---

## 5. The generator model

For machine 1 (from `daefun`):

```
Vd = V sin(δ − θ)                 Vq = V cos(δ − θ)
Id = (Ed′−Vd)·Rs/den + (Eq′−Vq)·xq′/den
Iq = (Eq′−Vq)·Rs/den − (Ed′−Vd)·xd′/den        den = Rs² + xd′·xq′
Pg = Vd·Id + Vq·Iq      Qg = Vq·Id − Vd·Iq      Pe = Pg + Rs·(Id² + Iq²)

f1 = ws(ω − 1)
f2 = (Pm − Pe − Kd(ω − 1)) / 2H
f3 = (−Eq′ − (xd − xd′)Id + Efd) / Tdo′
f4 = (−Ed′ + (xq − xq′)Iq) / Tqo′
f5 = (−Efd + KA(Vref − V − x9)) / TA
f6 = (−Pm + Ksg(Pref + (1 − ω)/R)) / Tsg
f7 = (−x7 − Kstab·TW·f2) / TW
f8 = (−x8 + x7 + T1·f7) / T2
f9 = (−x9 + x8 + T3·f8) / T4

X(k+1) = X(k) + h·f(X(k), V(k), θ(k))
```

Simplifications versus the MATLAB file:
- `sqrt` is not needed: `Rs·Ig²` is computed directly as `Rs·(Id² + Iq²)`.
- The forced-oscillation term in f6 is omitted (`FO_mag = 0` in the script).
- Initial state: `X_equilibrium(1:9)` from `Equilibrium_Values.mat`,
  `Vref = V + Efd/KA`, `Pref = Pm/Ksg` (what `fsolve` produces at equilibrium).

---

## 6. File-by-file implementation

### `hls/gen_params.h`
All machine-1 data from `Load_Kundur_System` (MVA base 100, machine values
scaled by 100/900) as `double` constants, plus the **derived coefficients**
the hardware uses. Every coefficient is pre-multiplied by h:

| Coefficient | Value | Used in |
|---|---|---|
| `C_H_WS` = h·ws | 0.377 | Δδ |
| `C_H_2H` = h/2H | 8.55e-6 | Δω |
| `C_H_TDO`, `C_H_TQO` | 1.25e-4, 2.5e-3 | ΔEq′, ΔEd′ |
| `C_H_TA`, `C_H_KA_TA` | 0.1, 20 | ΔEfd |
| `C_H_TSG`, `C_H_KSG`, `C_H_KSG_R` | 0.001, 0.01, 0.2 | ΔPm |
| `C_H_TW`, `C_H_T2`, `C_T1_T2`, `C_H_T4`, `C_T3_T4` | … | PSS |

Folding h in keeps the large constants (ws = 377, KA = 200, Ksg/R = 200) out of
the Q8.24 range limit of ±128. To change a machine parameter, edit the base
value here — the derived coefficients update automatically.

### `hls/gen_step.h`
Fixed-point types:

| Type | Format | Purpose |
|---|---|---|
| `q8_24_t` | `ap_fixed<32,8>` | Ports, states, UART words |
| `q8_24_rnd_t` | `ap_fixed<32,8,AP_RND,AP_SAT>` | Final rounding/saturation into Q8.24 |
| `alg_t` | `ap_fixed<36,8>` | Algebraic signals (Vd, Vq, Id, Iq, Pg, …) with 4 guard bits |
| `wide_t` | `ap_fixed<48,12>` | State increments h·f and Id²+Iq² (≈ 52 at rated load) |
| `kc_t` | `ap_fixed<32,6>` | Coefficients with \|c\| < 32 |
| `ks_t` | `ap_ufixed<32,-10>` | Very small coefficients (< 2⁻¹⁰), 42 fraction bits |
| `cordic_t` | `ap_fixed<32,3>` | Sine/cosine datapath |

Why wider internal types: increments such as h/2H·(Pm − Pe) are far below one
Q8.24 LSB per step if truncated early. Computing them with guard bits and
**rounding only once** when added to the state keeps the error within ½ LSB
per step and avoids the drift that truncation causes.

### `hls/gen_step.cpp`
The HLS top function `gen_step`:
- **Interface:** `ap_ctrl_hs` (ap_start / ap_done / ap_idle / ap_ready), inputs
  `ap_none`, outputs `ap_vld`. Stateless — X(k) comes in, X(k+1) goes out —
  so it pipelines at **II = 1** with no loop-carried dependency. The states are
  held in registers in `rtds_gen_top.sv`.
- **`sincos_cordic()`:** range reduction `r = φ − 2π·round(φ/2π)` to [−π, π],
  fold into [−π/2, π/2] (negating the result), then a 26-iteration
  rotation-mode CORDIC, fully unrolled and pipelined. No `hls_math` dependency.
- **Datapath:** stator equations → Pg, Qg, Pe → the nine h-scaled increments
  (PSS stages reuse Δω and Δx7, Δx8, since h·f7 depends on h·f2 etc.) →
  `X + Δ` rounded/saturated to Q8.24.
- HLS result: 66-cycle latency, estimated 7.0 ns at an 8 ns target.

### `hls/gen_step_tb.cpp`
- `ref_step()`: double-precision Euler step written literally from `daefun`
  (not from the folded coefficients — so it also checks `gen_params.h`).
- Scenario: 6 s, steady state, then V dips to 0.9·V for 100 ms at t = 1 s.
- **One-step check:** HW step vs. double step from the *same* quantised state,
  tolerance 64 LSB (actual ≤ 3 LSB).
- **Trajectory check:** free-running HW vs. free-running double model,
  tolerance 1e-3.
- Writes `gen_step_tb.csv` (for plotting) and `gen_step_golden.hex`
  (INIT words + 4 steps of inputs/expected outputs) for the RTL testbench.
- Returns non-zero on failure, so csim and cosim report FAIL.

### `hls/run_hls.tcl`
Creates `gen_step_prj`, part `xc7a100tcsg324-1`, clock **8 ns with 1 ns
uncertainty** (margin for 100 MHz on the board), runs csim, csynth and
cosim (xsim, Verilog). IP-catalog export is deliberately skipped: Vivado HLS
2018.x fails it after 2021 because of a date-based version overflow; the raw
Verilog is used directly instead.

### `rtl/uart_rx.sv`
8N1 receiver, `CLKS_PER_BIT = CLK_FREQ / BAUD_RATE = 50`. Two-flop
synchroniser on the RX pin, start bit re-checked at half a bit (glitch
rejection), data bits sampled at their centre, LSB first. After sampling the
stop bit at its centre it returns to IDLE immediately so back-to-back bytes are
never missed. Outputs a 1-cycle `rx_valid` or `frame_error` strobe.

### `rtl/uart_tx.sv`
8N1 transmitter. On `start` (when `ready`) it loads a 10-bit frame
`{stop, data, start}` and shifts one bit every 50 clocks. `ready` is low
while a byte is on the line.

### `rtl/rtds_gen_top.sv`
Top level, parameters `CLK_FREQ`, `BAUD_RATE`, `FREE_RUN`.

1. **Reset synchroniser** – `rst_n` (CPU_RESETN) → active-high `reset`,
   asynchronous assert, synchronous release. Only control flops are reset;
   data registers have no reset, which keeps the reset net small (this raised
   WNS from +0.17 ns to +1.62 ns).
2. **1 ms tick** – counter of `CLK_FREQ/1000` cycles.
3. **Frame parser** – FSM `P_HDR → P_INIT / P_STEP`; assembles big-endian words
   into `init_buf[11]` or `v_buf`/`th_buf`, then raises `init_pending` or
   `step_pending`. A 20-byte-time inter-byte timeout returns to `P_HDR`.
4. **HLS core instance** `gen_step` – inputs are the state registers `x_reg[9]`,
   `vref_reg`, `pref_reg` and the per-step snapshot `v_core`, `th_core`, all
   stable while the core computes. Each output is captured into `out_lat` on
   its own `ap_vld`.
5. **Step sequencer** – `M_IDLE → M_RUN → M_WAIT → M_COMMIT`:
   - `M_IDLE`: apply a pending INIT; on a tick with a step request, snapshot
     V, θ and go on (or flag a deadline miss if the TX is still busy).
   - `M_RUN`: hold `ap_start` until `ap_ready`.
   - `M_WAIT`: wait for `ap_done`.
   - `M_COMMIT`: `x_reg ← X(k+1)`, pulse `step_done`.
6. **Result transmitter** – on `step_done` loads the 11 output words into a
   352-bit shift register and sends `0xC3` + 44 bytes through `uart_tx`.
7. **Status** – LEDs, and `done_o` = `step_done` stretched to 100 cycles.

### `tb/rtds_gen_top_tb.sv` and `tb/run_sim.bat`
The testbench acts as the CPU on the real UART pins (500 ns per bit): sends
INIT and 4 STEP frames from `gen_step_golden.hex`, receives each 45-byte OUT
frame and compares it **bit-exactly** with the C model. Also checks that the
results are 1 ms apart, that `done_o` pulses once per step and that the
error LEDs stay off. `run_sim.bat` compiles the HLS Verilog, the RTL and the
testbench with `xvlog`/`xelab` and runs `xsim` in `tb/work/`.

### `constr/nexys_a7.xdc`
100 MHz clock on E3, CPU_RESETN (C12), USB-UART RX (C4) / TX (D4),
LD0–LD3, `done_o` on JA1 (C17). UART, reset, LED and `done_o` pins are
false-pathed (asynchronous / not timing critical).

### `vivado/build.tcl`
Non-project flow: reads the HLS Verilog, RTL and XDC, runs `synth_design`,
`opt_design`, `place_design`, `phys_opt_design`, `route_design`, writes
reports, prints WNS/WHS, **errors out if either is negative**, then writes the
bitstream.

### `script/pc_side.py`
- Opens the COM port at 2 Mbaud, sends INIT (equilibrium state, Vref, Pref).
- Per step: `network_solve()` gives V, θ → STEP frame → reads the OUT frame
  (re-syncing on `0xC3`) → logs it.
- Runs `ref_step()` (float model of the same equations) alongside and prints
  the max |FPGA − float| error per output.
- Saves `gen1_fpga.csv` and plots δ, ω, Efd and Pg.

`network_solve()` is the placeholder for the CPU side of the co-simulation.
By default it holds the generator bus at its power-flow value (V = 1.03,
θ = 0) with a 100 ms dip to 0.9·V at t = 1 s. Replace it with the network
solution and the other three machines; it receives the latest FPGA output
(δ, Eq′, Ed′, Pg, Qg, …) and must return V, θ for the next step.

---

## 7. Verification summary

| Check | Result |
|---|---|
| C simulation, one-step error | ≤ ½ LSB on all states except Efd (≤ 3 LSB) |
| C simulation, 6 s trajectory | max error 7.7e-4 (Efd), others ≤ 9e-5 |
| C/RTL co-simulation | PASS |
| RTL system simulation | PASS, bit-exact, 1 ms period |
| Python reference at equilibrium | Pg = 6.9996, Qg = 1.8493 (= power-flow PG(1), QG(1)) |
| Place & route @ 100 MHz | WNS +1.623 ns, WHS +0.025 ns, all constraints met |

---

## 8. Known limitations

- **Explicit Euler, h = 1 ms** — same method as the predator-prey design;
  it is less accurate than MATLAB's `ode15s`, compare against an Euler
  reference (as the testbenches do).
- **ω resolution** — one Q8.24 LSB is 6e-8. A 0.01 pu power mismatch moves ω
  by only ~1.4 LSB per step, so very small oscillations are coarsely
  quantised. Widening the ω state (e.g. extra fraction bits internally) would
  fix this if needed.
- **Only generator 1** is on the FPGA; the CPU side currently uses a fixed
  terminal bus, not the full network.
- **PC round-trip** over USB is usually slower than 1 ms in lock-step mode
  (see the FTDI latency tip above).
- **DRC warnings** about DSP input/output pipelining (DPIP/DPOP) are
  advisory only; timing is met.
