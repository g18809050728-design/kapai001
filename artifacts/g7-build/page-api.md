# UiFlowPage 页面 API

`src/ui/page_flow.gd` 提供 `UiFlowPage`，由 shell 设置 `screen` 后调用 `render(view)`。
局流程页面使用契约稳定 UID：`node:<id>`、`reward:<item>:skip/claim`、`shop:buy:<id>`、
`event:<option>`、`rest:take:<option>[:<card>]`、`summary:menu/retry`、`map:save/menu/abandon`。

页面不访问规则服务或存档；候选、替换饰品和休息目标只保存在本地选择字典，规则草稿交给 shell 的 preview 门控。
`setup:seed_random` 仅生成展示用十进制时间种子，不触碰领域随机流。资源统一经过 `UiStyle.texture`，RGB 人物图作为插画卡使用。

事件的 `option_id=leave` 特例 UID 为 `event:option:leave`，避免与节点继续按钮 `event:leave` 重复。
设置页 `settings:save` 手动保存当前学期，`settings:apply` 保存设置。
