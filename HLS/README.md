# Real-Time Digital Simulator – Kundur System Co-Simulation (FPGA + CPU)

Hardware-in-the-loop co-simulation of the **Kundur 4-machine, 11-bus system**
(`TA_Simulation.m`):

- **FPGA (Nexys A7-100T):** generator 3 on bus 3. Its 9 differential equations
  are solved every **1 ms** in **Q8.24 fixed point** by a pipelined Vivado HLS
  core.
- **CPU (Python):** generators 1, 2 and 4, the loads and the 11-bus network.
- **Link:** both sides exchange their coupling values every 1 ms over **UART at
  2 000 000 baud**.

```
 ┌─────────────────────────── CPU (pc_side.py + kundur.py) ───────────────────────────┐
 │  G1, G2, G4 (Euler)    11-bus network + loads (Newton)    disturbances, plots      │
 │        ▲                         │ V3, θ3                    ▲ δ3, Eq′3, Ed′3, …   │
 └────────┼─────────────────────────┼───────────────────────────┼─────────────────────┘
          │            STEP: 0x5A V3 θ3 (9 B)     OUT: 0xC3 X3(k+1) Pg3 Qg3 (45 B)
          │            INIT: 0xA5 X3(0) Vref Pref │
          │                         │  UART 2 Mbaud             │
 ┌────────┼─────────────────────────▼───────────────────────────┴─ FPGA (rtds_gen_top) ┐
 │  uart_rx → frame parser → state regs ──► gen_step (HLS core, G3) ──┐                │
 │  1 ms tick ─► step sequencer ── ap_start / ap_done (done_o) ◄──────┘                │
 │  uart_tx ◄── result frame sequencer ◄── X3(k+1), Pg3, Qg3                           │
 └────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 1. Features

| Feature | Details |
|---|---|
| System | Kundur 2-area system: 4 machines, 11 buses, constant-power loads at buses 7 and 9 (`Power_Flow_Solution.mat`) |
| Split | G3 on the FPGA; G1, G2, G4 + network + loads on the CPU |
| Generator model | Two-axis machine + exciter + governor + PSS — 9 states: δ, ω, Eq′, Ed′, Efd, Pm, x7, x8, x9 (identical to `daefun`) |
| Network | Algebraic equations g = PG − PL − P(V,θ), QG − QL − Q(V,θ) = 0, Newton–Raphson with analytic Jacobian (2–3 iterations per step) |
| Integration | Forward Euler, h = 1 ms, one step per 1 ms hardware tick |
| Number format | Q8.24 (signed 32-bit, 8 integer / 24 fraction bits) on every FPGA port, state and UART word |
| Pipelining | HLS function pipeline, **II = 1**, depth 68 → result 0.67 µs after `ap_start` |
| Done signal | HLS `ap_done` → `step_done` pulse internally, stretched to 1 µs on PMOD **JA1** (`done_o`) |
| Communication | UART 8N1, 2 000 000 baud, framed packets with header bytes and timeout re-sync |
| Exchanged every 1 ms | CPU → FPGA: V3, θ3 · FPGA → CPU: δ3, ω3, Eq′3, Ed′3, Efd3, Pm3, x7–x9, Pg3, Qg3 |
| Interface check | The CPU recomputes Pg3/Qg3 from its own network solution and compares them with the FPGA's every step |
| Disturbances | Load pulses/steps and shunt faults on any bus (`DISTURBANCES` in `pc_side.py`) |
| Backends for G3 | `uart` (the board), `emu` (bit-accurate HLS C++ model as a DLL), `float` (Python double) |
| Reference | A monolithic all-float simulation runs alongside and is compared with the co-simulation |
| Step modes | Lock-step (default) or hard real-time free-run (`FREE_RUN = 1`) |
| Status LEDs | LD0 initialised · LD1 toggles per step · LD2 UART frame error · LD3 1 ms deadline missed |
| Timing | Place & route at 100 MHz on xc7a100tcsg324-1: **WNS +1.001 ns, WHS +0.016 ns**, 0 failing endpoints |
| Resources | 8.4 k (13 %) LUT, 9.4 k (7 %) FF, 112 (47 %) DSP, 0 BRAM |

---

## 2. Folder layout

```
HLS/
├── TA_Simulation.m          Original MATLAB model (reference)
├── README.md                This file
├── hls/                     Vivado HLS (C++) part – the FPGA generator
│   ├── gen_params.h         Machine parameters (GEN_ID selects the machine) + h-scaled coefficients
│   ├── gen_step.h           Fixed-point types and top-function prototype
│   ├── gen_step.cpp         The pipelined generator core (HLS top: gen_step)
│   ├── gen_step_tb.cpp      C testbench + golden-file generator
│   ├── gen_step_emu.cpp     C wrapper to build the core as a PC DLL (emulator)
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
└── script/                  CPU side
    ├── pc_side.py           Co-simulation driver (UART / emu / float backends)
    ├── kundur.py            Kundur system: machines, loads, Newton network solver
    ├── build_emu.bat        Builds gen_step_emu.dll from the HLS C++
    └── data/
        ├── Power_Flow_Solution.mat   Y-bus, V, θ, PL, QL of the power flow
        └── Equilibrium_Values.mat    X_equilibrium of all 4 machines
