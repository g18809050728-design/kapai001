"""Reuse the exact-input Godot runner with a fresh task evidence root."""
import argparse
from datetime import datetime, timezone
import json
import platform
import re
import subprocess
import time
from pathlib import Path
import verify_character_integration as runner

runner.EVIDENCE=Path(__file__).resolve().parents[1]/'artifacts/verification/actor-lin-polish-20261115'
original=runner.inputs

def inputs():
    import hashlib
    result=original()
    root=runner.ROOT
    for name in ['build_actor_lin_polish.py','render_lin_polish_probe.gd','render_lin_character_art.gd','verify_lin_polish.py','run_lin_polish.gd']:
        p=root/'tools'/name
        if p.is_file(): result[p.relative_to(root).as_posix()]=hashlib.sha256(p.read_bytes()).hexdigest()
    return result

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('name');parser.add_argument('arguments',nargs=argparse.REMAINDER)
    args=parser.parse_args()
    arguments=args.arguments[1:] if args.arguments[:1]==['--'] else args.arguments
    prefix=runner.EVIDENCE/args.name; path=prefix.with_suffix('.run.json')
    if path.exists():raise SystemExit('Use a fresh evidence name')
    before=inputs();start=time.perf_counter();started=datetime.now(timezone.utc).isoformat()
    command=[str(runner.ENGINE),'--path',str(runner.ROOT),*arguments]
    with prefix.with_suffix('.stdout.txt').open('wb') as out,prefix.with_suffix('.stderr.txt').open('wb') as err:
        result=subprocess.run(command,cwd=runner.ROOT,stdout=out,stderr=err,timeout=900)
    after=inputs(); logs='\n'.join(prefix.with_suffix(s).read_text(encoding='utf-8',errors='replace') for s in ['.stdout.txt','.stderr.txt'])
    changed=[p for p in sorted(set(before)|set(after)) if before.get(p)!=after.get(p)]
    allowed={'assets/art/characters/P01/neutral.png','assets/art/characters/P01/portrait.png','assets/art/characters/source.json'} if 'res://tools/render_lin_character_art.gd' in arguments else set()
    unexpected=[p for p in changed if p not in allowed]
    errors=len(re.findall(r'(?m)^(?:SCRIPT ERROR:|ERROR:)',logs))
    record={'command':command,'started_utc':started,'seconds':time.perf_counter()-start,'exit_code':result.returncode,
       'engine_errors':errors,'os':platform.platform(),'inputs_before':before,'inputs_after':after,
       'changed_during_run':changed,'unexpected_changes':unexpected}
    path.write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
    prefix.with_suffix('.exit_code.txt').write_text(str(result.returncode))
    print('\n'.join(logs.splitlines()[-12:]))
    print(json.dumps({k:v for k,v in record.items() if not k.startswith('inputs')},ensure_ascii=False))
    return result.returncode or bool(errors or unexpected)

if __name__=='__main__':raise SystemExit(main())
