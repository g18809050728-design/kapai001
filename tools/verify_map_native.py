"""Exercise Windows mouse double clicks in an isolated, visible Godot window."""
from __future__ import annotations

import ctypes
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import time

import pyautogui
import win32con
import win32gui


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/verification/map-card-feedback-20261114" / os.environ.get("MAP_NATIVE_BATCH", "native")
ENGINE = Path(os.environ.get("GODOT_BIN", r"F:\GoDot\Godot_v4.7.2-stable_win64_console.exe"))
TITLE = "Campus map native double-click verification"


def write_json(path, value):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(path)


def wait_state(predicate, timeout=15):
    end = time.monotonic() + timeout
    latest = None
    while time.monotonic() < end:
        try:
            latest = json.loads((OUT / "state.json").read_text(encoding="utf-8"))
            if predicate(latest):
                return latest
        except (OSError, ValueError):
            pass
        time.sleep(.05)
    raise AssertionError(f"Native state timed out: {latest}")


def window():
    handle = win32gui.FindWindow(None, TITLE)
    assert handle, "The isolated verification window must exist"
    win32gui.ShowWindow(handle, win32con.SW_RESTORE)
    win32gui.SetWindowPos(handle, win32con.HWND_TOPMOST, 0, 0, 0, 0,
                         win32con.SWP_NOMOVE | win32con.SWP_NOSIZE | win32con.SWP_SHOWWINDOW)
    try:
        win32gui.SetForegroundWindow(handle)
    except Exception:
        pass
    if win32gui.GetForegroundWindow() != handle:
        # A title-bar click focuses only this known test window.
        left, top, right, _ = win32gui.GetWindowRect(handle)
        assert win32gui.WindowFromPoint(((left + right) // 2, top + 12)) == handle
        pyautogui.click((left + right) // 2, top + 12)
    return handle


def coordinates(state, kind="stamp", unavailable=False):
    handle = window()
    point = state["unavailable"]["point"][kind] if unavailable else state["point"][kind]
    position = win32gui.ClientToScreen(handle, tuple(round(v) for v in point))
    hit = win32gui.WindowFromPoint(position)
    assert hit == handle or win32gui.IsChild(handle, hit), f"Mouse target must belong to the isolated game: {position=}, {handle=}, hit={hit}, title={win32gui.GetWindowText(hit)!r}, client={win32gui.GetClientRect(handle)}, window={win32gui.GetWindowRect(handle)}, foreground={win32gui.GetForegroundWindow()}"
    return position


def snapshot(name):
    handle = window()
    left, top = win32gui.ClientToScreen(handle, (0, 0))
    rect = win32gui.GetClientRect(handle)
    pyautogui.screenshot(region=(left, top, rect[2], rect[3])).save(OUT / f"{name}.png")


def main():
    ctypes.windll.user32.SetProcessDPIAware()
    OUT.mkdir(parents=True, exist_ok=True)
    assert not (OUT / "result.json").exists(), "Keep previous verification evidence"
    isolated = OUT / "user_data"
    isolated.mkdir(exist_ok=True)
    command = [str(ENGINE), "--rendering-method", "gl_compatibility", "--position", "60,60", "--path", str(ROOT), "--script", "tools/capture_map_native.gd"]
    env = dict(os.environ, APPDATA=str(isolated), LOCALAPPDATA=str(isolated), PYTHONUTF8="1", MAP_NATIVE_OUT="res://"+OUT.relative_to(ROOT).as_posix())
    inputs = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
              for folder in ["src", "tests", "data"] for p in (ROOT / folder).rglob("*") if p.is_file()}
    for relative in ["project.godot", "tools/capture_map_native.gd", "tools/verify_map_native.py"]:
        inputs[relative] = hashlib.sha256((ROOT / relative).read_bytes()).hexdigest()
    write_json(OUT / "input_hashes.json", inputs)
    write_json(OUT / "environment.json", {"started_utc":datetime.now(timezone.utc).isoformat(), "os":platform.platform(), "python":sys.version, "command":command, "isolated_appdata":str(isolated), "double_click_interval_ms":ctypes.windll.user32.GetDoubleClickTime(), "input":"Windows mouse via PyAutoGUI; no injected Godot double_click flags"})
    results, failures = [], []
    sequence = 0
    pyautogui.PAUSE = .08
    process = None

    def reset(width, height, scale):
        nonlocal sequence
        sequence += 1
        write_json(OUT / "request.json", {"sequence":sequence,"width":width,"height":height,"text_scale":scale,"action":"reset"})
        state = wait_state(lambda s: s["sequence"] == sequence and s["screen"] == "map" and "point" in s)
        assert state["text_scale"] == scale / 100
        time.sleep(.15)
        return state

    try:
        with (OUT / "stdout.txt").open("wb") as stdout, (OUT / "stderr.txt").open("wb") as stderr:
            process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=stdout, stderr=stderr, creationflags=subprocess.CREATE_NO_WINDOW)
            for width, height in [(1280,800), (960,600)]:
                for scale in [100,125,150]:
                    for kind in ["stamp","caption"]:
                        label = f"{width}-{scale}-{kind}"
                        initial = reset(width,height,scale)
                        position = coordinates(initial,kind)
                        pyautogui.click(*position,button="right")
                        time.sleep(.12)
                        right = wait_state(lambda s: s["sequence"] == sequence and len(s["events"]) >= 2)
                        assert right["revision_delta"] == 0 and right["fingerprint_unchanged"] and right["selected"] == "", f"right-click cannot select or enter: {label}"
                        pyautogui.click(*position)
                        selected = wait_state(lambda s: s["sequence"] == sequence and s.get("selected") == s["target"])
                        assert selected["revision_delta"] == 0 and selected["fingerprint_unchanged"], f"single click is read only: {label}"
                        assert selected["point"] == initial["point"] and selected["scroll"] == initial["scroll"] and selected["enter_enabled"], f"single click preserves real target and scroll: {label}"
                        snapshot("selected-"+label)
                        # A separate ordinary click after the OS double-click interval.
                        time.sleep(ctypes.windll.user32.GetDoubleClickTime()/1000+.25)
                        pyautogui.click(*position)
                        repeated = wait_state(lambda s: s["sequence"] == sequence and s["screen"] == "battle")
                        assert repeated["current_node_id"] == repeated["target"] and repeated["revision_delta"] == 1 and len(repeated["submissions"]) == 1, f"slow second click enters once: {label}"
                        presses = [e for e in repeated["events"] if e["button"] == 1 and e["pressed"]]
                        assert len(presses) == 2 and not presses[-1]["double_click"], f"second click must be an ordinary OS click: {label}"
                        assert (presses[-1]["time_usec"]-presses[0]["time_usec"])/1000 > ctypes.windll.user32.GetDoubleClickTime(), "slow click exceeds OS interval"
                        results.append({"case":label+"-slow-repeat","selected":selected,"entered":repeated})
                        # Restart to prove that a genuine double click needs no earlier preselection.
                        initial = reset(width,height,scale)
                        position = coordinates(initial,kind)
                        time.sleep(ctypes.windll.user32.GetDoubleClickTime()/1000+.05)
                        pyautogui.doubleClick(*position, interval=.08)
                        entered = wait_state(lambda s: s["sequence"] == sequence and s["screen"] == "battle")
                        assert entered["current_node_id"] == entered["target"] and entered["revision_delta"] == 1 and len(entered["submissions"]) == 1, f"native double click must enter exactly once: {label}"
                        assert any(e["button"] == 1 and e["pressed"] and e["double_click"] for e in entered["events"]), f"Godot receives the actual OS double-click event: {label}"
                        time.sleep(.15)
                        snapshot("entered-"+label)
                        results.append({"case":label,"single":selected,"double":entered})
                        print(json.dumps({"case":label,"passed":True,"native_double_click":True,"commits":entered["revision_delta"]}),flush=True)
                    initial = reset(width,height,scale)
                    if "unavailable" in initial:
                        position = coordinates(initial, unavailable=True)
                        pyautogui.doubleClick(*position,interval=.08)
                        unavailable = wait_state(lambda s: s["sequence"] == sequence and s.get("selected") == initial["unavailable"]["id"])
                        assert unavailable["screen"] == "map" and unavailable["revision_delta"] == 0 and unavailable["fingerprint_unchanged"] and not unavailable["enter_enabled"], "Native double click on future node only previews"
                        results.append({"case":f"{width}-{scale}-unavailable","state":unavailable})
                    initial = reset(width,height,scale)
                    position = coordinates(initial)
                    pyautogui.moveTo(*position)
                    pyautogui.mouseDown()
                    pyautogui.moveTo(position[0]+90,position[1]-60,duration=.3)
                    pyautogui.mouseUp()
                    time.sleep(.15)
                    dragged = wait_state(lambda s: s["sequence"] == sequence and len(s["events"]) >= 2)
                    assert dragged["screen"] == "map" and dragged["revision_delta"] == 0 and dragged["fingerprint_unchanged"], "Dragging a node cannot enter it"
                    pyautogui.click(*position)
                    selected = wait_state(lambda s: s["sequence"] == sequence and s.get("selected") == s["target"])
                    # Leaving and returning during a second press is still a drag.
                    time.sleep(ctypes.windll.user32.GetDoubleClickTime()/1000+.1)
                    pyautogui.moveTo(*position)
                    pyautogui.mouseDown()
                    pyautogui.moveTo(position[0]+90,position[1]-60,duration=.2)
                    pyautogui.moveTo(*position,duration=.2)
                    pyautogui.mouseUp()
                    time.sleep(.15)
                    sticky = wait_state(lambda s: s["sequence"] == sequence and len(s["events"]) >= 6)
                    assert sticky["screen"] == "map" and sticky["revision_delta"] == 0 and sticky["fingerprint_unchanged"] and sticky["selected"] == sticky["target"], "dragging away and back cannot enter an already selected node"
                    handle = window()
                    confirmation = win32gui.ClientToScreen(handle, tuple(round(v) for v in selected["enter_point"]))
                    assert win32gui.WindowFromPoint(confirmation) == handle
                    pyautogui.click(*confirmation)
                    confirmed = wait_state(lambda s: s["sequence"] == sequence and s["screen"] == "battle")
                    assert confirmed["revision_delta"] == 1 and len(confirmed["submissions"]) == 1, "The existing confirmation button still enters exactly once"
                    results.append({"case":f"{width}-{scale}-drag-confirm","drag":dragged,"confirmed":confirmed})
            write_json(OUT / "request.json", {"sequence":sequence+1,"action":"quit"})
            process.wait(timeout=20)
    except Exception as exc:
        failures.append(str(exc))
        if process and process.poll() is None:
            write_json(OUT / "request.json", {"sequence":sequence+1,"action":"quit"})
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=5)
    errors = (OUT / "stderr.txt").read_text(encoding="utf-8",errors="replace")
    error_count = sum(line.startswith(("ERROR:","SCRIPT ERROR:")) for line in errors.splitlines())
    result = {"cases":results,"failures":failures,"engine_exit_code":process.returncode if process else None,"engine_errors":error_count}
    write_json(OUT / "result.json", result)
    print(json.dumps({"cases":len(results),"failures":failures,"engine_exit_code":result["engine_exit_code"],"engine_errors":error_count},ensure_ascii=False),flush=True)
    return 1 if failures or error_count or result["engine_exit_code"] != 0 else 0


if __name__ == "__main__":
    raise SystemExit(main())
