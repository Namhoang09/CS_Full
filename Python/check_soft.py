import numpy as np

from measurement import *
from config import *

# ── Sinh g bằng LFSR (khớp với RTL) ──────────────────────────────
GWIN_W    = 2 * Ne - 1          
total_length = (Ne - 1) + (M - 1) * Nc + Ne 
 
g = generate_lfsr(total_length)

# ── Xây A tại ND_TEST ─────────────────────────────────────────────
A = np.zeros((M, Ne), dtype=np.int32)
for m in range(M):
    gwin_m = g[m * Nc : m * Nc + GWIN_W]
    A[m]   = gwin_m[Nd : Nd + Ne]
 
# ── D_int (scaled, khớp với gen_theta_data.py) ────────────────────
scale     = np.sqrt(4.0 / M)
D_fourier = get_fourier_dict(Ne)
D_int     = np.round(D_fourier * scale * (1 << FRAC_D)).astype(np.int32)

# ── Po_int ────────────────────────────────────────────────────────
n = np.arange(Ne)
t = n * delta_T
S = Ap * (2 + np.cos(2 * np.pi * Fc1 * t) + np.cos(2 * np.pi * Fc2 * t))

S_int = np.round(S * (1 << FRAC_S)).astype(np.int32)

Po     = A.astype(np.float64) @ S
Po_int = np.round(Po * (1 << FRAC_S)).astype(np.int32)

# ── Mảng lưu trữ SSE để kiểm tra cực tiểu ─────────────────────────
sse_array = np.zeros(Ne, dtype=np.uint64)

for Nd_t in range(Ne):
    A_t = np.zeros((M, Ne), dtype=np.int32)
    for m in range(M):
        gwin_m = g[m * Nc : m * Nc + GWIN_W]
        A_t[m]   = gwin_m[Nd_t : Nd_t + Ne]
        
    # ── Theta = A @ D_int  [M × NE] ───────────────────────────────────
    Theta_t = A_t.astype(np.int64) @ D_int.astype(np.int64)   # shape: (M, NE)

    r    = Po_int.astype(np.int64)
    coef = np.zeros(Ne, dtype=np.int64)

    for _ in range(K_MP):
        corr     = Theta_t.T @ r                           # [NE]
        best_col = int(np.argmax(np.abs(corr)))

        if best_col == 0:
            alpha = (corr[best_col] >> NORM_SHIFT_DC).astype(np.int32)
        else:
            alpha = (corr[best_col] >> NORM_SHIFT).astype(np.int32)

        coef[best_col] = np.int32(coef[best_col] + alpha)
        r -= Theta_t[:, best_col] * np.int64(alpha)

    # ── Tính SSE (giống RTL) ──────────────────────────────────────────
    srec_acc = D_int.astype(np.int64) @ coef.astype(np.int32).astype(np.int64)
    diff     = (S_int.astype(np.int64) - srec_acc) >> SSE_SHIFT
    sse      = np.sum(diff ** 2).astype(np.uint64)

    # Lưu sse vào mảng
    sse_array[Nd_t] = sse

# ── Kiểm tra xem SSE có đạt cực tiểu tại Nd không ─────────────────
Nd_estimated = np.argmin(sse_array)
sse_min = sse_array[Nd_estimated]

print(f"Khoảng cách thực tế : {Nd}")
print(f"Khoảng cách ước lượng : {Nd_estimated}")
print(f"SSE min tương ứng     : {sse_min}")

if Nd_estimated == Nd:
    print(f"=> KẾT QUẢ: THÀNH CÔNG! SSE đạt cực tiểu đúng tại Nd")
else:
    print(f"=> KẾT QUẢ: THẤT BẠI! SSE_min không nằm ở Nd")
 