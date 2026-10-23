// =============================================================================
// gen_step.cpp - Pipelined (II = 1) Q8.24 generator model for Vivado HLS
//
// Implements, for machine 1 of TA_Simulation.m (daefun):
//
//   Vd = V sin(delta - theta)          Vq = V cos(delta - theta)
//   Id = (Ed'-Vd) Rs/den + (Eq'-Vq) xq'/den
//   Iq = (Eq'-Vq) Rs/den - (Ed'-Vd) xd'/den        den = Rs^2 + xd' xq'
//   Pg = Vd Id + Vq Iq     Qg = Vq Id - Vd Iq      Pe = Pg + Rs (Id^2 + Iq^2)
//
//   f1 = ws (w - 1)
//   f2 = 1/(2H) (Pm - Pe - Kd (w - 1))
//   f3 = 1/Tdo' (-Eq' - (xd - xd') Id + Efd)
//   f4 = 1/Tqo' (-Ed' + (xq - xq') Iq)
//   f5 = 1/TA   (-Efd + KA (Vref - V - x9))
//   f6 = 1/Tsg  (-Pm + Ksg (Pref + (1 - w)/R))
//   f7 = 1/TW   (-x7 - Kstab TW f2)
//   f8 = 1/T2   (-x8 + x7 + T1 f7)
//   f9 = 1/T4   (-x9 + x8 + T3 f8)
//
//   X(k+1) = X(k) + h f(X(k), V(k), theta(k))         (forward Euler, h = 1 ms)
//
// Control interface: ap_ctrl_hs. Pulse ap_start every 1 ms; ap_done is the
// "step done" signal. The function is fully pipelined with II = 1.
// =============================================================================
#include "gen_step.h"
#include "gen_params.h"

#define CORDIC_ITER 26

// CORDIC gain compensation (product of 1/sqrt(1 + 2^-2i))
static const cordic_t CORDIC_K = 0.6072529350088814;

// atan(2^-i)
static const cordic_t ATAN_TAB[CORDIC_ITER] = {
    0.78539816339744828,
    0.46364760900080609,
    0.24497866312686414,
    0.12435499454676144,
    0.06241880999595735,
    0.031239833430268277,
    0.015623728620476831,
    0.0078123410601011111,
    0.0039062301319669718,
    0.0019531225164788188,
    0.00097656218955931946,
    0.00048828121119489829,
    0.00024414062014936177,
    0.00012207031189367021,
    6.1035156174208773e-05,
    3.0517578115526096e-05,
    1.5258789061315762e-05,
    7.62939453110197e-06,
    3.8146972656064961e-06,
    1.907348632810187e-06,
    9.5367431640596084e-07,
    4.7683715820308884e-07,
    2.3841857910155797e-07,
    1.1920928955078068e-07,
    5.9604644775390552e-08,
    2.9802322387695303e-08
};

// sin / cos of any angle in Q8.24 range: reduce to [-pi, pi], fold into
// [-pi/2, pi/2], then run a fully unrolled rotation-mode CORDIC.
static void sincos_cordic(alg_t phi, cordic_t &s, cordic_t &c)
{
#pragma HLS INLINE
    const wide_t two_pi  = C_TWO_PI;
    const wide_t inv_2pi = C_INV_2PI;
    const wide_t pi      = P_PI;
    const wide_t half_pi = C_HALF_PI;

    // k = round(phi / 2pi), r = phi - 2pi k  ->  r in [-pi, pi]
    ap_fixed<8, 8, AP_RND, AP_SAT> turns = phi * inv_2pi;
    wide_t r = phi - two_pi * turns;

    bool neg = false;
    if (r > half_pi) {
        r  -= pi;
        neg = true;
    } else if (r < -half_pi) {
        r  += pi;
        neg = true;
    }

    cordic_t x = CORDIC_K;
    cordic_t y = 0;
    cordic_t z = r;

    for (int i = 0; i < CORDIC_ITER; i++) {
#pragma HLS UNROLL
        cordic_t xs = x >> i;
        cordic_t ys = y >> i;
        if (z >= 0) {
            x -= ys;
            y += xs;
            z -= ATAN_TAB[i];
        } else {
            x += ys;
            y -= xs;
            z += ATAN_TAB[i];
        }
    }

    s = neg ? (cordic_t)(-y) : y;
    c = neg ? (cordic_t)(-x) : x;
}