```

Generated (ignored by git): `hls/gen_step_prj/`, `tb/work/`, `vivado/out/`,
`script/gen_step_emu.dll`, `script/cosim_*.csv`.

---

## 3. How to run

Tools: **Vivado / Vivado HLS 2018.2** (`C:\Xilinx\Vivado\2018.2`), Python 3 with
`pyserial`, `numpy`, `scipy`, `matplotlib`.

### Step 1 – HLS: C simulation, synthesis, co-simulation
```bat
cd HLS\hls
set PATH=%SystemRoot%\system32;%SystemRoot%
call C:\Xilinx\Vivado\2018.2\settings64.bat
vivado_hls -f run_hls.tcl
```
Expected output: `Machine 3 (bus 3)`, `*** TEST PASSED ***`,
`Final II = 1, Depth = 68`, `C/RTL co-simulation finished: PASS`.
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
Expected output ends with `*** RTL TEST PASSED (4 steps) ***` and
`done_o pulses: 4`.

### Step 3 – Vivado implementation and bitstream
```bat
cd HLS\vivado
vivado -mode batch -source build.tcl
```
Prints worst setup / hold slack and **stops with an error if either is
negative**. Outputs in `vivado/out/`: `rtds_gen_top.bit`,
`timing_summary.rpt`, `utilization.rpt`, `drc.rpt`, checkpoints.

### Step 4 – Co-simulation without the board (recommended first)
```bat
cd HLS\script
build_emu.bat
python pc_side.py --backend emu
```
`build_emu.bat` compiles the *same* HLS C++ (`gen_step.cpp`) with Vivado's
bundled g++ into `gen_step_emu.dll`. The run is therefore bit-identical to what
the FPGA computes, minus the UART. `--backend float` uses a Python double model
of G3 instead; that run must match the float reference exactly, which checks
the co-simulation split itself.

### Step 5 – Co-simulation with the board
1. Program `vivado/out/rtds_gen_top.bit` with Hardware Manager.
2. `cd HLS\script` → `python pc_side.py --port COM4` (your port), type `s` + Enter.
3. LD0 lights after INIT, LD1 glows while stepping, LD2/LD3 must stay off.
   A scope on JA1 shows one `done_o` pulse per step.

Options: `--steps N` (default 10000 = 10 s), `--no-ref` (skip the float
reference, faster), `--no-plot`.

Output: console summary (interface check, max error vs. reference),
`cosim_<backend>.csv` (t, ω1–4, δ1–4, P7→8, Pg3/Qg3 from FPGA and CPU, V1–11),
and a plot of rotor speeds, relative angles, the tie-line flow 7→8 and Pg3.

> Tip: the FTDI USB-UART has a 16 ms latency timer by default. Set it to 1 ms
> (Device Manager → Ports → USB Serial Port → Advanced) to speed up the PC
> round-trip.

---

## 4. Co-simulation algorithm

Each 1 ms step k:

```
CPU  1. Newton solve of g(X(k), Y(k)) = 0 for Y(k) = [V1..V11, θ1..θ11]
        using all four machines' states; G3's δ3, Eq′3, Ed′3 come from the FPGA
