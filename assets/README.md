# 把立绘放这里

这个目录**不随仓库分发**（`.gitignore` 已排除），因为立绘属于各自原作者。

想恢复「祀」的立绘：

1. 准备 8 张透明 PNG，命名成 `idle.png` / `happy.png` / `taunt.png` /
   `confused.png` / `embarrassed.png` / `jealous.png` / `pout.png` / `sleep.png`
2. 放进本目录，前缀 `siqu-`，例如 `siqu-idle.png`
3. 它们会自动被 `roles/roles.json` 里的 `si` 角色用到

或者更推荐：用自己的角色包——

```powershell
node ..\tools\character.js --new mychar --name 我的角色
node ..\tools\character.js --use mychar
```

详见仓库根目录 README 的「换角色」一节。