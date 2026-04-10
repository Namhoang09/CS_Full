import numpy as np

from measurement import *
from config import *

def export_hex(array, filename, width_bits):
    hex_chars = width_bits // 4
    mask      = (1 << width_bits) - 1
    with open(filename, "w") as f:
        for val in array.flatten():
            f.write(f"{int(val) & mask:0{hex_chars}x}\n")

# ── Sinh g bằng LFSR (khớp với RTL) ──────────────────────────────
GWIN_W    = 2 * Ne - 1          
total_length = (Ne - 1) + (M - 1) * Nc + Ne 
 
g = generate_lfsr(total_length)

np.savetxt("Data/g_check.txt", g, fmt="%d")
print(f"Da ghi vao Data/g_check.txt")

# ── Xây A tại ND_TEST ─────────────────────────────────────────────
A = np.zeros((M, Ne), dtype=np.int32)
for m in range(M):
    gwin_m = g[m * Nc : m * Nc + GWIN_W]
    A[m]   = gwin_m[Nd : Nd + Ne]
 
# ── D_int (scaled, khớp với gen_theta_data.py) ────────────────────
scale     = np.sqrt(4.0 / M)
D_fourier = get_fourier_dict(Ne)
D_int     = np.round(D_fourier * scale * (1 << FRAC_D)).astype(np.int32)

export_hex(D_int.T.flatten(), "Data/d_matrix.txt", width_bits=16)
print(f"Da ghi vao Data/d_matrix.txt")

# ── Po_int ────────────────────────────────────────────────────────
n = np.arange(Ne)
t = n * delta_T
S = Ap * (2 + np.cos(2 * np.pi * Fc1 * t) + np.cos(2 * np.pi * Fc2 * t))

S_int = np.round(S * (1 << FRAC_S)).astype(np.int32)

export_hex(S_int, "Data/s_vector.txt", width_bits=32)
print(f"Da ghi vao Data/s_vector.txt")

Po     = A.astype(np.float64) @ S
Po_int = np.round(Po * (1 << FRAC_S)).astype(np.int32)

export_hex(Po_int, "Data/po_vector.txt", width_bits=32)
print(f"Da ghi vao Data/po_vector.txt")

# ── Theta = A @ D_int  [M × NE] ───────────────────────────────────
Theta = A.astype(np.int64) @ D_int.astype(np.int64)   # shape: (M, NE)

np.savetxt("Data/theta_check.txt", Theta.T.flatten(), fmt="%d")
print(f"Da ghi vao Data/theta_check.txt")

r    = Po_int.astype(np.int64)
coef = np.zeros(Ne, dtype=np.int64)

for it in range(K_MP):
    corr     = Theta.T @ r                           # [NE]
    best_col = int(np.argmax(np.abs(corr)))

    if best_col == 0:
        alpha = (corr[best_col] >> NORM_SHIFT_DC).astype(np.int32)
    else:
        alpha = (corr[best_col] >> NORM_SHIFT).astype(np.int32)
        
    coef[best_col] = np.int32(coef[best_col] + alpha)
    r -= Theta[:, best_col] * np.int64(alpha)

np.savetxt("Data/coef_check.txt", coef, fmt="%d")
print(f"Da ghi vao Data/coef_check.txt")

# ── Tính SSE (giống RTL) ──────────────────────────────────────────
srec_acc = D_int.astype(np.int64) @ coef.astype(np.int32).astype(np.int64)
diff     = (S_int.astype(np.int64) - srec_acc) >> SSE_SHIFT
sse      = np.sum(diff ** 2).astype(np.uint64)
 
np.savetxt("Data/sse_check.txt", [sse], fmt="%d")
print(f"Da ghi vao Data/sse_check.txt")
 