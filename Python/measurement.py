import numpy as np
from config import *

def generate_lfsr(length, seed=0xDEADBEEF, poly=0x80200003):
    lfsr = seed
    g = np.zeros(length, dtype=np.int8)
    
    for i in range(length):
        # Lấy bit LSB làm ngõ ra
        g[i] = lfsr & 1
        
        # Dịch bit và XOR với đa thức nếu LSB = 1
        if lfsr & 1:
            lfsr = (lfsr >> 1) ^ poly
        else:
            lfsr = lfsr >> 1
            
    return g

def generate():
    n = np.arange(Ne)
    t = n * delta_T

    # Sóng mang gốc s(t)
    S = Ap * (2 + np.cos(2 * np.pi * Fc1 * t) + np.cos(2 * np.pi * Fc2 * t))
    
    # Nd_test có thể chạy từ 0 → Ne-1
    max_Nd = Ne - 1
    total_length = max_Nd + (M - 1)*Nc + Ne

    # Chỉ tạo 1 chuỗi g duy nhất
    g = generate_lfsr(total_length)

    # Tạo ma trận A đúng theo paper
    A = np.zeros((M, Ne))
    
    for m in range(M):
        start = Nd + m*Nc
        A[m,:] = g[start : start + Ne]

    # Tín hiệu nén quan sát được tại PD
    Po = A @ S

    return t, S, A, Po, g

def get_fourier_dict(N):
    D = np.zeros((N, N))
    D[:, 0] = 1.0 / np.sqrt(N) # Thành phần DC
    
    for k in range(1, N // 2):
        D[:, 2*k - 1] = np.sqrt(2/N) * np.cos(2 * np.pi * k * np.arange(N) / N)
        D[:, 2*k]     = np.sqrt(2/N) * np.sin(2 * np.pi * k * np.arange(N) / N)
        
    D[:, -1] = 1.0 / np.sqrt(N) * np.cos(np.pi * np.arange(N))
    return D
