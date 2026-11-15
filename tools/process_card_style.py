"""Crop, inspect, install and audit this card-art batch; never calls an image API."""
import argparse
from datetime import datetime, timezone
import hashlib
import html
import json
from pathlib import Path
import shutil
import zipfile

from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/card-style-20261115'
EVIDENCE=ROOT/'artifacts/verification/card-style-20261115'
FONT=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',22)


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def read(p):
    return json.loads(p.read_text(encoding='utf-8-sig'))


def write(p,value):
    p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


def crop():
    layout=read(OUT/'layout.json')
    names={e['card_id']:e for e in read(OUT/'catalog.json')['entries']}
    reviews=read(OUT/'visual-review.json') if (OUT/'visual-review.json').exists() else {}
    records=[]
    for batch in layout['batches']:
        src=ROOT/batch['source_file']
        if not src.exists():
            continue
        request=read(OUT/(batch['batch_id']+'.api.json'))
        if request['exit_code']!=0 or request['output_sha256']!=sha(src):
            raise ValueError('Missing successful matching request record: '+str(src))
        review=reviews.get(batch['batch_id'],{})
        reviewed=review.get('source_sha256')==sha(src) and bool(review.get('approved_for_game'))
        with Image.open(src) as atlas:
            atlas.load()
            assert atlas.size==(1024,1536),(src,atlas.size)
            contact=Image.new('RGB',(1024,1664),'#111e28')
            draw=ImageDraw.Draw(contact)
            for slot in batch['slots']:
                cid=slot['card_id']
                if not cid:
                    continue
                image=atlas.crop(slot['crop']).convert('RGB')
                assert image.size==(480,360)
                dst=OUT/'crops'/(cid+'.png'); dst.parent.mkdir(parents=True,exist_ok=True)
                image.save(dst)
                x=(slot['column']-1)*512; y=(slot['row']-1)*416
                contact.paste(image,(x+16,y+12))
                draw.text((x+17,y+377),cid+'  '+names[cid]['name'],font=FONT,fill='#f7e7c7')
                records.append({
                    'asset_id':cid,'requirement_id':'UIR-074','version':3,'name':names[cid]['name'],
                    'owner':names[cid]['owner'],'scene':names[cid]['scene'],
                    'generated':True,'selected':False,'status':'reviewed_candidate' if reviewed else 'generated_candidate',
                    'batch_id':batch['batch_id'],'prompt_file':batch['prompt_file'],'prompt_sha256':batch['prompt_sha256'],
                    'provider':batch['provider'],'model':batch['model'],'api_mode':'bundled imagegen CLI edit; uploaded formal identity/linework reference; n=1',
                    'quality':'medium','requested_size':[1024,1536],'actual_atlas_size':list(atlas.size),
                    'source_file':batch['source_file'],'source_sha256':sha(src),'slot':slot,
                    'processing':'Pillow integer crop to RGB PNG; no resampling or recoloring','size':list(image.size),
                    'candidate_output':dst.relative_to(ROOT).as_posix(),'output':f'assets/cards/v3/{cid}.png','sha256':sha(dst),
                    'reference_file':batch['reference_image'],'reference_sha256':batch['reference_sha256'],
                    'reference_mode':'actually uploaded current formal character identity and painted linework',
                    'ai_visual_review':review if reviewed else None,'human_acceptance':'pending user review',
                    'license_review':'provider terms not independently verified','seed':None,'cost':'not returned',
                    'recorded_utc':datetime.now(timezone.utc).isoformat(),
                })
            cp=OUT/'contacts'/(batch['batch_id']+'.jpg'); cp.parent.mkdir(parents=True,exist_ok=True)
            contact.save(cp,quality=94)
    hashes={}
    duplicates=[]
    for rec in records:
        if rec['sha256'] in hashes:
            duplicates.append([hashes[rec['sha256']],rec['asset_id']])
        hashes[rec['sha256']]=rec['asset_id']
    write(OUT/'asset-manifest.json',{'requirement_id':'UIR-074','count':len(records),'assets':records,'duplicates':duplicates,
                                    'planned_atlases':22,'api_before':121,'api_successful':len({r['batch_id'] for r in records}),
                                    'human_acceptance':'pending','installed':False})
    print(json.dumps({'cropped':len(records),'atlases':len({r['batch_id'] for r in records}),'duplicates':duplicates},ensure_ascii=False))


