#!/usr/bin/env python3
"""Approximate reference for the MACcore 4-sample NLMS smoke test.

This script documents the intended integer update rule and why the old "small
imaginary coefficient" expectation was not a valid golden for a 39-term model
trained from only four captured samples. The permanent Questa testbench is the
bit-exact regression for this snapshot.
"""

SAMPLES = [
    (1000, -500, 2000, -1000),
    (-1500, 700, -3000, 1400),
    (2200, 1100, 4400, 2200),
    (-800, -1200, -1600, -2400),
]

N_TERMS = 39
MAX_EPOCHS = 20
MIN_EPOCHS = 10
MU_SHIFT = 2


def sat16(value):
    return max(-32768, min(32767, value))


def sat18(value):
    return max(-131072, min(131071, value))


def isqrt32(value):
    return int(value ** 0.5)


def q15_umult(lhs, rhs):
    return min(32767, (lhs * rhs) >> 15)


def mag_q15(ii, qq):
    return min(32767, isqrt32(ii * ii + qq * qq))


def amp_power(amp, power):
    if power == 0:
        return 32767
    value = amp
    for p in range(1, 5):
        if p < power:
            value = (value * amp) >> 15
    return min(32767, value)


def term_x_pos(idx):
    if idx % 3 == 0:
        return 0
    if idx % 3 == 1:
        return 1
    return 2


def term_amp_pos(idx):
    if idx in (3, 12, 21, 30):
        return 0
    if idx in (4, 6, 13, 15, 22, 24, 31, 33):
        return 1
    if idx in (5, 7, 9, 14, 16, 18, 23, 25, 27, 32, 34, 36):
        return 2
    if idx in (8, 10, 17, 19, 26, 28, 35, 37):
        return 3
    if idx in (11, 20, 29, 38):
        return 4
    return 0


def term_power(idx):
    if idx < 3:
        return 0
    if idx < 12:
        return 1
    if idx < 21:
        return 2
    if idx < 30:
        return 3
    return 4


def basis_component(comp, amp, power):
    if power == 0:
        return comp
    return (comp * amp_power(amp, power)) >> 15


def basis(idx, fb_i, fb_q, mags):
    xpos = term_x_pos(idx)
    apos = term_amp_pos(idx)
    power = term_power(idx)
    return (
        basis_component(fb_i[xpos], mags[apos], power),
        basis_component(fb_q[xpos], mags[apos], power),
    )


def run():
    coef_r = [0] * N_TERMS
    coef_i = [0] * N_TERMS
    best_r = [0] * N_TERMS
    best_i = [0] * N_TERMS
    best_err = None
    status_error_acc = 0

    for epoch in range(MAX_EPOCHS):
        fb_i = [0] * 5
        fb_q = [0] * 5
        ref_i = [0] * 5
        ref_q = [0] * 5
        mags = [0] * 5
        acc_r = [0] * N_TERMS
        acc_i = [0] * N_TERMS
        den = [0] * N_TERMS
        model_error = 0

        for sri, srq, sfi, sfq in SAMPLES:
            status_error_acc += abs(sri - sfi) + abs(srq - sfq)
            fb_i = fb_i[1:] + [sfi]
            fb_q = fb_q[1:] + [sfq]
            ref_i = ref_i[1:] + [sri]
            ref_q = ref_q[1:] + [srq]
            mags = mags[1:] + [mag_q15(sfi, sfq)]

            if SAMPLES.index((sri, srq, sfi, sfq)) < 2:
                continue

            model_i = 0
            model_q = 0
            basis_cache = []
            for term in range(N_TERMS):
                bi, bq = basis(term, fb_i, fb_q, mags)
                basis_cache.append((bi, bq))
                model_i += ((bi * coef_r[term]) - (bq * coef_i[term])) >> 16
                model_q += ((bi * coef_i[term]) + (bq * coef_r[term])) >> 16

            err_i = sat16(ref_i[2] - model_i)
            err_q = sat16(ref_q[2] - model_q)
            model_error += abs(err_i) + abs(err_q)

            for term, (bi, bq) in enumerate(basis_cache):
                acc_r[term] += err_i * bi + err_q * bq
                acc_i[term] += err_q * bi - err_i * bq
                den[term] += bi * bi + bq * bq

        for term in range(N_TERMS):
            if den[term]:
                delta_r = int((acc_r[term] << 16) / (den[term] + 1)) >> MU_SHIFT
                delta_i = int((acc_i[term] << 16) / (den[term] + 1)) >> MU_SHIFT
            else:
                delta_r = 0
                delta_i = 0
            coef_r[term] = sat18(coef_r[term] + sat18(delta_r))
            coef_i[term] = sat18(coef_i[term] + sat18(delta_i))

        new_best = best_err is None or model_error < best_err
        stop = (
            epoch >= MAX_EPOCHS - 1
            or ((not new_best) and best_err is not None and epoch >= MIN_EPOCHS and model_error > best_err)
        )
        print(
            f"epoch={epoch:02d} model_error={model_error} "
            f"coef2=({coef_r[2]},{coef_i[2]}) acc2=({acc_r[2]},{acc_i[2]}) den2={den[2]}"
        )
        if new_best:
            best_err = model_error
            best_r = coef_r[:]
            best_i = coef_i[:]
        if stop:
            break

    print(f"best_error={best_err}")
    print(f"status_error_acc={status_error_acc}")
    print(f"coef2=({best_r[2]},{best_i[2]})")
    print(f"coef38_imag={best_i[38]}")


if __name__ == "__main__":
    run()
