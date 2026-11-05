# 原型音效

`sfx/*.wav` 是本地程序化合成音效，由 `tools/generate_sfx.py` 确定性生成，不含外部采样或第三方旋律。格式为 44.1 kHz、16-bit、单声道 WAV，保留现有 18 个资源 ID。

2026-11-05 按 FY-AUD-003 重做为柔和的纸张、木质与低频短音，使用低通噪声、正弦音和渐入渐出包络。线性峰值为 0.025–0.17，18 条的峰值及 RMS 均低于替换前；首尾采样为零、无削波、重复合成字节一致。生成命令为 `python tools/generate_sfx.py`，逐文件参数及 SHA256 见 [manifest](sfx/manifest.json)。

播放策略在 `src/ui/audio_manager.gd`：悬停与普通状态变化静音，同 ID 180ms 冷却，普通战斗反馈组 160ms、UI 组 80ms；重要提示后为其他反馈保留 220ms 安静窗口。SFX 播放槽从 8 个减至 3 个；选择、胜利、失败提示会停止较低优先级的 SFX，避免连续抽弃牌与状态事件叠加。DDL 剩余 >3 / ≤3 / ≤1 时仍使用 1.0/0.8/0.6 音高。

Master/Music/Ambience/SFX/UI 五路音量及静音保留设置页持久化，默认 100/70/50/80/70%；不重置个人设置。脱树停止播放并清缓存，战斗音频仍由事件演出单点消费。

替换前的 WAV 与生成器保存在 [audio-before.zip](../../artifacts/verification/ui-followup-20261105/audio-before.zip)，解码、峰值/RMS、包络、确定性及 hash 检查见 [asset-verification.json](../../artifacts/verification/ui-followup-20261105/asset-verification.json)。真实事件节流测试和运行证据见[本轮记录](../../docs/UI追加反馈实施记录_20261105.md)。机器指标不代表已经完成人工听感验收。

Music/Ambience 尚无素材与循环播放器；音乐、环境循环、正式混音和最终人工听感仍待完成。
