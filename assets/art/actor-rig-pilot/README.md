# 原生骨架实践资源

仅由 `tools/run_actor_rig_pilot.gd` 显式启用。`main.tscn` 默认仍使用原在用图片，用户存档不迁移。

P01：林序，8 件在用；N01：课后习题，9 件在用。每件是参考图编辑后重画的独立完整部件，本机去除品红背景生成实际 alpha。P01 的 `hem.png` 是保留的未用候选，完整衣身网格已替代它。`rig.json` 记录父子骨骼、轴心/偏移、层序、网格和动作；`source.json` 记录具体原图、抽取区域、尺寸和 SHA256。

提示词与 API 原件：`output/imagegen/actor-rig-pilot-20261114/`。用户授权最多200张，本批5张 API 输出；拆出的18件不再调用API。没有使用已否决的旧分层包或外部人物候选。当前技术选用不等同最终审美签收。

复现抽取：`python tools/build_actor_rig_pilot.py`。运行、实测与后续生产规范见[实践方案](../../../docs/plans/2026-11-14-actor-rig-feasibility-plan.md)。

最终证据为[render-05离线对照与连续动画](../../../artifacts/verification/actor-rig-pilot-20261114/review/index.html)：226项定向检查、5条真实命令A/B、19张PNG、247帧，规则和完整UI回归通过。全身/后层已实渲核对，肩肘接缝、人物比例、动作力度和地面承托继续列入后续精修，最终美术与全量资源未验收。