def install():
    manifest=read(OUT/'asset-manifest.json')
    expected=set(read(ROOT/'data/four_year/manifests/campus_four_year.json')['enabled']['card'])
    assets=manifest['assets']
    assert len(assets)==len(expected)==174 and {a['asset_id'] for a in assets}==expected
    assert not manifest['duplicates']
    assert all(a['ai_visual_review'] and a['ai_visual_review']['approved_for_game'] for a in assets)
    baseline=read(EVIDENCE/'baseline.json')
    for name,digest in baseline['protected'].items():
        assert sha(ROOT/name)==digest,'Protected input changed: '+name
    for name,digest in baseline['old_art'].items():
        assert sha(ROOT/name)==digest,'Installed old art changed before this batch install: '+name
    for a in assets:
        assert sha(ROOT/a['candidate_output'])==a['sha256']
        assert sha(ROOT/a['prompt_file'])==a['prompt_sha256']
        assert sha(ROOT/a['reference_file'])==a['reference_sha256']
    for a in assets:
        shutil.copyfile(ROOT/a['candidate_output'],ROOT/a['output'])
        a.update(selected=True,status='selected_for_game',previous_sha256=baseline['old_art'][a['output']])
    manifest.update(installed=True,selected_count=174,generated_count=174,
                    installed_utc=datetime.now(timezone.utc).isoformat())
    write(OUT/'asset-manifest.json',manifest)
    write(ROOT/'docs/art/card-art-assets-v3.json',manifest)
    print('Installed 174 reviewed illustrations; shared runtime source/index unchanged.')


def review_page():
    assets=read(OUT/'asset-manifest.json')['assets']
    entries={e['card_id']:e for e in read(OUT/'catalog.json')['entries']}
    review=EVIDENCE/'review'; review.mkdir(parents=True,exist_ok=True)
    old_dir=review/'before'; old_dir.mkdir(exist_ok=True)
    with zipfile.ZipFile(EVIDENCE/'before.zip') as archive:
        for a in assets:
            p=old_dir/(a['asset_id']+'.png')
            if not p.exists(): p.write_bytes(archive.read(a['output']))
    cards=[]
    for a in assets:
        e=entries[a['asset_id']]; cid=a['asset_id']
        new='../../../../'+a['candidate_output']
        actual=f'../render-01/faces/{cid}.png'
        game_link=f'<button onclick="toggleGame(this)">游戏卡面</button><a target="_blank" href="../render-01/detail-{cid}.png">实际详情</a>' if (EVIDENCE/'render-01/faces'/(cid+'.png')).exists() else ''
        cards.append(f'''<article data-owner="{a['owner']}" data-search="{html.escape(cid+' '+a['name']+' '+e['group'])}">
<div class="art"><img loading="lazy" src="{new}" alt="{html.escape(a['name'])}" data-new="{new}" data-old="before/{cid}.png" data-game="{actual}" onclick="zoom(this)"></div>
<h2>{html.escape(a['name'])}<small>{cid}</small></h2><p>{html.escape(e['base_text'])}</p>
<div class="choices"><button onclick="toggle(this,false)">新插画</button><button onclick="toggle(this,true)">改前</button>{game_link}<a href="{new}" target="_blank">查看原尺寸</a></div></article>''')
    batches=read(OUT/'layout.json')['batches']
    batchlinks=' '.join(f'<a target="_blank" href="../../../../output/imagegen/card-style-20261115/contacts/{b["batch_id"]}.jpg">{b["batch_id"]}</a>' for b in batches if (ROOT/b['source_file']).exists())
    page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>174卡 · 角色风格重绘</title><style>
