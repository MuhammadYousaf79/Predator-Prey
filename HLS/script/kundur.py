"""
kundur.py - CPU-side model of the Kundur 4-machine / 11-bus system.

Same equations as daefun() in TA_Simulation.m:
  * machines : two-axis model + exciter + governor + PSS (9 states each)
  * network  : g(X, Y) = [PG - PL - P(V, th) ; QG - QL - Q(V, th)] = 0
               solved by Newton-Raphson for Y = [V(1..11), th(1..11)]
  * time     : forward Euler, h = 1 ms (same as the FPGA)

Machine parameters MUST match HLS/hls/gen_params.h, because the machine that
runs on the FPGA is built from that file.
"""
import os

import numpy as np
import scipy.io as sio

H_STEP = 0.001
NSTATE = 9
NMACH = 4
NBUS = 11
MVA_BASE = 100.0
DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'data')

# --- Machine data (Load_Kundur_System) - keep in sync with gen_params.h ------
S = MVA_BASE / 900.0
PARAMS = dict(
    ws=2 * np.pi * 60,
    H=np.array([6.5, 6.5, 6.175, 6.175]) * 900 / MVA_BASE,
    Kd=np.full(NMACH, 2.0 * 900 / MVA_BASE),   # = P_KD in gen_params.h
    xd=np.full(NMACH, 1.8 * S), xq=np.full(NMACH, 1.7 * S),
    xdp=np.full(NMACH, 0.3 * S), xqp=np.full(NMACH, 0.55 * S),
    Rs=np.full(NMACH, 0.0025 * S),
    Tdo=np.full(NMACH, 8.0), Tqo=np.full(NMACH, 0.4),
    KA=np.full(NMACH, 200.0), TA=np.full(NMACH, 0.01),
    Ksg=np.full(NMACH, 10.0), Tsg=np.full(NMACH, 1.0), R=np.full(NMACH, 0.05),
    Kstab=np.full(NMACH, 3.5), TW=np.full(NMACH, 10.0),
    T1=np.full(NMACH, 0.02), T2=np.full(NMACH, 0.05),
    T3=np.full(NMACH, 6.0), T4=np.full(NMACH, 5.4),
)

STATE_NAMES = ['delta', 'omega', "Eq'", "Ed'", 'Efd', 'Pm', 'x7', 'x8', 'x9']


