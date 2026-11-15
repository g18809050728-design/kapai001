# P01 / N01 动作精修资源

仅由`tools/start_actor_rig_polish.ps1`显式启用，默认main.tscn继续使用原入口。

沿用已核对的`actor-rig-pilot`透明部件，P01新增大腿/小腿/脚踝绑定与连续权重网格，N01主体加入网格形变；独立待机、错峰动作及混合由version 2的rig.json描述。source.json保存实际使用纹理的路径与hash。本批没有调用图像API新增图片。

重建描述文件：`python tools/build_actor_motion_polish.py`。构建脚本只写本目录的rig/source，不覆盖上一版纹理或rig。实施与实渲证据见[精修记录](../../../docs/plans/2026-11-14-actor-motion-polish-design.md)。最终用户美术评审尚未完成。