*{box-sizing:border-box}body{background:#0d1821;color:#e6ddc9;font:16px/1.6 "Microsoft YaHei",sans-serif;margin:0}header{padding:28px 4vw;background:#13252d;position:sticky;top:0;z-index:2;border-bottom:1px solid #5c695f}h1{margin:0;font-size:26px}header p{margin:5px 0 14px;color:#bfcac8}nav{display:flex;gap:8px;flex-wrap:wrap}button,input{font:inherit;border:1px solid #6c817b;border-radius:6px;color:#f2e7d1;background:#233d43;min-height:44px;padding:7px 14px;cursor:pointer}input{width:240px;background:#102329}a{color:#afdbc9}main{padding:24px 4vw;display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:20px}article{background:#182b33;border:1px solid #475c5b;border-radius:10px;overflow:hidden}.art{aspect-ratio:4/3;background:#192b32}.art img{width:100%;height:100%;object-fit:contain;cursor:zoom-in}h2{font-size:20px;margin:12px 16px 0}small{display:block;color:#b3c5c5;font-size:12px;font-weight:400}article p{margin:10px 16px;font-size:14px;min-height:44px}.choices{display:flex;gap:8px;align-items:center;margin:12px 14px;flex-wrap:wrap}.choices button{font-size:13px;padding:5px 9px}.choices a{font-size:12px}details{margin:8px 4vw}details a{margin:5px;display:inline-block}dialog{background:#12252d;color:white;border:1px solid #6b7b70;max-width:95vw;max-height:95vh}dialog img{max-width:85vw;max-height:80vh;display:block}dialog::backdrop{background:#000c}.hidden{display:none}footer{padding:22px 4vw;color:#abbcba}
</style><header><h1>174卡 · 角色风格与牌名插画</h1><p>四人各40张＋公共12＋衍生2。点图放大，逐牌可切换改前；正式游戏内从“图鉴”查看原卡框与规则。AI观察与用户最终审美签收分开。</p><nav><button onclick="filter('')">全部</button><button onclick="filter('P01')">林序 · 调试实践</button><button onclick="filter('P02')">许知微 · 论文研究</button><button onclick="filter('P03')">沈见章 · 证据追问</button><button onclick="filter('P04')">唐以宁 · 小组协作</button><button onclick="filter('C')">公共</button><input placeholder="搜索牌名 / ID" oninput="query=this.value;apply()"><span id="count"></span></nav></header><details><summary>每批8张：带牌名的裁片核对表</summary>'''+batchlinks+'''</details><main>'''+''.join(cards)+'''</main><footer>原件、prompt、实际参考输入、API日志、精确格位与hash保留于 output/imagegen/card-style-20261115/。旧174图保留在改前ZIP。本页展示插画素材；游戏实渲和验证见同级证据目录。</footer><dialog id="zoom"><button onclick="this.parentNode.close()">关闭</button><img></dialog><script>
let owner='',query='';function filter(o){owner=o;apply()}function apply(){let n=0;document.querySelectorAll('article').forEach(a=>{let ok=(!owner||a.dataset.owner===owner)&&a.dataset.search.toLowerCase().includes(query.toLowerCase());a.classList.toggle('hidden',!ok);if(ok)n++});document.querySelector('#count').textContent=n+' 张'}function toggle(b,old){const img=b.closest('article').querySelector('img');img.src=old?img.dataset.old:img.dataset.new}function toggleGame(b){const img=b.closest('article').querySelector('img');img.src=img.dataset.game}function zoom(i){const d=document.querySelector('dialog');d.querySelector('img').src=i.src;d.showModal()}apply();
</script></html>'''
    (review/'index.html').write_text(page,encoding='utf-8')
    print('Review: '+str(review/'index.html'))


def audit():
    baseline=read(EVIDENCE/'baseline.json')
    unexpected=[name for name,digest in baseline['protected'].items() if not (ROOT/name).exists() or sha(ROOT/name)!=digest]
    saves=Path(baseline['saves_root'])
    after={p.relative_to(saves).as_posix():sha(p) for p in saves.rglob('*') if p.is_file()}
    manifest=read(OUT/'asset-manifest.json')
    expected=set(read(ROOT/'data/four_year/manifests/campus_four_year.json')['enabled']['card'])
    manifest_ok=(manifest.get('installed') is True and manifest.get('selected_count')==174
                 and len(manifest['assets'])==174 and {a['asset_id'] for a in manifest['assets']}==expected
                 and all(a.get('selected') for a in manifest['assets'])
                 and sha(OUT/'asset-manifest.json')==sha(ROOT/'docs/art/card-art-assets-v3.json'))
    bad=[]
    provenance_bad=[]
    for a in manifest['assets']:
        p=ROOT/a['output']
        if not p.exists() or sha(p)!=a['sha256']: bad.append(a['asset_id'])
        for file_key,hash_key in [('candidate_output','sha256'),('source_file','source_sha256'),
                                  ('prompt_file','prompt_sha256'),('reference_file','reference_sha256')]:
            p=ROOT/a[file_key]
            if not p.exists() or sha(p)!=a[hash_key]: provenance_bad.append([a['asset_id'],file_key])
    snapshots={}
    with zipfile.ZipFile(EVIDENCE/'before.zip') as archive:
        for name,digest in {**baseline['documents'],**baseline['old_art']}.items():
            snapshots[name]=hashlib.sha256(archive.read(name)).hexdigest()==digest
    doc_prefix={}
    updates_path=EVIDENCE/'document-header-updates.json'
    updates=read(updates_path)['updates'] if updates_path.exists() else []
    assert len(updates)<=1,'Only one explicitly registered plan status-line replacement is allowed'
    for update in updates:
        assert update['path']=='实施计划与验收基线.md'
        assert update['old'].startswith('版本：v1.88｜') and update['new'].startswith('版本：v1.89｜')
        assert all('\n' not in update[key] and '\r' not in update[key] for key in ['old','new'])
    with zipfile.ZipFile(EVIDENCE/'before.zip') as archive:
        for name in baseline['documents']:
            if name.endswith('.md'):
                original=archive.read(name)
                for update in updates:
                    if update['path']==name:
                        old=update['old'].encode('utf-8');new=update['new'].encode('utf-8')
                        assert original.count(old)==1,'Status header must occur exactly once in the original snapshot'
                        original=original.replace(old,new,1)
                doc_prefix[name]=(ROOT/name).read_bytes().startswith(original)
    result={'ok':not unexpected and not bad and not provenance_bad and manifest_ok and after==baseline['saves'] and all(snapshots.values()) and all(doc_prefix.values()),
            'protected_count':len(baseline['protected']),'unexpected_changes':unexpected,
            'saves_count':len(after),'saves_unchanged':after==baseline['saves'],
            'snapshots':snapshots,'historical_markdown_bytes_preserved_except_registered_status_header':doc_prefix,
            'registered_document_header_updates':updates,'installed_manifest_and_provenance_agree':manifest_ok,
            'installed_cards':len(manifest['assets']),'bad_installed_hashes':bad,
            'bad_provenance_hashes':provenance_bad,
            'api_before':121,'api_successful':manifest['api_successful'],'human_acceptance':'pending user review'}
    write(EVIDENCE/'audit.json',result)
    print(json.dumps({k:v for k,v in result.items() if k not in ['snapshots','historical_markdown_bytes_preserved_except_registered_status_header','registered_document_header_updates']},ensure_ascii=False))
    return 0 if result['ok'] else 1


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['crop','install','review','audit'])
    args=parser.parse_args()
    action={'crop':crop,'install':install,'review':review_page,'audit':audit}[args.action]
    raise SystemExit(action() or 0)
