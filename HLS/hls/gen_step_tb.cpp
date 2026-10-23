// =============================================================================
// gen_step_tb.cpp - C simulation / C-RTL co-simulation testbench for gen_step
//
// Golden model: double-precision forward Euler of the machine-1 equations,
// written exactly as in daefun() of TA_Simulation.m.
//
// Scenario (terminal bus driven by the "CPU" = this testbench):
//   0  - 1 s  : steady state at the power-flow solution (must stay flat)
//   1 - 1.1 s : terminal voltage dip to 0.9 * V
//   1.1 - 6 s : recovery
//
// Checks
//   1) one-step error : HW step vs double step from the *same* state
//   2) trajectory     : free-running HW vs free-running double model
// Writes gen_step_tb.csv for plotting.
// =============================================================================
#include <cstdio>
#include <cmath>
#include "gen_step.h"
#include "gen_params.h"

// Machine-1 equilibrium from Equilibrium_Values.mat (X_equilibrium(1:9))
static const double X0[GEN_NSTATE] = {
    0.75230068, 1.0, 0.95154547, 0.47723241, 1.94397421,
    7.01337039, 0.0, 0.0, 0.0
};
static const double V_SS     = 1.03;   // V_mag_ss(1)
static const double THETA_SS = 0.0;    // V_angle_ss(1)

static void ref_step(const double *x, double v, double th, double vref,
                     double pref, double *xn, double *pg_o, double *qg_o)
{
    const double ws = P_WS, h = P_H_STEP;
    double vd = v * sin(x[0] - th);
    double vq = v * cos(x[0] - th);
    double den = P_RS * P_RS + P_XD_P * P_XQ_P;
    double id = (x[3] - vd) * (P_RS / den) + (x[2] - vq) * (P_XQ_P / den);
    double iq = (x[2] - vq) * (P_RS / den) + (x[3] - vd) * (-P_XD_P / den);
    double ig = sqrt(id * id + iq * iq);
    double pg = vd * id + vq * iq;
    double qg = vq * id - vd * iq;
    double pe = pg + P_RS * ig * ig;

    double f[GEN_NSTATE];
    f[0] = ws * (x[1] - 1);
    f[1] = 1 / (2 * P_H) * (x[5] - pe - P_KD * (x[1] - 1));
    f[2] = 1 / P_TDO_P * (-x[2] - (P_XD - P_XD_P) * id + x[4]);
    f[3] = 1 / P_TQO_P * (-x[3] + (P_XQ - P_XQ_P) * iq);
    f[4] = 1 / P_TA * (-x[4] + P_KA * (vref - v - x[8]));
    f[5] = 1 / P_TSG * (-x[5] + P_KSG * (pref + 1 / P_R * (1 - x[1])));
    f[6] = 1 / P_TW * (-x[6] - P_KSTAB * P_TW * f[1]);
    f[7] = 1 / P_TSTAB2 * (-x[7] + x[6] + P_TSTAB1 * f[6]);
    f[8] = 1 / P_TSTAB4 * (-x[8] + x[7] + P_TSTAB3 * f[7]);

    for (int i = 0; i < GEN_NSTATE; i++)
        xn[i] = x[i] + h * f[i];
    *pg_o = pg;
    *qg_o = qg;
}

static void hw_step(const q8_24_t *x, q8_24_t v, q8_24_t th, q8_24_t vref,
                    q8_24_t pref, q8_24_t *xn, q8_24_t *pg, q8_24_t *qg)
{
    gen_step(v, th, vref, pref,
             x[0], x[1], x[2], x[3], x[4], x[5], x[6], x[7], x[8],
             &xn[0], &xn[1], &xn[2], &xn[3], &xn[4], &xn[5], &xn[6], &xn[7],
             &xn[8], pg, qg);
}

