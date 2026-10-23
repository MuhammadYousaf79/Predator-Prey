"""
pc_side.py - CPU side of the Kundur-system co-simulation.

  FPGA : generator 3 (bus 3) - 9 states, Q8.24, h = 1 ms   (rtds_gen_top)
  CPU  : generators 1, 2, 4 + the 11-bus network + loads    (kundur.py)

Every 1 ms step k:
  1. CPU  : Newton solve of the network with ALL machine states X(k)
            (generator 3's delta, Eq', Ed' come from the FPGA)  ->  V, theta
  2. CPU  -> FPGA  STEP : V3(k), theta3(k)
  3. FPGA : X3(k+1) = X3(k) + h f(X3(k), V3(k), theta3(k))
     CPU  : X(k+1)  = X(k)  + h f(X(k), V(k), theta(k))    for machines 1, 2, 4
  4. FPGA -> CPU   OUT  : X3(k+1), Pg3(k), Qg3(k)
     (CPU checks Pg3/Qg3 against its own network solution)

This is the same explicit-Euler DAE solution as one monolithic program, which
runs alongside as the reference ("float reference") for comparison.

Protocol (all words signed Q8.24, big-endian):
  PC -> FPGA  INIT : 0xA5 + delta omega Eq' Ed' Efd Pm x7 x8 x9 Vref Pref
  PC -> FPGA  STEP : 0x5A + V theta
  FPGA -> PC  OUT  : 0xC3 + delta omega Eq' Ed' Efd Pm x7 x8 x9 Pg Qg

Backends for generator 3 (--backend):
  uart  : the real FPGA over the serial port            (default)
  emu   : bit-accurate HLS C++ model (gen_step_emu.dll, see build_emu.bat)
  float : Python double model (checks the co-simulation split itself)

Examples:
  python pc_side.py                       # board on COM4
  python pc_side.py --port COM7 --steps 20000
  python pc_side.py --backend emu         # no board needed
"""
import argparse
import ctypes
import os
import struct
import time

import numpy as np
import matplotlib.pyplot as plt

import kundur

# --- Configuration -----------------------------------------------------------
FPGA_GEN = 3                 # machine on the FPGA = GEN_ID in gen_params.h
BAUD = 2_000_000
Q24 = 2 ** 24
H = kundur.H_STEP

HDR_INIT, HDR_STEP, HDR_OUT = 0xA5, 0x5A, 0xC3
OUT_NAMES = kundur.STATE_NAMES + ['Pg', 'Qg']

# Disturbances applied on the CPU side (bus numbers 1..11, powers in pu/100 MVA)
#   load  : extra P/Q load between t_on and t_off
#   fault : shunt fault impedance Rf + jXf between t_on and t_off
DISTURBANCES = [
    dict(type='load', bus=7, dP=2.0, dQ=0.0, t_on=1.0, t_off=1.1),
    # dict(type='fault', bus=8, Rf=0.0, Xf=0.05, t_on=1.0, t_off=1.05),
]


def to_q(x):
    q = int(round(float(x) * Q24))
    return max(-2 ** 31, min(2 ** 31 - 1, q))


# =============================================================================
# Generator-3 backends: init(x0, vref, pref) and step(V, theta) -> (x(k+1), Pg, Qg)
# =============================================================================
class UartGen:
    """The real FPGA (rtds_gen_top) over the USB-UART."""

    def __init__(self, port):
        import serial
        self.ser = serial.Serial(port, BAUD, timeout=0.1)
        time.sleep(1.0)
        self.ser.reset_input_buffer()
        self.ser.reset_output_buffer()

    def init(self, x0, vref, pref):
        words = [to_q(v) for v in list(x0) + [vref, pref]]
        self.ser.write(bytes([HDR_INIT]) + struct.pack('>11i', *words))
        self.ser.flush()
        time.sleep(0.01)

    def step(self, v, th):
        self.ser.write(bytes([HDR_STEP]) + struct.pack('>2i', to_q(v), to_q(th)))
        self.ser.flush()
        while True:                                   # re-sync on header
            b = self.ser.read(1)
            if len(b) == 0:
                raise TimeoutError('no reply from FPGA')
            if b[0] == HDR_OUT:
                break
        payload = self.ser.read(44)
        if len(payload) < 44:
            raise TimeoutError('short frame from FPGA')
        w = np.array(struct.unpack('>11i', payload)) / Q24
        return w[:9], w[9], w[10]

    def close(self):
        self.ser.close()


