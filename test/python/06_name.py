# 06 变量名拼错（NameError）
# 运行：.\pyrun.cmd test\python\06_name.py
# 祀应该会说："这个变量不存在。你自己造的？"

total = 0
scores = [88, 92, 79]

for s in scores:
    totol += s          # 拼错了：totol → total

print("总分:", total)
