"""
pc_side.py - CPU side of the generator-1 co-simulation (rtds_gen_top).

Protocol (all words signed Q8.24, big-endian):
  PC -> FPGA  INIT : 0xA5 + delta omega Eq' Ed' Efd Pm x7 x8 x9 Vref Pref
  PC -> FPGA  STEP : 0x5A + V theta
  FPGA -> PC  OUT  : 0xC3 + delta omega Eq' Ed' Efd Pm x7 x8 x9 Pg Qg

The FPGA integrates generator 1 (h = 1 ms) on every 1 ms tick once a STEP
frame has arrived and replies with X(k+1) plus Pg, Qg at step k.

`network_solve()` is where the CPU side of the co-simulation goes: it gets the
generator output of the previous step and returns the terminal-bus V, theta
for the next step. The default is the test scenario of the HLS testbench
(generator bus held at its power-flow value with a 100 ms voltage dip at 1 s),
and a float reference of the same Euler model runs alongside for comparison.
"""
import struct
import time

import numpy as np
import serial
import matplotlib.pyplot as plt

# --- Configuration -----------------------------------------------------------
PORT        = 'COM4'
BAUD        = 2_000_000
TOTAL_STEPS = 10000
H           = 0.001
Q24         = 2 ** 24

HDR_INIT, HDR_STEP, HDR_OUT = 0xA5, 0x5A, 0xC3
OUT_NAMES = ['delta', 'omega', "Eq'", "Ed'", 'Efd', 'Pm', 'x7', 'x8', 'x9',
             'Pg', 'Qg']

# --- Machine 1 data (TA_Simulation.m, Load_Kundur_System) --------------------
S = 100 / 900
P = dict(ws=2 * np.pi * 60, H=6.5 * 9, Kd=2.0,
         xd=1.8 * S, xq=1.7 * S, xdp=0.3 * S, xqp=0.55 * S, Rs=0.0025 * S,
         Tdo=8.0, Tqo=0.4, KA=200.0, TA=0.01, Ksg=10.0, Tsg=1.0, R=0.05,
         Kstab=3.5, TW=10.0, T1=0.02, T2=0.05, T3=6.0, T4=5.4)

# Equilibrium of machine 1 (Equilibrium_Values.mat) and its terminal bus
X0 = np.array([0.75230068, 1.0, 0.95154547, 0.47723241, 1.94397421,
               7.01337039, 0.0, 0.0, 0.0])
V_SS, THETA_SS = 1.03, 0.0
VREF = V_SS + X0[4] / P['KA']
PREF = X0[5] / P['Ksg']


def to_q(x):
    q = int(round(x * Q24))
    return max(-2**31, min(2**31 - 1, q))


def from_q(q):
    return q / Q24


def ref_step(x, v, th):
    """Float forward-Euler step of the same model (daefun, machine 1)."""
    p = P
    vd, vq = v * np.sin(x[0] - th), v * np.cos(x[0] - th)
    den = p['Rs'] ** 2 + p['xdp'] * p['xqp']
    i_d = (x[3] - vd) * p['Rs'] / den + (x[2] - vq) * p['xqp'] / den
    i_q = (x[2] - vq) * p['Rs'] / den - (x[3] - vd) * p['xdp'] / den
    pg, qg = vd * i_d + vq * i_q, vq * i_d - vd * i_q
    pe = pg + p['Rs'] * (i_d ** 2 + i_q ** 2)
    f = np.zeros(9)
    f[0] = p['ws'] * (x[1] - 1)
    f[1] = (x[5] - pe - p['Kd'] * (x[1] - 1)) / (2 * p['H'])
    f[2] = (-x[2] - (p['xd'] - p['xdp']) * i_d + x[4]) / p['Tdo']
    f[3] = (-x[3] + (p['xq'] - p['xqp']) * i_q) / p['Tqo']
    f[4] = (-x[4] + p['KA'] * (VREF - v - x[8])) / p['TA']
    f[5] = (-x[5] + p['Ksg'] * (PREF + (1 - x[1]) / p['R'])) / p['Tsg']
    f[6] = (-x[6] - p['Kstab'] * p['TW'] * f[1]) / p['TW']
    f[7] = (-x[7] + x[6] + p['T1'] * f[6]) / p['T2']
    f[8] = (-x[8] + x[7] + p['T3'] * f[7]) / p['T4']
    return x + H * f, pg, qg


