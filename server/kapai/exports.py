from contextlib import contextmanager
from datetime import datetime, timedelta
from decimal import Decimal
from io import BytesIO
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response
from xlsxwriter import Workbook

from kapai.accounts import limited
from kapai.admin import audit, require_admin
from kapai.feedback import Category, FeedbackFilter, feedback_rows
from kapai.runtime import engine
from kapai.statistics import BEIJING, RecordSource, RecordState, record_rows, stats_scope, stats_snapshot

router = APIRouter()
EXPORT_LIMIT = 5000
MIME = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
Sort = Literal["newest", "oldest"]
CATEGORIES = {"bug": "游戏问题", "suggestion": "改进建议", "other": "其他反馈"}
STATES = {"new": "待处理", "reviewing": "处理中", "resolved": "已解决", "archived": "已归档",
          "active": "待处理与处理中", "all": "全部"}
SOURCES = {"automatic": "自动记录", "adjusted": "已修正", "manual": "人工补录"}
RECORD_STATES = {"included": "计入统计", "excluded": "已移出", "all": "全部"}
DIFFICULTIES = {"relaxed": "轻松", "normal": "标准", "hard": "困难"}
SORTS = {"newest": "从新到旧", "oldest": "从旧到新"}


def beijing(utc):
    return utc + timedelta(hours=8) if utc is not None else None


def label(row, key, labels):
    return labels.get(row[key], row[key])


def checked(rows):
    if len(rows) > EXPORT_LIMIT:
        raise HTTPException(422, "export_too_many_rows")
    return rows


@contextmanager
def export_db(request):
    with engine.connect() as db:
        actor = require_admin(db, request)
    limited(request, "export_xlsx", actor, attempts=12)
    with engine.begin() as db:
        yield db, require_admin(db, request)


def sheet(book, name, headers, widths, rows, *, filters=True):
    page = book.add_worksheet(name)
    head = book.add_format({"bold": True, "font_color": "white", "bg_color": "#24494B", "text_wrap": True})
    date_style = book.add_format({"num_format": "yyyy-mm-dd hh:mm:ss"})
    page.set_row(0, 26)
    page.freeze_panes(1, 0)
    for col, title in enumerate(headers):
        page.set_column(col, col, widths[col])
        page.write_string(0, col, title, head)
    last = 0
    for last, values in enumerate(rows, 1):
        for col, value in enumerate(values):
            if value is None:
                continue
            if isinstance(value, datetime):
                page.write_datetime(last, col, value, date_style)
            elif isinstance(value, (int, Decimal)):
                page.write_number(last, col, value)
            else:
                # All user-controlled values remain strings, never executable cells or hyperlinks.
                page.write_string(last, col, str(value))
    if filters:
        page.autofilter(0, 0, last, len(headers) - 1)


def workbook(kind, sheets, filters):
    now = datetime.now(BEIJING)
    target = BytesIO()
    with Workbook(target, {"in_memory": True, "strings_to_formulas": False, "strings_to_urls": False}) as book:
        for args in sheets:
            sheet(book, *args)
        sheet(book, "筛选与说明", ("项目", "值"), (23, 86),
              [("导出时间（北京时间）", now.replace(tzinfo=None)), *filters], filters=False)
    return Response(target.getvalue(), media_type=MIME, headers={
        "Content-Disposition": f'attachment; filename="kapai-{kind}-{now:%Y%m%d-%H%M%S}.xlsx"',
        "X-Content-Type-Options": "nosniff",
    })


def dimension_filters(scope):
    return [("开始日期（北京时间）", beijing(scope["start"]).date().isoformat()),
            ("结束日期（北京时间）", (beijing(scope["end"]) - timedelta(days=1)).date().isoformat()),
            ("游戏版本", scope["version"] or "全部"), ("角色", scope["character"] or "全部"),
            ("难度", label(scope, "difficulty", DIFFICULTIES) or "全部")]