void gen_step(
    q8_24_t  v_mag,  q8_24_t  v_ang,  q8_24_t  v_ref,  q8_24_t  p_ref,
    q8_24_t  delta,  q8_24_t  omega,  q8_24_t  eq_p,   q8_24_t  ed_p,
    q8_24_t  efd,    q8_24_t  pm,     q8_24_t  x7,     q8_24_t  x8,
    q8_24_t  x9,
    q8_24_t *delta_n, q8_24_t *omega_n, q8_24_t *eq_p_n, q8_24_t *ed_p_n,
    q8_24_t *efd_n,   q8_24_t *pm_n,    q8_24_t *x7_n,   q8_24_t *x8_n,
    q8_24_t *x9_n,
    q8_24_t *pg,      q8_24_t *qg)
{
#pragma HLS INTERFACE ap_ctrl_hs port=return
#pragma HLS INTERFACE ap_none port=v_mag
#pragma HLS INTERFACE ap_none port=v_ang
#pragma HLS INTERFACE ap_none port=v_ref
#pragma HLS INTERFACE ap_none port=p_ref
#pragma HLS INTERFACE ap_none port=delta
#pragma HLS INTERFACE ap_none port=omega
#pragma HLS INTERFACE ap_none port=eq_p
#pragma HLS INTERFACE ap_none port=ed_p
#pragma HLS INTERFACE ap_none port=efd
#pragma HLS INTERFACE ap_none port=pm
#pragma HLS INTERFACE ap_none port=x7
#pragma HLS INTERFACE ap_none port=x8
#pragma HLS INTERFACE ap_none port=x9
#pragma HLS INTERFACE ap_vld  port=delta_n
#pragma HLS INTERFACE ap_vld  port=omega_n
#pragma HLS INTERFACE ap_vld  port=eq_p_n
#pragma HLS INTERFACE ap_vld  port=ed_p_n
#pragma HLS INTERFACE ap_vld  port=efd_n
#pragma HLS INTERFACE ap_vld  port=pm_n
#pragma HLS INTERFACE ap_vld  port=x7_n
#pragma HLS INTERFACE ap_vld  port=x8_n
#pragma HLS INTERFACE ap_vld  port=x9_n
#pragma HLS INTERFACE ap_vld  port=pg
#pragma HLS INTERFACE ap_vld  port=qg
#pragma HLS PIPELINE II=1

    // ---------------------------------------------------------- coefficients
    const kc_t k_rs_den  = C_RS_DEN;
    const kc_t k_xqp_den = C_XQP_DEN;
    const kc_t k_xdp_den = C_XDP_DEN;
    const ks_t k_rs      = C_RS;
    const kc_t k_xd_diff = C_XD_DIFF;
    const kc_t k_xq_diff = C_XQ_DIFF;

    const kc_t k_h_ws    = C_H_WS;
    const ks_t k_h_2h    = C_H_2H;
    const kc_t k_kd      = C_KD;
    const ks_t k_h_tdo   = C_H_TDO;
    const kc_t k_h_tqo   = C_H_TQO;
    const kc_t k_h_ta    = C_H_TA;
    const kc_t k_h_ka_ta = C_H_KA_TA;
    const kc_t k_h_tsg   = C_H_TSG;
    const kc_t k_h_ksg   = C_H_KSG;
    const kc_t k_h_ksg_r = C_H_KSG_R;
    const ks_t k_h_tw    = C_H_TW;
    const kc_t k_kstab   = C_KSTAB;
    const kc_t k_h_t2    = C_H_T2;
    const kc_t k_t1_t2   = C_T1_T2;
    const ks_t k_h_t4    = C_H_T4;
    const kc_t k_t3_t4   = C_T3_T4;

    // ------------------------------------------------- stator / network side
    cordic_t s_phi, c_phi;
    alg_t phi = (alg_t)delta - (alg_t)v_ang;
    sincos_cordic(phi, s_phi, c_phi);

    alg_t vd = v_mag * s_phi;
    alg_t vq = v_mag * c_phi;

    alg_t d_ed = ed_p - vd;
    alg_t d_eq = eq_p - vq;

    alg_t id = d_ed * k_rs_den  + d_eq * k_xqp_den;
    alg_t iq = d_eq * k_rs_den  - d_ed * k_xdp_den;

    alg_t pg_a = vd * id + vq * iq;
    alg_t qg_a = vq * id - vd * iq;
    wide_t i_sq = id * id + iq * iq;      // ~52 at rated load: needs > Q8
    alg_t pe   = pg_a + k_rs * i_sq;

    // ------------------------------------------- h * f(X)  (state increments)
    alg_t dw = omega - (q8_24_t)1;

    wide_t inc_delta = k_h_ws * dw;
    wide_t inc_omega = k_h_2h * (alg_t)(pm - pe - k_kd * dw);
    wide_t inc_eq    = k_h_tdo * (alg_t)(efd - eq_p - k_xd_diff * id);
    wide_t inc_ed    = k_h_tqo * (alg_t)(k_xq_diff * iq - ed_p);
    wide_t inc_efd   = k_h_ka_ta * (alg_t)(v_ref - v_mag - x9) - k_h_ta * efd;
    wide_t inc_pm    = k_h_ksg * p_ref - k_h_ksg_r * dw - k_h_tsg * pm;
    wide_t inc_x7    = -(wide_t)(k_h_tw * x7) - k_kstab * inc_omega;
    wide_t inc_x8    = k_h_t2 * (alg_t)(x7 - x8) + k_t1_t2 * inc_x7;
    wide_t inc_x9    = k_h_t4 * (alg_t)(x8 - x9) + k_t3_t4 * inc_x8;

    // ------------------------------- X(k+1) = X(k) + h f, rounded to Q8.24
    q8_24_rnd_t r_delta = delta + inc_delta;
    q8_24_rnd_t r_omega = omega + inc_omega;
    q8_24_rnd_t r_eq    = eq_p  + inc_eq;
    q8_24_rnd_t r_ed    = ed_p  + inc_ed;
    q8_24_rnd_t r_efd   = efd   + inc_efd;
    q8_24_rnd_t r_pm    = pm    + inc_pm;
    q8_24_rnd_t r_x7    = x7    + inc_x7;
    q8_24_rnd_t r_x8    = x8    + inc_x8;
    q8_24_rnd_t r_x9    = x9    + inc_x9;
    q8_24_rnd_t r_pg    = pg_a;
    q8_24_rnd_t r_qg    = qg_a;

    *delta_n = r_delta;
    *omega_n = r_omega;
    *eq_p_n  = r_eq;
    *ed_p_n  = r_ed;
    *efd_n   = r_efd;
    *pm_n    = r_pm;
    *x7_n    = r_x7;
    *x8_n    = r_x8;
    *x9_n    = r_x9;
    *pg      = r_pg;
    *qg      = r_qg;
}