CPU  2. send STEP: V3(k), θ3(k)                                   ─► FPGA
FPGA 3. X3(k+1) = X3(k) + h·f(X3(k), V3(k), θ3(k))   (on the next 1 ms tick)
CPU     X(k+1)  = X(k)  + h·f(X(k), V(k), θ(k))      for G1, G2, G4 (in parallel)
FPGA 4. send OUT: X3(k+1), Pg3(k), Qg3(k)                         ─► CPU
CPU     check Pg3, Qg3 against its own network solution
```

Because the network is solved with the stator equations of **all** machines
(G3's included, from its states), the split introduces **no extra delay or
approximation**: it is exactly the same explicit-Euler DAE solution as a
single program. `--backend float` confirms this (difference 0).

The FPGA side does not need any network knowledge — it only ever sees its own
terminal voltage — so moving another machine onto the FPGA only means changing
`GEN_ID` (hardware) and `FPGA_GEN` (Python).

### Disturbances
Edit `DISTURBANCES` in `pc_side.py` (bus numbers 1–11, powers in pu on
100 MVA):
```python
DISTURBANCES = [
    dict(type='load', bus=7, dP=2.0, dQ=0.0, t_on=1.0, t_off=1.1),     # 200 MW pulse
    # dict(type='fault', bus=8, Rf=0.0, Xf=0.05, t_on=1.0, t_off=1.05),  # 50 ms fault
]
```
Prefer pulses over permanent steps: a permanent load change leaves a frequency
offset, so all rotor angles drift and δ3 would eventually leave the Q8.24 range
(±128 rad).

---

## 5. UART protocol

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
- STEP + OUT take 45 µs + 225 µs on the wire, well inside the 1 ms step.

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

## 6. The model

### Machines (FPGA for G3, CPU for G1, G2, G4)
From `daefun`:
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

### Network (CPU)
```
P_i = Σ_j V_i V_j |Y_ij| cos(θ_i − θ_j − ∠Y_ij)
Q_i = Σ_j V_i V_j |Y_ij| sin(θ_i − θ_j − ∠Y_ij)
g   = [PG − PL − P ; QG − QL − Q] = 0          (22 equations, 22 unknowns)
PG, QG = Pg, Qg of machines 1–4 at buses 1–4, 0 elsewhere
PL = PL_ss·(P + I·V/V_ss + Z·(V/V_ss)²)       (ZIP, constant P at buses 7, 9)
```

Simplifications versus the MATLAB file:
- `sqrt` is not needed: `Rs·Ig²` is computed directly as `Rs·(Id² + Iq²)`.
- Forced-oscillation and noise injections are omitted (`FO_mag`, `Noise` = 0
  in the script); `DISTURBANCES` replaces them.
- Initial state: `X_equilibrium` from `Equilibrium_Values.mat`,
  `Vref = V + Efd/KA`, `Pref = Pm/Ksg` (the `fsolve` equilibrium).
- Like `daefun`, the tiny PG/QG residues of the power flow at the load buses
  are ignored, so the network settles 1e-3 away from the power-flow values in
  the first step.

### Parameters (must match on both sides)
| Where | Used for |
|---|---|
| `hls/gen_params.h` (`P_…` base values, `GEN_ID`) | The FPGA machine (and the C testbench / emulator DLL) |
| `script/kundur.py` → `PARAMS` | The CPU machines and the float reference |

The current values are `Kd = 2.0·900/100 = 18` and `Kstab = 3.5` on all machines.
After changing `gen_params.h`, rerun steps 1–3 (and `build_emu.bat`).

---

## 7. File-by-file implementation

### `hls/gen_params.h`
All data from `Load_Kundur_System` (MVA base 100, machine values scaled by
100/900) as `double` constants, plus the **derived coefficients** the hardware
uses. `GEN_ID` (default 3) selects which machine is built; only H differs
(6.5 for G1/G2, 6.175 for G3/G4). Every coefficient is pre-multiplied by h:

| Coefficient | Value (G3) | Used in |
|---|---|---|
| `C_H_WS` = h·ws | 0.377 | Δδ |
| `C_H_2H` = h/2H | 9.0e-6 | Δω |
| `C_KD` = Kd | 18 | Δω |
| `C_H_TDO`, `C_H_TQO` | 1.25e-4, 2.5e-3 | ΔEq′, ΔEd′ |
| `C_H_TA`, `C_H_KA_TA` | 0.1, 20 | ΔEfd |
| `C_H_TSG`, `C_H_KSG`, `C_H_KSG_R` | 0.001, 0.01, 0.2 | ΔPm |
| `C_H_TW`, `C_H_T2`, `C_T1_T2`, `C_H_T4`, `C_T3_T4` | … | PSS |

Folding h in keeps the large constants (ws = 377, KA = 200, Ksg/R = 200) out of
the Q8.24 range limit of ±128.

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

Increments such as h/2H·(Pm − Pe) are far below one Q8.24 LSB per step if
truncated early. Computing them with guard bits and **rounding only once**
when added to the state keeps the error within ½ LSB per step.

> Range limits: a parameter change that pushes a `kc_t` coefficient beyond
> ±32 (e.g. Kd > 32, KA > 320) or a `ks_t` coefficient beyond 9.7e-4 wraps
> silently — the C simulation then fails its error check.

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

### `hls/gen_step_tb.cpp`
- Equilibrium table of all four machines; `GEN_ID` picks the one under test.
- `ref_step()`: double-precision Euler step written literally from `daefun`
  (not from the folded coefficients — so it also checks `gen_params.h`).
- Scenario: 6 s with the terminal bus fixed at its power-flow value, V dips to
  0.9·V for 100 ms at t = 1 s.
- **One-step check:** HW step vs. double step from the *same* quantised state,
  tolerance 64 LSB (actual ≤ 3 LSB).
- **Trajectory check:** free-running HW vs. free-running double model,
  tolerance 1e-3.
- Writes `gen_step_tb.csv` and `gen_step_golden.hex` (INIT words + 4 steps of
  inputs/expected outputs) for the RTL testbench. Returns non-zero on failure.

### `hls/gen_step_emu.cpp`
`extern "C" gen_step_raw(int32 in[13], int32 out[11])` around `gen_step`,
using raw Q8.24 words exactly as on the UART, plus `gen_step_id()` returning
`GEN_ID`, so `pc_side.py` refuses a DLL built for another machine.

### `hls/run_hls.tcl`
Creates `gen_step_prj`, part `xc7a100tcsg324-1`, clock **8 ns with 1 ns
uncertainty** (margin for 100 MHz on the board), runs csim, csynth and cosim.
IP-catalog export is skipped: Vivado HLS 2018.x fails it after 2021 because of
a date-based version overflow; the raw Verilog is used directly.

### `rtl/uart_rx.sv`
8N1 receiver, `CLKS_PER_BIT = CLK_FREQ / BAUD_RATE = 50`. Two-flop
synchroniser, start bit re-checked at half a bit (glitch rejection), data bits
sampled at their centre, LSB first. Returns to IDLE right after the centre of
the stop bit so back-to-back bytes are never missed.

### `rtl/uart_tx.sv`
8N1 transmitter. On `start` (when `ready`) it loads `{stop, data, start}` and
shifts one bit every 50 clocks.

### `rtl/rtds_gen_top.sv`
Top level, parameters `CLK_FREQ`, `BAUD_RATE`, `FREE_RUN`.
1. **Reset synchroniser** – `rst_n` → active-high `reset`. Only control flops
   are reset; data registers have no reset (keeps the reset net small for
   timing).
2. **1 ms tick** – counter of `CLK_FREQ/1000` cycles.
3. **Frame parser** – FSM `P_HDR → P_INIT / P_STEP`; assembles big-endian words
   into `init_buf[11]` or `v_buf`/`th_buf`, raises `init_pending` /
   `step_pending`. 20-byte-time inter-byte timeout returns to `P_HDR`.
4. **HLS core** `gen_step` – fed from `x_reg[9]`, `vref_reg`, `pref_reg` and the
   per-step snapshot `v_core`, `th_core`, all stable while it computes. Each
   output is captured into `out_lat` on its own `ap_vld`.
5. **Step sequencer** – `M_IDLE → M_RUN → M_WAIT → M_COMMIT`: apply INIT /
   start on tick, hold `ap_start` until `ap_ready`, wait for `ap_done`, then
   `x_reg ← X(k+1)` and pulse `step_done`.
6. **Result transmitter** – sends `0xC3` + the 11 words (44 bytes).
7. **Status** – LEDs, and `done_o` = `step_done` stretched to 100 cycles.

### `tb/rtds_gen_top_tb.sv` and `tb/run_sim.bat`
Acts as the CPU on the real UART pins: sends INIT and 4 STEP frames from
`gen_step_golden.hex`, checks every 45-byte OUT frame **bit-exactly** against
the C model, the 1 ms spacing, one `done_o` pulse per step and the error LEDs.

### `constr/nexys_a7.xdc`
100 MHz clock (E3), CPU_RESETN (C12), USB-UART RX (C4) / TX (D4), LD0–LD3,
`done_o` on JA1 (C17). Asynchronous I/O is false-pathed.

### `vivado/build.tcl`
Non-project flow: HLS Verilog + RTL + XDC → synth → opt → place → phys_opt →
route → reports → **error if WNS or WHS < 0** → bitstream.

### `script/kundur.py`
`Kundur` class:
- Loads `data/Power_Flow_Solution.mat` (Y-bus, V, θ, PL, QL) and
  `data/Equilibrium_Values.mat` (X_equilibrium), computes Vref, Pref.
- `stator()`, `euler()`: vectorised machine equations for any subset of
  machines (same formulas as the FPGA).
- `loads()`: ZIP loads + load disturbances, with dPL/dV for the Jacobian.
- `ybus()`: Y-bus with active shunt faults.
- `solve_network()`: Newton–Raphson on the 22 algebraic equations. The
  Jacobian is analytic: network part from the MATPOWER `dSbus_dV` formulas,
  plus each generator's ∂(Pg, Qg)/∂(V, θ) from its stator equations.
- `line_flow()`: MW flow between two buses (e.g. tie line 7→8).

### `script/pc_side.py`
- `UartGen`, `EmuGen`, `FloatGen`: three interchangeable G3 backends with
  `init()` / `step(V, θ)`. `UartGen` frames the Q8.24 words and re-syncs on
  `0xC3`; `EmuGen` keeps the state as raw Q8.24 words like the FPGA registers.
- Main loop: network solve → G3 step → G1/G2/G4 Euler step → Pg3/Qg3
  interface check → monolithic float reference step → logging.
- Summary: wall-clock time per step, interface error, max |co-sim − reference|
  of ω and δ per machine and of the tie-line flow. Saves `cosim_<backend>.csv`
  and plots.

### `script/build_emu.bat`
Compiles `gen_step.cpp` + `gen_step_emu.cpp` with Vivado's MinGW g++
(statically linked) into `gen_step_emu.dll`.

---

## 8. Verification summary

| Check | Result |
|---|---|
| C simulation G3, one-step error | ≤ ½ LSB on all states except Efd (≤ 3 LSB) |
| C/RTL co-simulation | PASS |
| RTL system simulation | PASS, bit-exact, 1 ms period |
| Newton network solver | converges in 2–4 iterations, analytic Jacobian (quadratic convergence) |
| Co-sim `--backend float` vs. monolithic reference | identical (error 0) |
| Co-sim `--backend emu` (Q8.24 G3) vs. float reference, 20 s, 200 MW load pulse | ω ≤ 7e-6 pu, tie line ≤ 0.47 MW, Pg3 interface ≤ 1.6e-6 |
| Physical plausibility | inter-area mode 0.64 Hz (G1/G2 against G3/G4), tie line 7→8 = 400 MW |
| CPU time per step (Python, with reference) | ≈ 0.4–0.5 ms |
| Place & route @ 100 MHz | WNS +1.001 ns, WHS +0.016 ns, all constraints met |

---

## 9. Known limitations

- **Explicit Euler, h = 1 ms** on both sides — less accurate than MATLAB's
  `ode15s`; compare against the Euler reference (as `pc_side.py` does).
- **ω resolution** — one Q8.24 LSB is 6e-8; very small speed changes are
  coarsely quantised on the FPGA machine.
- **Angle range** — δ3 must stay inside ±128 rad, so avoid long runs with a
  permanent frequency offset (use disturbance pulses).
- **PC round-trip** over USB is usually slower than 1 ms per step in
  lock-step mode (see the FTDI latency tip), so the board run is slower than
  real time; the FPGA itself needs only 0.67 µs per step.
- **DRC warnings** about DSP input/output pipelining (DPIP/DPOP) are
  advisory only; timing is met.