int main()
{
    const int    N_STEPS  = 6000;
    const double LSB      = 1.0 / (1 << 24);
    const char  *names[GEN_NSTATE] = {"delta", "omega", "Eq'", "Ed'", "Efd",
                                      "Pm", "x7", "x8", "x9"};

    // Set-points exactly as the fsolve initialisation produces them
    double vref = V_SS + X0[4] / P_KA;
    double pref = X0[5] / P_KSG;

    double  xr[GEN_NSTATE], xrn[GEN_NSTATE];
    q8_24_t xh[GEN_NSTATE], xhn[GEN_NSTATE];
    for (int i = 0; i < GEN_NSTATE; i++) {
        xr[i] = X0[i];
        xh[i] = X0[i];
    }

    double one_step_err[GEN_NSTATE + 2] = {0};
    double traj_err[GEN_NSTATE] = {0};
    double pq_err = 0;

    FILE *fp = fopen("gen_step_tb.csv", "w");
    fprintf(fp, "t,delta_hw,delta_ref,omega_hw,omega_ref,eq_hw,eq_ref,"
                "efd_hw,efd_ref,pm_hw,pm_ref,pg_hw,pg_ref,qg_hw,qg_ref\n");

    for (int k = 0; k < N_STEPS; k++) {
        double t  = k * P_H_STEP;
        double v  = (t >= 1.0 && t < 1.1) ? 0.9 * V_SS : V_SS;
        double th = THETA_SS;

        q8_24_t pg_h, qg_h;
        hw_step(xh, v, th, vref, pref, xhn, &pg_h, &qg_h);

        // (1) one-step error from the identical (quantised) HW state
        double xq[GEN_NSTATE], xqn[GEN_NSTATE], pg_q, qg_q;
        for (int i = 0; i < GEN_NSTATE; i++)
            xq[i] = xh[i].to_double();
        ref_step(xq, q8_24_t(v).to_double(), q8_24_t(th).to_double(),
                 q8_24_t(vref).to_double(), q8_24_t(pref).to_double(),
                 xqn, &pg_q, &qg_q);
        for (int i = 0; i < GEN_NSTATE; i++)
            one_step_err[i] = fmax(one_step_err[i],
                                   fabs(xhn[i].to_double() - xqn[i]));
        one_step_err[GEN_NSTATE]     = fmax(one_step_err[GEN_NSTATE],
                                            fabs(pg_h.to_double() - pg_q));
        one_step_err[GEN_NSTATE + 1] = fmax(one_step_err[GEN_NSTATE + 1],
                                            fabs(qg_h.to_double() - qg_q));

        // (2) free-running golden trajectory
        double pg_r, qg_r;
        ref_step(xr, v, th, vref, pref, xrn, &pg_r, &qg_r);
        for (int i = 0; i < GEN_NSTATE; i++)
            traj_err[i] = fmax(traj_err[i], fabs(xhn[i].to_double() - xrn[i]));
        pq_err = fmax(pq_err, fabs(pg_h.to_double() - pg_r));

        if (k % 10 == 0)
            fprintf(fp, "%.4f,%.9f,%.9f,%.9f,%.9f,%.9f,%.9f,%.9f,%.9f,"
                        "%.9f,%.9f,%.9f,%.9f,%.9f,%.9f\n",
                    t, xh[0].to_double(), xr[0], xh[1].to_double(), xr[1],
                    xh[2].to_double(), xr[2], xh[4].to_double(), xr[4],
                    xh[5].to_double(), xr[5], pg_h.to_double(), pg_r,
                    qg_h.to_double(), qg_r);

        for (int i = 0; i < GEN_NSTATE; i++) {
            xh[i] = xhn[i];
            xr[i] = xrn[i];
        }
    }
    fclose(fp);

    // ------------------------------------------------------------- report --
    // One step: |err| must stay within a few Q8.24 LSBs (CORDIC + rounding)
    const double ONE_STEP_TOL = 64 * LSB;     // ~3.8e-6
    // Trajectory: allows quantisation drift accumulated over 6000 steps
    const double TRAJ_TOL     = 1e-3;

    int fail = 0;
    printf("\n%-6s %16s %16s\n", "state", "1-step |err|", "trajectory |err|");
    for (int i = 0; i < GEN_NSTATE; i++) {
        printf("%-6s %16.3e %16.3e\n", names[i], one_step_err[i], traj_err[i]);
        if (one_step_err[i] > ONE_STEP_TOL || traj_err[i] > TRAJ_TOL)
            fail = 1;
    }
    printf("%-6s %16.3e %16.3e\n", "Pg", one_step_err[GEN_NSTATE], pq_err);
    printf("%-6s %16.3e\n", "Qg", one_step_err[GEN_NSTATE + 1]);
    if (one_step_err[GEN_NSTATE] > ONE_STEP_TOL ||
        one_step_err[GEN_NSTATE + 1] > ONE_STEP_TOL)
        fail = 1;

    // ------------------------------------------------ golden file for RTL TB --
    // Words (hex, one per line): 11 INIT words, then per step: V, theta and
    // the 11 expected output words. Used by ../tb/rtds_gen_top_tb.sv.
    {
        const int N_GOLD = 4;
        FILE *fg = fopen("gen_step_golden.hex", "w");
        q8_24_t xg[GEN_NSTATE], xgn[GEN_NSTATE], pg_g, qg_g;
        for (int i = 0; i < GEN_NSTATE; i++) {
            xg[i] = X0[i];
            fprintf(fg, "%08x\n", (unsigned)xg[i].range(31, 0).to_uint());
        }
        fprintf(fg, "%08x\n", (unsigned)q8_24_t(vref).range(31, 0).to_uint());
        fprintf(fg, "%08x\n", (unsigned)q8_24_t(pref).range(31, 0).to_uint());
        for (int k = 0; k < N_GOLD; k++) {
            q8_24_t v  = (0.95 - 0.02 * k) * V_SS;   // a changing terminal bus
            q8_24_t th = -0.01 * k;
            hw_step(xg, v, th, vref, pref, xgn, &pg_g, &qg_g);
            fprintf(fg, "%08x\n%08x\n", (unsigned)v.range(31, 0).to_uint(),
                    (unsigned)th.range(31, 0).to_uint());
            for (int i = 0; i < GEN_NSTATE; i++) {
                fprintf(fg, "%08x\n", (unsigned)xgn[i].range(31, 0).to_uint());
                xg[i] = xgn[i];
            }
            fprintf(fg, "%08x\n%08x\n", (unsigned)pg_g.range(31, 0).to_uint(),
                    (unsigned)qg_g.range(31, 0).to_uint());
        }
        fclose(fg);
    }

    printf("\nFinal HW state  : ");
    for (int i = 0; i < GEN_NSTATE; i++) printf("%.6f ", xh[i].to_double());
    printf("\nFinal ref state : ");
    for (int i = 0; i < GEN_NSTATE; i++) printf("%.6f ", xr[i]);
    printf("\n\n*** TEST %s ***\n", fail ? "FAILED" : "PASSED");
    return fail;
}