class Kundur:
    """System data, machine equations and the network solver."""

    def __init__(self, params=PARAMS, data_dir=DATA_DIR, disturbances=()):
        pf = sio.loadmat(os.path.join(data_dir, 'Power_Flow_Solution.mat'))
        eq = sio.loadmat(os.path.join(data_dir, 'Equilibrium_Values.mat'))
        self.p = params
        self.Y = pf['Y'].astype(complex)
        self.V_ss = pf['V'].ravel().astype(float)
        self.th_ss = pf['theta'].ravel().astype(float)
        self.PL_ss = pf['PL'].ravel().astype(float)
        self.QL_ss = pf['QL'].ravel().astype(float)

        # ZIP load model, columns [Z I P] for P and for Q (constant P at 7, 9)
        self.zip_p = np.zeros((NBUS, 3))
        self.zip_q = np.zeros((NBUS, 3))
        self.zip_p[[6, 8], 2] = 1.0
        self.zip_q[[6, 8], 2] = 1.0

        # Equilibrium (fsolve result) and the matching set-points
        self.X_eq = eq['X_equilibrium'].ravel().reshape(NMACH, NSTATE)
        self.Vref = self.V_ss[:NMACH] + self.X_eq[:, 4] / params['KA']
        self.Pref = self.X_eq[:, 5] / params['Ksg']
        self.Y_eq = np.concatenate([self.V_ss, self.th_ss])

        self.disturbances = list(disturbances)

    # ----------------------------------------------------------- machines --
    def stator(self, x, V, th, m):
        """Stator algebraic equations for machines m (index array).

        x : (n, 9) states, V / th : (n,) terminal bus voltage.
        Returns a dict with Vd, Vq, Id, Iq, Pg, Qg, Pe.
        """
        p = self.p
        rs, xdp, xqp = p['Rs'][m], p['xdp'][m], p['xqp'][m]
        phi = x[:, 0] - th
        vd, vq = V * np.sin(phi), V * np.cos(phi)
        den = rs ** 2 + xdp * xqp
        a, b, c = rs / den, xqp / den, xdp / den
        ded, deq = x[:, 3] - vd, x[:, 2] - vq
        i_d = ded * a + deq * b
        i_q = deq * a - ded * c
        pg = vd * i_d + vq * i_q
        qg = vq * i_d - vd * i_q
        pe = pg + rs * (i_d ** 2 + i_q ** 2)
        return dict(vd=vd, vq=vq, id=i_d, iq=i_q, pg=pg, qg=qg, pe=pe,
                    a=a, b=b, c=c)

    def euler(self, x, V, th, m):
        """X(k+1) = X(k) + h f(X(k), V(k), th(k)) for machines m."""
        p = self.p
        s = self.stator(x, V, th, m)
        f = np.zeros_like(x)
        dw = x[:, 1] - 1
        f[:, 0] = p['ws'] * dw
        f[:, 1] = (x[:, 5] - s['pe'] - p['Kd'][m] * dw) / (2 * p['H'][m])
        f[:, 2] = (-x[:, 2] - (p['xd'][m] - p['xdp'][m]) * s['id'] + x[:, 4]) / p['Tdo'][m]
        f[:, 3] = (-x[:, 3] + (p['xq'][m] - p['xqp'][m]) * s['iq']) / p['Tqo'][m]
        f[:, 4] = (-x[:, 4] + p['KA'][m] * (self.Vref[m] - V - x[:, 8])) / p['TA'][m]
        f[:, 5] = (-x[:, 5] + p['Ksg'][m] * (self.Pref[m] - dw / p['R'][m])) / p['Tsg'][m]
        f[:, 6] = (-x[:, 6] - p['Kstab'][m] * p['TW'][m] * f[:, 1]) / p['TW'][m]
        f[:, 7] = (-x[:, 7] + x[:, 6] + p['T1'][m] * f[:, 6]) / p['T2'][m]
        f[:, 8] = (-x[:, 8] + x[:, 7] + p['T3'][m] * f[:, 7]) / p['T4'][m]
        return x + H_STEP * f

    # -------------------------------------------------------------- loads --
    def loads(self, V, t):
        """ZIP loads + active disturbances. Returns PL, QL, dPL/dV, dQL/dV."""
        r = V / self.V_ss
        PL = self.PL_ss * (self.zip_p[:, 2] + self.zip_p[:, 1] * r + self.zip_p[:, 0] * r ** 2)
        QL = self.QL_ss * (self.zip_q[:, 2] + self.zip_q[:, 1] * r + self.zip_q[:, 0] * r ** 2)
        dPL = self.PL_ss * (self.zip_p[:, 1] + 2 * self.zip_p[:, 0] * r) / self.V_ss
        dQL = self.QL_ss * (self.zip_q[:, 1] + 2 * self.zip_q[:, 0] * r) / self.V_ss
        for d in self.disturbances:
            if d['type'] == 'load' and d['t_on'] <= t < d['t_off']:
                PL[d['bus'] - 1] += d.get('dP', 0.0)
                QL[d['bus'] - 1] += d.get('dQ', 0.0)
        return PL, QL, dPL, dQL

    def ybus(self, t):
        """Bus admittance matrix including active shunt faults."""
        Y = self.Y
        for d in self.disturbances:
            if d['type'] == 'fault' and d['t_on'] <= t < d['t_off']:
                Y = Y.copy()
                Y[d['bus'] - 1, d['bus'] - 1] += 1.0 / complex(d.get('Rf', 0.0), d['Xf'])
        return Y

    # ------------------------------------------------------------ network --
    def solve_network(self, y0, xg, t, tol=1e-10, max_iter=20):
        """Newton-Raphson on g(X, Y) = 0.

        y0 : (22,) initial guess [V; th], xg : (4, 9) states of ALL machines
        (only delta, Eq', Ed' are used). Returns (y, iterations, |g|_inf).
        """
        Y = self.ybus(t)
        m = np.arange(NMACH)
        y = y0.copy()
        for it in range(1, max_iter + 1):
            V, th = y[:NBUS], y[NBUS:]
            Vc = V * np.exp(1j * th)
            I = Y @ Vc
            Sb = Vc * np.conj(I)
            PL, QL, dPL, dQL = self.loads(V, t)

            s = self.stator(xg, V[:NMACH], th[:NMACH], m)
            PG = np.zeros(NBUS)
            QG = np.zeros(NBUS)
            PG[:NMACH], QG[:NMACH] = s['pg'], s['qg']
            g = np.concatenate([PG - PL - Sb.real, QG - QL - Sb.imag])
            err = np.max(np.abs(g))
            if err < tol:
                return y, it - 1, err

            # Network Jacobian (MATPOWER dSbus_dV, polar)
            Vn = Vc / V
            dS_dth = 1j * np.diag(Vc) @ np.conj(np.diag(I) - Y @ np.diag(Vc))
            dS_dV = np.diag(Vc) @ np.conj(Y @ np.diag(Vn)) + np.diag(np.conj(I)) @ np.diag(Vn)
            J = -np.block([[dS_dV.real, dS_dth.real], [dS_dV.imag, dS_dth.imag]])
            J[np.arange(NBUS), np.arange(NBUS)] -= dPL
            J[NBUS + np.arange(NBUS), np.arange(NBUS)] -= dQL

            # Generator injections (depend on their own bus V, th only)
            sphi, cphi = np.sin(xg[:, 0] - th[:NMACH]), np.cos(xg[:, 0] - th[:NMACH])
            vd, vq, i_d, i_q = s['vd'], s['vq'], s['id'], s['iq']
            a, b, c = s['a'], s['b'], s['c']
            for dvd, dvq, col in ((sphi, cphi, m),           # d/dV
                                  (-vq, vd, NBUS + m)):      # d/dth
                did = -a * dvd - b * dvq
                diq = -a * dvq + c * dvd
                dpg = dvd * i_d + vd * did + dvq * i_q + vq * diq
                dqg = dvq * i_d + vq * did - dvd * i_q - vd * diq
                J[m, col] += dpg
                J[NBUS + m, col] += dqg

            y = y - np.linalg.solve(J, g)
        return y, max_iter, err

    def line_flow(self, y, i, j):
        """Active power i -> j through the series branch, in MW."""
        V, th = y[:NBUS], y[NBUS:]
        vi, vj = V[i - 1] * np.exp(1j * th[i - 1]), V[j - 1] * np.exp(1j * th[j - 1])
        I = -(vi - vj) * self.Y[i - 1, j - 1]
        return (vi * np.conj(I)).real * MVA_BASE
