# 彩平图机器人 · caipingtu-bot

把 CAD 黑白户型线稿，变成**室内设计彩平图（colored floor plan）**，并自动擦掉生图平台强制加的水印。

一个可以直接装进 AI 助手当技能用的工具包：**提示词模板 + 三条风格基线（现代奶油 / 宋式美学 / 中古风）+ LaMa 深度学习去水印**。

> 核心原则：**户型结构保真 > 一切风格表现**。风格可以换，户型不能变形。

---

## 一键安装

**Windows（PowerShell）**

```powershell
irm https://raw.githubusercontent.com/zhuhengji2/caipingtu-bot/main/install.ps1 | iex
```

**macOS / Linux**

```bash
curl -fsSL https://raw.githubusercontent.com/zhuhengji2/caipingtu-bot/main/install.sh | bash
```

脚本会自动做四件事：下载本仓库 → 装到 `~/.workbuddy/skills/caipingtu` → 装 Python 依赖 → 下载 208MB 修复模型。
**重启 AI 助手，发一张线稿说「做彩平图」就生效了。**

不想跑脚本？也可以手动装：

```bash
git clone https://github.com/zhuhengji2/caipingtu-bot.git ~/.workbuddy/skills/caipingtu
cd ~/.workbuddy/skills/caipingtu && pip install -r requirements.txt && python scripts/download_model.py
```

> 网络拉不动 GitHub 时，安装脚本会自动切换 `gh-proxy` / `ghfast` 镜像；模型下载自带 8 线程断点续传 + hf-mirror。
> 也可以点右上角 **Use this template** 复制成你自己的仓库，改成你的风格体系再分发。

---

## 它是怎么工作的

```
CAD 线稿(.png)  ──┐
                  ├─►  生图模型（双图输入：线稿 + 风格基准图）
风格基准图(.jpg) ──┘            │
                                ▼
                        彩平图（右下角带平台水印）
                                │
                                ▼
                   scripts/lama_remove.py（LaMa 修复擦水印）
                                │
                                ▼
                        干净成品 · 可直接进方案册
```

生图这一步由你使用的 AI 助手平台提供（本仓库不含模型和额度）；本仓库负责真正决定成片质量的另外三块——**提示词、风格规范、后处理**。

---

## 用起来是什么样

装好后，在对话里发一张户型线稿，说一句：

> 做彩平图，宋式美学

它会自动：读结构 → 拼三段式提示词 → 出图 → 检测并擦除水印 → 按 `125平-宋式美学.png` 命名交付 → 对照线稿逐项核验。

切换风格只需换词：`奶油风` / `宋式美学` / `中古风`。

---

## 免费吗？会花谁的钱

| 项目 | 成本 |
|---|---|
| 本仓库（提示词、脚本、模型、风格基线） | **免费，MIT 协议，可商用** |
| 去水印（LaMa 本地推理） | **免费，纯 CPU，不限次数** |
| 生图 | 由使用者自己的 AI 账号额度承担，每张约 5–10 点 |

分发给别人时不用担心替你烧额度——**用的是他们自己的账号**。

---

## 出图四步法

1. **读图**：把线稿结构逐条写成文字（上排从左到右是什么、下排是什么、每间房有哪些家具）。
2. **拼提示词**：按 [`reference/prompt-template.md`](reference/prompt-template.md) 填三段——结构块 + 风格块 + 灯光块。第一条永远是「几何保真第一优先」。
3. **生成**：线稿作 image1、风格基准图作 image2，`input_fidelity=high`，**尺寸必须与线稿一致**（横版 1536×1024 / 竖版 1024×1536）。
4. **验收**：对照线稿逐项核对房间数量和位置，不通过就改提示词重出。错的结构修不了，只能重来。

---

## 关键经验（踩过的坑）

| 坑 | 原因 | 解法 |
|---|---|---|
| 布局被参考图带跑（出现 L 形弧墙） | 输出尺寸和竖版参考图一致，模型连户型一起学了 | 尺寸跟线稿，提示词写明「参考图仅作风格参考，严禁照搬户型」 |
| 墙体颜色被带偏（灰变棕） | 只说「参照参考图」太笼统 | 逐项写死：墙体中灰、地面奶油米白、背景只出现在户型外围 |
| 修复区出现灰色糊块 | OpenCV `inpaint` 遇到深色墙体就平均化 | 换 LaMa 深度修复（本仓库方案） |
| 地板纹理被水印挡过就糊成一片 | 同上 | `rect` 模式整块重建 |
| 中文路径读图失败 | `cv2.imread` 不支持非 ASCII 路径 | 脚本已改用 `np.fromfile` + `imdecode` |
| 平台水印关不掉 | 提示词 / footnote 参数都无效 | 只能事后修复，且**不能裁图**（会丢画面、比例不对） |

---

## 目录结构

```
caipingtu-bot/
├── SKILL.md                  # 技能定义：触发词、铁律、流程、验收红线
├── install.ps1 / install.sh  # 一键安装
├── requirements.txt
├── scripts/
│   ├── lama_remove.py        # LaMa 去水印（detect / rect）
│   └── download_model.py     # 208MB 模型断点续传
├── reference/
│   ├── prompt-template.md    # 三段式提示词模板
│   ├── style-baselines.md    # 三条风格的配色材质规格
│   └── 基准图-*.jpg          # 风格基准图（现代奶油/宋式/中古）
└── samples/                  # 放你自己的成果图（不入库）
```

`scripts/models/` 与 `samples/` 被 `.gitignore` 排除——**客户项目的线稿和成品图不要推到公开仓库**。

---

## 三条风格基线速查

| 风格 | 墙体 | 地面 | 家具 | 氛围 |
|---|---|---|---|---|
| 现代奶油 | 深炭灰剖面 + 暖橙灯带 | 浅原木地板 | 米白布艺、浅木 | 暖奶油、干净 |
| 宋式美学 | 中灰剖面 | 奶油米白 + 浅灰地毯 | 奶油白布艺、原木、朱砂红圆凳 | 低饱和古画、外围绢本山水底 |
| 中古风 | 砖红/橘红剖面 | 客餐厅深藏青、厨卧木地板 | 奶油白沙发、彩色餐椅、宝蓝圆毯 | 浅粉底、扁平插画风 |

详细规格见 [`reference/style-baselines.md`](reference/style-baselines.md)。想加风格：换一张 `基准图-<风格>-默认.jpg`，再补一段规格即可。

---

## 已知限制

- AI 生成是**高保真还原**，不是像素级精确。墙厚、门洞位置偶有小出入，交付前务必人工核一遍。
- 复杂户型（异形、多折线）建议拆分区域分别出图。
- 生图有额度成本；去水印纯本地，免费无限次。
- `reference/` 里的基准图来自公开渠道的收集，仅供学习参考；商业发布请替换为自有素材。

---

## License

MIT
