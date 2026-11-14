"""Real Windows input against the isolated known reference-UI game window."""
from datetime import datetime, timezone
import ctypes
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
import traceback

import pyautogui
import win32gui
import verify_map_native as native

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/verification/menu-relic-feedback-20261114" / os.environ.get("REFERENCE_NATIVE_BATCH", "native")


def click(state, uid):
    point = state["points"][uid]
    assert not point["disabled"], uid
    handle = native.window()
    target = win32gui.ClientToScreen(handle, (round(point["x"]), round(point["y"])))
    hit = win32gui.WindowFromPoint(target)
    assert hit == handle or win32gui.IsChild(handle, hit), (uid, target)
    pyautogui.click(*target)


def write_request(value):
    # Godot briefly opens the request file while polling. Windows may deny
    # atomic replacement during that read; retry this transport operation.
    for attempt in range(40):
        try:
            native.write_json(OUT / "request.json", value)
            return
        except PermissionError:
            if attempt == 39:
                raise
            time.sleep(.025)


def main():
    ctypes.windll.user32.SetProcessDPIAware()
    OUT.mkdir(parents=True, exist_ok=True)
    assert not (OUT / "result.json").exists(), "Keep earlier native evidence"
    native.OUT, native.TITLE = OUT, "Campus reference native verification"
    isolated = OUT / "user_data"
    isolated.mkdir(exist_ok=True)
    env = dict(os.environ, APPDATA=str(isolated), LOCALAPPDATA=str(isolated), REFERENCE_NATIVE_OUT=str(OUT))
    command = [str(native.ENGINE), "--rendering-method", "gl_compatibility", "--path", str(ROOT), "--script", "tools/capture_reference_native.gd"]
    sources = [p for folder in ["src", "tests", "data"] for p in (ROOT / folder).rglob("*") if p.is_file()]
    sources += [ROOT / p for p in ["project.godot", "tools/capture_reference_native.gd", "tools/verify_reference_native.py", "tools/verify_map_native.py"]]
    inputs = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    native.write_json(OUT / "input_hashes.json", inputs)
    cases, failures = [], []
    with (OUT / "stdout.txt").open("wb") as stdout, (OUT / "stderr.txt").open("wb") as stderr:
        process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=stdout, stderr=stderr, creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            for sequence, (width, height, scale, battle) in enumerate((w, h, s, b) for w, h in [(1280, 800), (960, 600)] for s in [100, 125, 150] for b in [False, True]):
                write_request(dict(sequence=sequence, width=width, height=height, scale=scale, battle=battle))
                state = native.wait_state(lambda value: value.get("sequence") == sequence and value.get("ready"))
                prefix = "battle" if battle else "flow"
                label = f'{"battle" if battle else "map"}-{width}-{scale}'
                # Use the English layout only in this test window's thread, so
                # the user's Chinese IME does not turn search typing into a
                # composition that consumes the first Escape before Godot.
                handle = native.window()
                english = ctypes.windll.user32.LoadKeyboardLayoutW("00000409", 0)
                ctypes.windll.user32.PostMessageW(handle, 0x0050, 0, english)
                time.sleep(.1)
                click(state, f'{prefix}:options')
                state = native.wait_state(lambda value: value["menu"])
                time.sleep(.25)
                native.snapshot(label + "-menu")
                click(state, "battle:rules:caption" if battle else "flow:help:caption")
                time.sleep(.25)
                native.snapshot(label + "-after-help")
                state = native.wait_state(lambda value: value["reference"] == "rules")
                pyautogui.press("e")
                pyautogui.press("1")
                native.snapshot(label + "-rules")
                pyautogui.press("esc")
                state = native.wait_state(lambda value: not value["reference"])
                click(state, "toolbar:relic:2")
                state = native.wait_state(lambda value: value["reference"] == "relics")
                assert state["selected_relic"], "Direct slot selects equipment"
                native.snapshot(label + "-relics")
                click(state, "reference:log")
                state = native.wait_state(lambda value: value["reference"] == "log")
                click(state, "reference:search")
                pyautogui.write("DDL", .1)
                state = native.wait_state(lambda value: value.get("search_text", "").upper() == "DDL")
                native.snapshot(label + "-log-search")
                pyautogui.press("esc")
                state = native.wait_state(lambda value: not value["reference"])
                assert state["unchanged"], "Real browsing, search and background hotkeys preserve state"
                assert len(state["events"]) >= 8, "Godot received native pointer events"
                cases.append(dict(label=label, events=state["events"], unchanged=state["unchanged"]))
                print("PASS", label, flush=True)
            write_request(dict(sequence=1000, action="quit"))
            code = process.wait(timeout=15)
        except Exception as error:
            failures.append(repr(error))
            (OUT / "driver-error.txt").write_text(traceback.format_exc(), encoding="utf-8")
            process.terminate()
            code = process.wait(timeout=10)
    errors = (OUT / "stderr.txt").read_text(encoding="utf-8", errors="replace")
    engine_errors = sum(line.startswith(("ERROR:", "SCRIPT ERROR:")) for line in errors.splitlines())
    after = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources if p.exists()}
    native.write_json(OUT / "result.json", dict(utc=datetime.now(timezone.utc).isoformat(), command=command, isolated_appdata=str(isolated), cases=cases, failures=failures, exit_code=code, engine_errors=engine_errors, hashes=after, changed_during_run=[p for p in inputs if inputs[p] != after.get(p)]))
    print(json.dumps(dict(cases=len(cases), failures=failures, exit_code=code, engine_errors=engine_errors)))
    return int(bool(failures) or code != 0 or engine_errors != 0)


if __name__ == "__main__":
    raise SystemExit(main())
