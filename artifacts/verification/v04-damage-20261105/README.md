# V04 全牌升级与战斗完成量飘字验证

日期：2026-11-05。需求：FY-UX-024、FY-ACT-004。基线提交：`de175c174c1a8adce283d3a5c01998532c79a555`，验证对象为该提交上的当前未提交增量。引擎：`Godot 4.7.2.stable.official.ed1daf0bf`；窗口截图使用 Windows OpenGL 3.3 Compatibility、Intel UHD Graphics。测试设置隔离的 `APPDATA` 与 `LOCALAPPDATA`，均指向本目录 `isolated_appdata/`；测试存档使用 `user://` 隔离路径，未修改玩家实际存档。

## 输入登记（SHA256）

| 文件 | SHA256 |
|---|---|
| `data/four_year/manifests/campus_four_year.json` | `2D8744B71D00DF58DB56DF904A3214D994AA37B200AE64334968B6CA7E43116C` |
| `data/four_year/definitions/events.json` | `26FFEACF86EA9AD5842FC8989A47336AD5986EE28677D772ED10053C8E69CD3D` |
| `tests/run_tests.gd` | `ED8DC578B1C5060EC140072ADF4E01AEE94180FBD482FA41D32EC83B74802925` |
| `tests/run_ui_tests.gd` | `6B361C3E7B3E6ECD8FF9CDDAFDC0AC6300C5433D7E9139A0DB148C1C4F128E08` |
| `tests/suites/test_run_nodes.gd` | `BD6C96346F87E248DDD12F6A90E29ABEB50FBEF7790CC845DACA3C38D9433434` |
| `tests/suites/test_ui_experience.gd` | `F1D5C30CF388372A30D0A01A7448C54AFFC34D126E9E80AF266C28E4983001AC` |
| `tests/suites/test_ui_damage_popup.gd` | `61C0D311A872B7DFFC4779D4E38255024DF671820BD7D8324E44980ACAD139AA` |
| `tests/suites/test_ui_followup.gd` | `5C0DB1E374C50BEB7E7DC1F32C94AEFAF406D15315E5465DE107A9AB2989A215` |
| `tools/capture_v04_damage.gd` | `7CC6E3D856C0B836BE84170BC3342C63D307725F5211FD120C831FDE352F82A8` |

## 实际运行

所有命令在仓库根目录执行，Godot 路径为 `D:\chrome\godot\Godot_v4.7.2-stable_win64_console.exe`。

| 命令参数 | 退出码 | 原始输出 |
|---|---:|---|
| `--headless --path . --script res://tests/run_tests.gd` | 0 | `rules-final.stdout.log`、`rules-final.stderr.log`、`rules-final.godot.log` |
| `--headless --path . --script res://tests/run_ui_tests.gd` | 0 | `ui-acceptance.stdout.log`、`ui-acceptance.stderr.log`、`ui-acceptance.godot.log` |
| `--path . --script res://tools/capture_v04_damage.gd` | 0 | `capture-final4.stdout.log`、`capture-final4.stderr.log`、`capture-final4.godot.log` |
| `git diff --check` | 0 | 无空白错误；工作区原有 `.import` 文件有换行转换警告 |

规则入口报告 G1/G2/G3、G4、G5 无头套件通过；UI 入口报告 `FY_UX_CHECKS.failures=[]`、`UI_FOLLOWUP.failures=[]` 和 `G7 UI tests passed`。三次最终运行均未出现 `SCRIPT ERROR`。规则与 UI 标准错误仅有本机系统证书库读取警告；截图运行标准错误为空。以上测试入口的套件标签不代表本次重新验收整版阶段出口。

## 实渲核对

`visual/capture.json` 记录页面、分辨率、飘字文本与图片保存码；六张 PNG 均保存成功。`event-preview-1280x800.png`、`event-preview-960x600.png` 可直接看到自动升级 5 张工作牌及目标前后比较；`hit-1280x800.png`、`hit-960x600.png` 中显示 `-6`；`lethal-1280x800.png`、`lethal-960x600.png` 中显示 `-1`，飘字期间保留战斗画面。普通布局的目标锚点为 `(868, 325)`、飘字起点 `(788, 281)`；紧凑布局为 `(92.5, 350)`、`(12.5, 306)`。脚本在选牌与点目标之间等待绘制帧，与实际交互顺序一致。

规则测试覆盖多张同名工作牌、满级/非工作牌、无合格目标、精力不足、重复提交和一次扣费；UI 测试覆盖事件预览/确认及续档、真实卡牌命中、双目标/伙伴/持续事件、屏障吸收、过量攻击、连续命中和减少动态；窗口截图覆盖击倒与两种布局。

整版 G0 规则与生产清单、G6 人工资源签收、G8 完整用户路径、性能与打包出口仍未关闭。本次验证不替代这些出口。
