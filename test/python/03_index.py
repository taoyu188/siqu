# 03 列表越界（IndexError）
# 运行：.\pyrun.cmd test\python\03_index.py
# 祀应该会说："越界了。跟 C 数组一个毛病。"

scores = [88, 92, 79]
for i in range(len(scores) + 1):     # 多跑了一圈
    print(f"第 {i} 个: {scores[i]}")