def network_solve(step, gen_out):
    """CPU side of the co-simulation: return (V, theta) of the generator bus.

    gen_out = latest FPGA output (dict of OUT_NAMES) or None on the 1st step.
    Replace this with the network / other-machine solution.
    """
    t = step * H
    v = 0.9 * V_SS if 1.0 <= t < 1.1 else V_SS
    return v, THETA_SS


def read_frame(ser):
    """Read one 45-byte result frame, re-synchronising on the header byte."""
    while True:
        b = ser.read(1)
        if len(b) == 0:
            return None
        if b[0] == HDR_OUT:
            break
    payload = ser.read(44)
    if len(payload) < 44:
        return None
    words = struct.unpack('>11i', payload)
    return {n: from_q(w) for n, w in zip(OUT_NAMES, words)}


def main():
    ser = serial.Serial(PORT, BAUD, timeout=0.1)
    time.sleep(1.0)
    print(f"Connected to {PORT} at {BAUD} baud. Press 's' + Enter to start.")
    while input('>> ').strip().lower() != 's':
        pass
    ser.reset_input_buffer()
    ser.reset_output_buffer()

    # INIT frame: state + set-points
    init = list(X0) + [VREF, PREF]
    ser.write(bytes([HDR_INIT]) + struct.pack('>11i', *[to_q(x) for x in init]))
    ser.flush()
    time.sleep(0.01)

    hw_log, ref_log = [], []
    x_ref = X0.copy()
    gen_out = None
    t0 = time.time()
    try:
        for k in range(TOTAL_STEPS):
            v, th = network_solve(k, gen_out)
            ser.write(bytes([HDR_STEP]) + struct.pack('>2i', to_q(v), to_q(th)))
            ser.flush()

            gen_out = read_frame(ser)
            if gen_out is None:
                print(f"[ERROR] timeout / sync lost at step {k}")
                break

            x_ref, pg_r, qg_r = ref_step(x_ref, v, th)
            hw_log.append([gen_out[n] for n in OUT_NAMES])
            ref_log.append(list(x_ref) + [pg_r, qg_r])

            if k % 500 == 0:
                print(f"step {k:5d} | delta {gen_out['delta']:9.6f} "
                      f"| omega {gen_out['omega']:9.6f} | Pg {gen_out['Pg']:8.4f} "
                      f"| Qg {gen_out['Qg']:8.4f}")
    except KeyboardInterrupt:
        print('Aborted by user.')
    finally:
        ser.close()
        dt = time.time() - t0
        print(f"{len(hw_log)} steps in {dt:.2f} s "
              f"({1000 * dt / max(len(hw_log), 1):.2f} ms per step round trip)")

    if not hw_log:
        return
    hw, ref = np.array(hw_log), np.array(ref_log)
    t = np.arange(1, len(hw) + 1) * H
    np.savetxt('gen1_fpga.csv', np.column_stack([t, hw]), delimiter=',',
               header='t,' + ','.join(OUT_NAMES), comments='')
    print('Max |FPGA - float| per output:')
    for i, n in enumerate(OUT_NAMES):
        print(f"  {n:6s} {np.max(np.abs(hw[:, i] - ref[:, i])):.3e}")

    fig, ax = plt.subplots(2, 2, figsize=(12, 7), sharex=True)
    for a, i in zip(ax.flat, [0, 1, 4, 9]):
        a.plot(t, ref[:, i], label='float reference', lw=2, alpha=0.6)
        a.plot(t, hw[:, i], '--', label='FPGA (Q8.24)')
        a.set_title(OUT_NAMES[i])
        a.grid(True)
        a.legend()
    for a in ax[1]:
        a.set_xlabel('Time (s)')
    plt.tight_layout()
    plt.show()


if __name__ == '__main__':
    main()
