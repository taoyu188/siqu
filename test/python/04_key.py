# 04 字典缺键（KeyError）
# 运行：.\pyrun.cmd test\python\04_key.py
# 祀应该会说："这个键不存在。"

scores = {"语文": 90, "数学": 85}
subjects = ["语文", "数学", "英语"]

for sub in subjects:
    print(sub, "=", scores[sub])
