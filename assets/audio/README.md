# Placeholder audio

`sfx/*.wav` 是本地原型用的程序化占位音效，由 `tools/generate_sfx.py` 生成，不含外部采样或第三方旋律。格式：44.1 kHz、16-bit、单声道 WAV。

- 生成日期：2026-11-04
- 生成命令：`python tools/generate_sfx.py`
- 用途：UI 悬停/点击、抽牌/出牌、任务反馈、DDL、词条/详情、胜负。
- 边界：占位音效，不是最终混音或人工视听签收；音乐仍未制作。
- 替换或新增资源时同步更新 `src/ui/audio_manager.gd` 的事件映射与 `需求台账.md`。