class EmuGen:
    """Bit-accurate HLS model; holds the state as raw Q8.24 like the FPGA."""

    def __init__(self):
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'gen_step_emu.dll')
        self.dll = ctypes.CDLL(path)
        if self.dll.gen_step_id() != FPGA_GEN:
            raise RuntimeError(f'gen_step_emu.dll built for machine '
                               f'{self.dll.gen_step_id()}, expected {FPGA_GEN}')
        self.inp = (ctypes.c_int32 * 13)()
        self.out = (ctypes.c_int32 * 11)()

    def init(self, x0, vref, pref):
        self.inp[2], self.inp[3] = to_q(vref), to_q(pref)
        for i in range(9):
            self.inp[4 + i] = to_q(x0[i])

    def step(self, v, th):
        self.inp[0], self.inp[1] = to_q(v), to_q(th)
        self.dll.gen_step_raw(self.inp, self.out)
        for i in range(9):
            self.inp[4 + i] = self.out[i]                 # state register
        w = np.array(self.out[:]) / Q24
        return w[:9], w[9], w[10]

    def close(self):
        pass


class FloatGen:
    """Python double model of generator 3 (same equations as kundur.py)."""

    def __init__(self, system):
        self.sys = system
        self.m = np.array([FPGA_GEN - 1])

    def init(self, x0, vref, pref):
        self.x = np.array(x0, dtype=float)[None, :]

    def step(self, v, th):
        V, T = np.array([v]), np.array([th])
        s = self.sys.stator(self.x, V, T, self.m)
        self.x = self.sys.euler(self.x, V, T, self.m)
        return self.x[0].copy(), s['pg'][0], s['qg'][0]

    def close(self):
        pass


