# assets/

立绘与语音已经移到**角色包**里，这个目录只留少量辅助图。

| 用途 | 位置 |
|---|---|
| 角色立绘 / 语音 | `characters/si/` |
| 占位角色（可分发） | `characters/placeholder/` |
| 抠图中间产物 | 本目录（`siqu-bubble.png` 等，不进 git） |

换成自己的角色：

```powershell
node tools\character.js --new mychar --name 我的角色
node tools\character.js --use mychar
```