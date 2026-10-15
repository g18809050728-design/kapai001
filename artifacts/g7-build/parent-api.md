# 当前 G7 任务及父代理接口（2026-10-15）

用户已生成并切分图片并要求“接下来进行下一步”，前文明确允许 subagent 提速。父代理已读 agent.md / 根计划并先用 CodeGraph（不支持 gd）。G6 核对代理 g6_spec 已实际 view_image 六个 contact sheet：46 切片可用于 G7，少量贴边/拟字细节有记录；正复制选定图到 assets/art/g6-v1 并补 selection。G6 readiness 已确认，可立即写 G7，**不要因 selection 写入比消息慢而暂停**。G7 设计已落盘 动作或者图片描述/G7界面与交互设计.md。

## 所有代理现在继续的任务

- g4_rewards：写 src/ui/page_flow.gd，class_name UiFlowPage extends UiPage，screen:String 由 shell 赋值。实现 menu/setup/map/reward/shop/event/rest/summary/settings/battle_entry。仅负责该文件。按契约按钮 uid/动作草稿及实时 Callable 候选门控。seed_random 本地生成十进制字符串（用 Time.get_unix_time_from_system 整数即可；不改领域 RNG），更新 LineEdit，不交 shell。不运行 Godot 导入。
- g6_atlas_tool：写 src/ui/battle_screen.gd/.tscn、src/ui/battle/battle_event_animator.gd（必要组件可同目录）。class_name BattleScreen extends UiPage，按契约手牌/任务/单位/待选/保留/公开牌堆/规则/日志/动画。父将补 GameSession 非出牌 preview，勿因此暂停。不要修改父文件/测试/规则。consume_events(events:Array,run_id:String,revision:int)；preview_callback:Callable 由 shell 注入，返回 ActionPreview 或 null；animation_enabled:bool；is_locked/lock_snapshot/draw_pile_card_ids。BattleView 由 shell 注入 pending_choice:ChoiceRequest、event_log、run_id、revision、can_save。不得重算费用，父将提供 hand.effective_cost/effective_vitality_cost/face/playable。
- g5_docs：只写 tests/run_ui_tests.gd、tests/suites/test_ui_shell_pages.gd、tests/suites/test_ui_battle_choice.gd。真实 Button.pressed + GameSession + 隔离存储/fixture 跑一学期（真实 BattleEngine），生产开局、禁用无副作用、保存继续、待选锁/确认/取消、动画 A/B。公开API见下。不要运行Godot或改旧run_tests/业务文件。与battle/page agent自行对齐UID。
- g6_spec：完成 G6 图片核对/selection/selected图及G6记录，注意不要用全局数字replace破坏README（另代理报告数字异常，请自查）。不写 G7。
- 父：UiPage、UiStyle、GameShell、入口、规则预览接线、运行验证、文档状态。

## 基类 API（已实现 src/ui/ui_page.gd）

UiPage extends Control，var view:Dictionary、body:VBoxContainer。

```
signal action_requested(draft:Dictionary)
signal local_selection_changed(selection:Dictionary)
reset_page(title:String,subtitle:String="")->VBoxContainer
add_button(parent:Node,uid:String,label:String,draft:Variant={},local_callback:Callable=Callable())->Button
add_text(parent:Node,text:String,size:int=18,color:Color=UiStyle.INK)->Label
add_art(parent:Node,id:String,size:Vector2)->TextureRect
add_row(parent:Node)->HBoxContainer
add_panel(parent:Node)->VBoxContainer
build_action()->Dictionary # 最近草稿，不能override成不同参数
press(uid)->bool / action_uids / action_draft / apply_gating / button_disabled / button_reason / button_text / button_uids
```

reset_page 清理旧子节点/按钮表/最近草稿，创建 ScrollContainer+margin+body，标题/副标题在body。请 render(data) 中先 view=data.duplicate(true)，再 reset_page。local_selection_changed 发后 shell 重新 preview 门控，不要重新全局路由。
add_button draft 可为 Dictionary 或 Callable；有非 ui.* type 就登记规则操作，shell 统一 preview。local_callback 只更新本地选择，无draft时不会自动发请求。按钮 disabled 时 press 返回 false，启用时真正 emit pressed。

UiStyle 静态API（父在实现）：label(id:String)->String，texture(id:String)->Texture2D，describe_effects(effects:Array)->String；颜色 INK/PAPER/MUTED/GREEN/GOLD/RED。所有图片为RGB实底，用插画卡不当透明立绘。

## GameShell API

GameShell extends Control；var session:GameSession 可在add_child前注入，var page:UiPage；refresh()->void，show_screen(screen:String)->void（空字符串按会话路由），press(uid)->bool，submit_action(draft:Dictionary)。shell _ready 若session为空创建，否则使用注入session。初始menu。

局外视图：menu {has_active_session,has_save,save_error,profile,can_start_new}；setup {characters,difficulties,manifests,default_seed}；settings {settings:{autosave},save_meta,backup_meta,can_restore,seed,difficulty}。局内传 SessionView.run，summary 额外 terminal_summary/profile_commit_status。battle 传 SessionView.battle 并注入上文Session字段。

导航 ui.menu/new_run/continue/settings/back/save/save_settings/restore_backup/retry/quit；开局 ui.start_run payload {character_id,difficulty,manifest_id,seed}；设置 ui.save_settings payload {autosave:bool}。ui.quit 先 save_and_exit；菜单只隐藏不释放内存局。

## 禁止误判

当前消息接口若正文为空，不要回到旧G5/G6任务，不要停止：以此共享文件为当前任务。父已批准按用户本轮意图实施 G7。状态可在此目录用小文件回复。
