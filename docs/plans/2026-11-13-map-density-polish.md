# 地图密度与外观追加实施计划

日期：2026-11-13。来源：用户实测大一地图反馈；沿根计划§0.19/0.19.1和原逐年地图计划执行。需求FY-MAP-007。

目标：三个初始方向，中段四至五条持续路线，减少中央留白；保留不同经历、长分支和真实预告。采用Godot原生绘制及现有配色，无新素材请求。

## 设计与验收

- 新生成算法版本2：三条独立主线，至少两处长支线，中间层3–5节点，至少一半中间层有4–5节点；起点三个出口，普通节点至多两个出口。无重复列、不可达节点、死路或起点/Boss外全局瓶颈；分岔至少三个独立节点再合流。
- 每次实际游玩仍为12/12/14/14站；不因候选增多提高战斗/风险预算。各路线保留商店、两次实际休息、大二后半可转向服务、大四两次ST、无精英完整通路。种子改变拓扑和内容层位，经历仅影响机会。
- campaign.version仍为2；map_version区分算法1/2。保留原生成器字节语义；旧逐年图恢复与未来生成按版本1，新开局按版本2；未知版本与混合版本拒绝。
- 显示改为紧凑图标节点和下方短标签，弧线避开文字，已过/当前/可入/不可达用符号和颜色共同标识；路线宽度居中限制，纵向间距缩短。现有资源槽在详细图和概览可用。
- 保留节点UID、键盘方向导航、只读预告、进入门控、当前定位、全图概览；1280×800和960×600，字号100/125/150不重叠、不截断按钮。

## 执行步骤

- [x] G0：补根计划、FY-MAP-007文字需求及接口兼容说明。
- [x] G1–G4：生成器独立版本2；增加批量密度/入口/长支线/预算用例，原版本1全部旧用例继续通过。
- [x] G5：按存档版本分发种子和生成算法，验证版本1读档/继续跨年、版本2重放及混合版本拒绝。
- [x] G6/G7：复用现有颜色资源，紧凑节点/图标/弧线/稳定布局；补实际生产密图的布局、键盘、资源槽检查。
- [x] G8子项：完整规则/UI回归及两尺寸三字号168张实渲，检查实际截图并保留输入、命令、退出码与原始日志；更新追踪与[交付记录](../地图密度与外观改进记录_20261113.md)。

文件边界：生成器工作集中在src/run/annual_map_generator*.gd与生成器测试；界面集中在src/ui/route_canvas.gd、experience_page.gd及节点绘制脚本与UI测试；主线处理campaign_progression.gd、存档兼容用例、契约与证据。使用tools/verify_adaptive_maps.py的新命名输出保留旧证据，不提交或重置现有工作区。

实际验证命令：`python tools/verify_adaptive_maps.py density-rules res://tests/run_tests.gd`；`python tools/verify_adaptive_maps.py density-ui-final res://tests/run_ui_tests.gd`；`python tools/verify_adaptive_maps.py density-visual res://tools/capture_adaptive_maps.gd --visual --script-arg=--output=res://artifacts/verification/adaptive-maps-20261113/density-visual-png`。另运行density-import和density-progression-green。截图脚本新增输出参数，避免覆盖首轮实渲。所有最终检查退出0、引擎错误0；自动验证不代表人工美术、自然平衡或完整G8验收。
