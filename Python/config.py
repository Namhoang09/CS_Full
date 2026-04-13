# Cố định bởi vật lý
c = 3e8                                     # Tốc độ ánh sáng (m/s)

# Cố định bởi phần cứng
Fc1 = 100e6                                 # Tần số f_c1 = 100 MHz
Fc2 = 110e6                                 # Tần số f_c2 = 110 MHz

Fs = 2e9                                    # Tần số lấy mẫu của tín hiệu ngẫu nhiên g(n) = 2 GHz
delta_T = 1 / Fs                            # Chu kỳ lấy mẫu (0.5 ns)

Ne = round(1 / ((Fc2 - Fc1) * delta_T))     # Số mẫu trong thời gian phơi sáng (200 mẫu)
lambda_e = c / (Fc2 - Fc1)                  # Khoảng cách đo tối đa (30 m)
delta_L  = c * delta_T                      # Độ phân giải khoảng cách (0.15 m)

Fr = 1e4                                    # Tần số lặp lại của PD = 10 kHz
Nc = round(1 / (Fr * delta_T))              # Số mẫu của sóng mang trong 1 chu kỳ PD (200000 mẫu)

# Thông số thuật toán, có thể điều chỉnh
Ap = 30                                     # Biên độ tín hiệu

Nd = 100                                    # Độ trễ thực tế Nd (số mẫu)
actual_dist = Nd * c * delta_T              # Khoảng cách thực tế (m)

M = 20                                      # Số lượng mẫu PD thu được (số phương trình nén)

SNR_DB = None                               # Tín hiệu nhiễu (dB)

FRAC_Psi  = 14
FRAC_S  = 15
K_MP    = 10

NORM_SHIFT = 28
NORM_SHIFT_DC = 36
SSE_SHIFT = 15