@router.get("/admin/exports/feedback")
def export_feedback(request: Request, category: Category | None = None, q: str = Query("", max_length=100),
                    state: FeedbackFilter = "all", sort: Sort = "newest"):
    with export_db(request) as (db, actor):
        rows = checked(feedback_rows(db, category, q, state, sort, EXPORT_LIMIT + 1))
        audit(db, actor, "export.feedback")
    values = ((r["feedback_id"], beijing(r["created_at"]), r["nickname"], label(r, "category", CATEGORIES),
               label(r, "status", STATES), r["build_version"], r["title"], r["description"], r["note"],
               r["screenshot_count"], beijing(r["updated_at"])) for r in rows)
    return workbook("feedback", [("玩家反馈", ("反馈编号", "提交时间（北京时间）", "玩家昵称", "类型", "状态", "游戏版本",
                     "标题", "原始正文", "内部备注", "截图数量", "上次处理（北京时间）"),
                     (39, 26, 18, 16, 14, 24, 35, 64, 46, 13, 26), values)],
                    [("关键词", q.strip()), ("类型", CATEGORIES.get(category, "全部")), ("状态", STATES[state]),
                     ("排序", SORTS[sort]), ("记录数", len(rows)), ("截图", "只导出数量，不包含图片。")])


@router.get("/admin/exports/records")
def export_records(request: Request, scope: dict = Depends(stats_scope), q: str = Query("", max_length=100),
                   source: RecordSource = "", state: RecordState = "included", sort: Sort = "newest"):
    with export_db(request) as (db, actor):
        rows = checked(record_rows(db, scope, q, source, state, sort, EXPORT_LIMIT + 1))
        audit(db, actor, "export.records")
    values = ((r["record_id"], beijing(r["started_at"]), r["nickname"], r["game_version"], r["character_id"],
               label(r, "difficulty", DIFFICULTIES), "是" if r["first_battle"] else "否", "是" if r["finished"] else "否",
               label(r, "source", SOURCES), "已移出" if r["excluded"] else "计入统计", r["reason"]) for r in rows)
    return workbook("records", [("对局明细", ("记录编号", "开局时间（北京时间）", "玩家昵称", "游戏版本", "角色", "难度",
                     "首战完成", "整局结算", "来源", "统计状态", "操作理由"), (39, 26, 18, 25, 12, 12, 13, 13, 14, 14, 50), values)],
                    [*dimension_filters(scope), ("关键词", q.strip()), ("来源", SOURCES.get(source, "全部")),
                     ("状态", RECORD_STATES[state]), ("排序", SORTS[sort]), ("记录数", len(rows))])


@router.get("/admin/exports/stats")
def export_stats(request: Request, scope: dict = Depends(stats_scope)):
    with export_db(request) as (db, actor):
        snapshot = stats_snapshot(db, scope)
        audit(db, actor, "export.stats")
    versions = checked([r for r in snapshot["activity"] if r["game_version"] is not None])
    totals = next((r for r in snapshot["activity"] if r["game_version"] is None), {})
    metrics = [("累计注册账号", snapshot["registered"]), ("区间独立游客浏览器", snapshot["visitors"])]
    metrics += [(title, totals.get(key) or 0) for title, key in (("开局账号", "accounts"), ("开局", "started"),
                ("完成首战", "first_battles"), ("完成整局", "finished"), ("人工补录", "manual"))]
    rows = ((r["game_version"], r["accounts"], r["started"], r["first_battles"], r["finished"], r["manual"]) for r in versions)
    return workbook("stats", [("统计概览", ("指标", "数值"), (28, 16), metrics),
                    ("各版本对局", ("游戏版本", "开局账号", "开局", "完成首战", "完成整局", "人工补录"),
                     (29, 16, 14, 16, 16, 16), rows)],
                    [*dimension_filters(scope), ("统计口径", "累计注册不受筛选影响；独立游客浏览器只受日期影响。"),
                     ("人工补录", "只计对局，不增加开局账号。")])
