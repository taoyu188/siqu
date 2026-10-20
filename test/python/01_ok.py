# 01 正确示范：算平均分
# 运行：.\pyrun.cmd test\python\01_ok.py
# 预期：她什么都不说（或者只说"过了"）

scores = [88, 92, 79, 95]
total = 0
for s in scores:
    total += s

avg = total / len(scores)
print("平均分:", avg)
print("格式化:", f"{avg:.2f}")
