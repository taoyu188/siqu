# 05 忘了 return，拿 None 去用（AttributeError）
# 运行：.\pyrun.cmd test\python\05_none.py
# 祀应该会说："None 上面没有这个属性。"

def get_scores():
    scores = [88, 92, 79]          # 忘了写 return scores

result = get_scores()
print("总分:", result.append(100))