# =============================================================================
def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--backend', choices=['uart', 'emu', 'float'], default='uart')
    ap.add_argument('--port', default='COM4')
    ap.add_argument('--steps', type=int, default=10000, help='number of 1 ms steps')
    ap.add_argument('--no-ref', action='store_true', help='skip the float reference')
    ap.add_argument('--no-plot', action='store_true')
    args = ap.parse_args()

    sysm = kundur.Kundur(disturbances=DISTURBANCES)
    g = FPGA_GEN - 1
    cpu_m = np.array([m for m in range(kundur.NMACH) if m != g])
    nb = kundur.NBUS

    if args.backend == 'uart':
        gen = UartGen(args.port)
        print(f'Connected to {args.port} at {BAUD} baud.')
        print("Press 's' + Enter to start.")
        while input('>> ').strip().lower() != 's':
            pass
    elif args.backend == 'emu':
        gen = EmuGen()
    else:
        gen = FloatGen(sysm)

    # ---- initial conditions: equilibrium of the full system ----------------
    X = sysm.X_eq.copy()                                 # (4, 9) all machines
    gen.init(X[g], sysm.Vref[g], sysm.Pref[g])
    if args.backend in ('uart', 'emu'):                  # FPGA starts from Q8.24
        X[g] = np.round(X[g] * Q24) / Q24
    y = sysm.Y_eq.copy()

    Xr, yr = sysm.X_eq.copy(), sysm.Y_eq.copy()          # monolithic reference
    all_m = np.arange(kundur.NMACH)

    log = dict(t=[], w=[], d=[], efd=[], pm=[], p78=[], v=[],
               pg3_fpga=[], pg3_cpu=[], qg3_fpga=[], qg3_cpu=[], nit=[], tstep=[],
               w_ref=[], d_ref=[], p78_ref=[], v_ref=[])

    print(f'Co-simulation: machine {FPGA_GEN} on {args.backend.upper()}, '
          f'machines {[m + 1 for m in cpu_m]} + network on CPU, {args.steps} steps')
    t_start = time.perf_counter()
    try:
        for k in range(args.steps):
            t = k * H
            t0 = time.perf_counter()

            # 1. network at step k with all machine states X(k)
            y, nit, res = sysm.solve_network(y, X, t)
            V, th = y[:nb], y[nb:]
            if res > 1e-6:
                print(f'[WARN] t={t:.3f}s network not converged (|g|={res:.1e})')

            # 2-4. FPGA steps generator 3 while the CPU steps the others
            x3n, pg3, qg3 = gen.step(V[g], th[g])
            s3 = sysm.stator(X[[g]], V[[g]], th[[g]], np.array([g]))
            X[cpu_m] = sysm.euler(X[cpu_m], V[cpu_m], th[cpu_m], cpu_m)
            X[g] = x3n
            log['tstep'].append(time.perf_counter() - t0)

            # monolithic float reference
            if not args.no_ref:
                yr, _, _ = sysm.solve_network(yr, Xr, t)
                log['w_ref'].append(Xr[:, 1].copy())
                log['d_ref'].append(Xr[:, 0].copy())
                log['p78_ref'].append(sysm.line_flow(yr, 7, 8))
                log['v_ref'].append(yr[:nb].copy())
                Xr = sysm.euler(Xr, yr[:kundur.NMACH], yr[nb:nb + kundur.NMACH], all_m)

            log['t'].append(t)
            log['nit'].append(nit)
            log['pg3_fpga'].append(pg3)
            log['qg3_fpga'].append(qg3)
            log['pg3_cpu'].append(s3['pg'][0])
            log['qg3_cpu'].append(s3['qg'][0])
            log['p78'].append(sysm.line_flow(y, 7, 8))
            log['v'].append(V.copy())
            # states at step k+1 are logged against t+h below via w/d arrays
            log['w'].append(X[:, 1].copy())
            log['d'].append(X[:, 0].copy())
            log['efd'].append(X[:, 4].copy())
            log['pm'].append(X[:, 5].copy())

            if k % 1000 == 0:
                print(f't={t:6.3f}s | w = {np.array2string(X[:, 1], precision=6)} '
                      f'| P7-8 = {log["p78"][-1]:7.2f} MW | Pg3 = {pg3:7.4f} '
                      f'| Newton it {nit}')
    except (KeyboardInterrupt, TimeoutError) as e:
        print(f'Stopped: {e!r}')
    finally:
        gen.close()

    n = len(log['t'])
    if n == 0:
        return
    wall = time.perf_counter() - t_start
    print(f'\n{n} steps ({n * H:.2f} s simulated) in {wall:.2f} s wall clock, '
          f'{1000 * np.mean(log["tstep"]):.3f} ms per co-simulation step')

    L = {k: np.array(v) for k, v in log.items() if len(v)}
    t = L['t']
    tx = t + H                                            # time of X(k+1)
    pg_err = np.max(np.abs(L['pg3_fpga'] - L['pg3_cpu']))
    qg_err = np.max(np.abs(L['qg3_fpga'] - L['qg3_cpu']))
    print(f'Interface check  max|Pg3 FPGA - CPU| = {pg_err:.2e}   '
          f'max|Qg3 FPGA - CPU| = {qg_err:.2e}')
    if 'w_ref' in L:
        # reference arrays hold X(k); shift co-sim (X(k+1)) by one step to align
        print('Max |co-sim - float reference|:')
        for i in range(kundur.NMACH):
            dw = np.max(np.abs(L['w'][:-1, i] - L['w_ref'][1:, i]))
            dd = np.max(np.abs(L['d'][:-1, i] - L['d_ref'][1:, i]))
            tag = ' (FPGA)' if i == g else ''
            print(f'  G{i + 1}{tag:7s} omega {dw:.2e}   delta {dd:.2e} rad')
        print(f'  P7-8 tie line  {np.max(np.abs(L["p78"] - L["p78_ref"])):.3f} MW')

    hdr = (['t'] + [f'w{i + 1}' for i in range(4)] + [f'delta{i + 1}' for i in range(4)]
           + ['P78_MW', 'Pg3_fpga', 'Qg3_fpga', 'Pg3_cpu', 'Qg3_cpu']
           + [f'V{i + 1}' for i in range(nb)])
    out = np.column_stack([tx, L['w'], L['d'], L['p78'], L['pg3_fpga'], L['qg3_fpga'],
                           L['pg3_cpu'], L['qg3_cpu'], L['v']])
    csv = f'cosim_{args.backend}.csv'
    np.savetxt(csv, out, delimiter=',', header=','.join(hdr), comments='')
    print(f'Saved {csv}')

    if args.no_plot:
        return
    fig, ax = plt.subplots(2, 2, figsize=(13, 8), sharex=True)
    for i in range(4):
        lbl = f'G{i + 1}' + (' (FPGA)' if i == g else '')
        ax[0, 0].plot(tx, L['w'][:, i], label=lbl)
    if 'w_ref' in L:
        ax[0, 0].plot(t, L['w_ref'][:, g], 'k--', lw=1, label=f'G{g + 1} float ref')
    ax[0, 0].set_title('Rotor speed (pu)')
    for i in range(4):
        ax[0, 1].plot(tx, L['d'][:, i] - L['d'][:, 0], label=f'd{i + 1} - d1')
    ax[0, 1].set_title('Rotor angle relative to G1 (rad)')
    ax[1, 0].plot(t, L['p78'], label='co-simulation')
    if 'p78_ref' in L:
        ax[1, 0].plot(t, L['p78_ref'], 'k--', lw=1, label='float reference')
    ax[1, 0].set_title('Tie-line flow 7 -> 8 (MW)')
    ax[1, 1].plot(t, L['pg3_fpga'] * 100, label='Pg3 from FPGA')
    ax[1, 1].plot(t, L['pg3_cpu'] * 100, '--', label='Pg3 from CPU network')
    ax[1, 1].set_title('Generator 3 electrical power (MW)')
    for a in ax.flat:
        a.grid(True)
        a.legend(fontsize=8)
    for a in ax[1]:
        a.set_xlabel('Time (s)')
    fig.suptitle(f'Kundur co-simulation - G{FPGA_GEN} on {args.backend.upper()}')
    plt.tight_layout()
    plt.show()


if __name__ == '__main__':
    main()
