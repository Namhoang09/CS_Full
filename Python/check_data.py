import numpy as np

# ── Cấu hình: chỉ cần sửa ở đây ──────────────────────────────────
Link     = "coef"
FILE_RTL = "Data/" + Link + "_output.txt"   # output từ ModelSim
FILE_PY  = "Data/" + Link + "_check.txt"    # reference từ Python
# ─────────────────────────────────────────────────────────────────

# Dùng float64 để đọc (tránh overflow int64), sau đó so sánh
a = np.atleast_1d(np.loadtxt(FILE_RTL, dtype=np.float64))
b = np.atleast_1d(np.loadtxt(FILE_PY, dtype=np.float64))

print(f"RTL   : {FILE_RTL}  ({len(a)} phần tử)")
print(f"Python: {FILE_PY}  ({len(b)} phần tử)")

if len(a) != len(b):
    print(f"KHÁC ĐỘ DÀI")
else: 
    mismatches = np.where(a != b)[0]
    if len(mismatches) == 0:
        print("KHỚP HOÀN TOÀN")
    else:
        print(f"SAI LỆCH")
        for idx in mismatches:
            print(f"Index [{idx}]: RTL= {a[idx]}, Python = {b[idx]}")