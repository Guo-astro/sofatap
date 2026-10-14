#!/usr/bin/env python3
"""Copy only manifest-listed public store media into a responsive review gallery."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil

from PIL import Image, ImageDraw


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def copy_verified(source, target, expected):
    if digest(source) != expected:
        raise ValueError(f'Output changed since its production receipt: {source.name}')
    target.parent.mkdir(parents=True, exist_ok=True)
    if source.resolve() != target.resolve():
        shutil.copyfile(source, target)
    assert digest(target) == expected


def media_records(entry):
    records = list(entry.get('screenshots', []))
    if entry.get('contactSheet'):
        records.append(entry['contactSheet'])
    if entry.get('preview'):
        records.extend((entry['preview'], entry['preview']['poster']))
    return records


def checked_relative(value):
    relative = Path(value)
    if relative.is_absolute() or '..' in relative.parts or not relative.parts:
        raise ValueError('Unsafe path in existing delivery receipt')
    return relative


def inspect_existing(destination):
    """Refuse unmanaged content before touching the delivery directory."""
    if destination.is_symlink():
        raise ValueError('Delivery destination cannot be a symlink')
    if not destination.exists():
        return {'locales': {}}
    entries = list(destination.rglob('*'))
    if any(path.is_symlink() for path in entries):
        raise ValueError('Existing delivery contains a symlink; use a fresh directory')
    files = {path.relative_to(destination).as_posix() for path in entries if path.is_file()}
    if not files:
        return {'locales': {}}
    receipt_path = destination / 'production-manifest.json'
    if not receipt_path.is_file():
        raise ValueError('Nonempty delivery is not managed by a production manifest; preserve it and use a fresh directory')
    existing = json.loads(receipt_path.read_text())
    if existing.get('brand') != 'Sofatap' or existing.get('version') != 1:
        raise ValueError('Existing delivery manifest is not a supported Sofatap manifest')
    expected = {'index.html', 'README.md', 'production-manifest.json', 'SHA256SUMS'}
    media = []
    for entry in existing.get('locales', {}).values():
        for record in media_records(entry):
            relative = checked_relative(record['file'])
            if relative.parts[0] not in ('screenshots', 'previews', 'contact-sheets'):
                raise ValueError('Unexpected managed media path')
            expected.add(relative.as_posix())
            media.append((destination / relative, record['sha256']))
    for record in existing.get('productionTools', []):
        relative = checked_relative(record['file'])
        if relative.parts[0] != 'tools':
            raise ValueError('Unexpected managed production-tool path')
        expected.add(relative.as_posix())
        media.append((destination / relative, record['sha256']))
    unexpected = files - expected
    if unexpected:
        raise ValueError('Delivery contains unmanifested files; nothing changed. Preserve them and use a fresh directory: ' + ', '.join(sorted(unexpected)))
    for path, expected_hash in media:
        if not path.is_file() or digest(path) != expected_hash:
            raise ValueError('Previously delivered media is missing or changed; nothing changed: ' + path.name)
    return existing


def gallery_item(locale, entry, labels, names):
    result = {'label': labels.get(locale, locale), 'screenshots': {}, 'preview': None, 'contactSheet': entry['contactSheet']['file']}
    for shot in entry['screenshots']:
        size = 'x'.join(str(n) for n in shot['dimensions'])
        state = Path(shot['file']).stem.split('-', 1)[1]
        result['screenshots'].setdefault(size, []).append({'file': shot['file'], 'label': names.get(state, state)})
    if entry.get('preview'):
        result['preview'] = {'file': entry['preview']['file'], 'poster': entry['preview']['poster']['file']}
    return result


HTML = '''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Sofatap · App Store media</title><meta name="color-scheme" content="dark">
<style>
:root{color-scheme:dark;--bg:#091114;--panel:#121e21;--line:#2a413c;--text:#eaf9f1;--muted:#a0b7b0;--mint:#a6efcd}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:16px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}a{color:var(--mint)}button,select{font:inherit}main{max-width:1280px;margin:auto;padding:32px 24px 64px}header{padding:8px 0 26px}.brand{color:var(--mint);font-weight:700;letter-spacing:.01em}.eyebrow{color:var(--muted);font-size:.8rem;letter-spacing:.08em;text-transform:uppercase}h1{font-size:clamp(2rem,5vw,3.75rem);line-height:1.06;margin:12px 0 16px;letter-spacing:-.04em}h2{font-size:1.3rem;margin:0}p{color:var(--muted);max-width:780px}nav{display:flex;align-items:center;flex-wrap:wrap;gap:10px;margin-top:22px}button,select{border:1px solid var(--line);border-radius:12px;background:var(--panel);color:var(--text);padding:10px 14px;min-height:44px}button{cursor:pointer}button[aria-pressed=true]{background:var(--mint);color:var(--bg);border-color:var(--mint)}.section-head{display:flex;align-items:center;justify-content:space-between;gap:16px;flex-wrap:wrap;margin:34px 0 18px}.shots{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:16px}.card{margin:0;background:var(--panel);border:1px solid var(--line);border-radius:16px;overflow:hidden}.card img{display:block;width:100%;height:auto}.card a{display:block;padding:12px 14px;text-decoration:none;font-size:.85rem;border-top:1px solid var(--line)}.card a:hover{background:#233731}.preview{display:grid;grid-template-columns:minmax(240px,390px) 1fr;gap:30px;align-items:start}.preview video{display:block;width:100%;max-height:760px;aspect-ratio:886/1920;background:#000;border:1px solid var(--line);border-radius:18px}.details{padding:4px 0}.download{display:inline-block;border-radius:12px;padding:12px 18px;background:var(--mint);color:var(--bg);text-decoration:none;font-weight:650;margin:10px 10px 10px 0}.secondary{display:inline-block;padding:10px 0;margin-right:20px}.facts{margin:20px 0;padding:18px;border:1px solid var(--line);border-radius:14px;color:var(--muted)}.facts div{padding:3px 0}.fine{font-size:.85rem;color:var(--muted)}footer{margin-top:40px;border-top:1px solid var(--line);padding-top:20px}.empty{display:none}@media(max-width:1000px){.shots{grid-template-columns:repeat(3,minmax(0,1fr))}}@media(max-width:640px){main{padding:24px 16px 44px}.shots{grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}.card a{padding:10px;font-size:.8rem}.preview{grid-template-columns:1fr;gap:14px}.preview video{max-width:350px;margin:auto;max-height:none}.section-head{align-items:flex-start}select{max-width:100%}}
</style></head><body><main>
<header><div class="brand">Sofatap</div><div class="eyebrow">App Store media · 1.0 (15)</div><h1>Real app. Real iPhone.</h1><p>Review the store screenshots and App Preview. Each screen comes from the physical iPhone running Sofatap. Choose a language and image size below.</p><nav id="languages" aria-label="Language"></nav></header>
<section aria-labelledby="screens-title"><div class="section-head"><h2 id="screens-title">Store screenshots</h2><label>Image size <select id="size" aria-label="Screenshot dimensions"><option value="1320x2868">1320 × 2868</option><option value="1206x2622">1206 × 2622</option></select></label></div><div class="shots" id="shots"></div><p class="fine">Open an image to inspect it at full size, or use its download link. <a id="contact-download" download>Contact sheet</a></p></section>
<section id="preview-section" aria-labelledby="preview-title"><div class="section-head"><h2 id="preview-title">24-second App Preview</h2></div><div class="preview"><video id="video" controls playsinline preload="metadata"></video><div class="details"><p>Touch gestures, keyboard input, sending text, the gesture guide and QR scanning — captured in the app at normal speed.</p><a id="video-download" class="download" download>Download MP4</a><a id="poster-download" class="secondary" download>Poster image</a><div class="facts"><div>886 × 1920 · 30 fps · H.264</div><div>24 seconds · Silent AAC audio</div><div>Physical iPhone 16 Pro Max · iOS 18.6.2</div><div>Sofatap 1.0 (15)</div></div><p class="fine">The full app screen is retained. Captions sit outside it. The device-list screenshots blur only private IP numerals; no screen, connection state or interaction is invented.</p></div></div></section>
<footer><a href="production-manifest.json" download>Production manifest</a> · <a href="README.md">Production notes</a><p class="fine">Review files prepared for App Store submission. This page does not imply Apple approval or publication.</p></footer>
</main><script id="gallery-data" type="application/json">__DATA__</script>
<script>
const data=JSON.parse(document.getElementById('gallery-data').textContent);let locale=Object.keys(data.locales)[0];
const size=document.getElementById('size'),shots=document.getElementById('shots'),video=document.getElementById('video');
function render(){const current=data.locales[locale];document.querySelectorAll('[data-locale]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.locale===locale)));shots.replaceChildren();for(const item of current.screenshots[size.value]){const card=document.createElement('figure');card.className='card';const open=document.createElement('a');open.href=item.file;open.target='_blank';open.rel='noopener';open.style.padding='0';open.style.border='0';const image=document.createElement('img');image.src=item.file;image.alt=item.label;image.loading='lazy';image.width=Number(size.value.split('x')[0]);image.height=Number(size.value.split('x')[1]);open.append(image);const link=document.createElement('a');link.href=item.file;link.download='';link.textContent='↓ '+item.label;card.append(open,link);shots.append(card)}const preview=current.preview||data.locales['en-US']?.preview;document.getElementById('preview-title').textContent=current.preview?'24-second App Preview':'24-second App Preview · English UI';document.getElementById('preview-section').classList.toggle('empty',!preview);video.pause();if(preview){video.src=preview.file;video.poster=preview.poster;document.getElementById('video-download').href=preview.file;document.getElementById('poster-download').href=preview.poster}document.getElementById('contact-download').href=current.contactSheet;video.load()}
for(const [key,value] of Object.entries(data.locales)){const button=document.createElement('button');button.type='button';button.dataset.locale=key;button.textContent=value.label;button.addEventListener('click',()=>{locale=key;render()});document.getElementById('languages').append(button)}size.addEventListener('change',render);render();
</script></body></html>'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--destination', required=True, type=Path)
    parser.add_argument('--locales', nargs='+', default=['en-US', 'zh-Hans', 'ja'])
    args = parser.parse_args()
    source = args.source.resolve()
    # Check the caller's path before resolving so a symlink cannot be hidden.
    if args.destination.is_symlink():
        raise ValueError('Delivery destination cannot be a symlink')
    destination = args.destination.resolve()
    existing = inspect_existing(destination)
    shot_receipt = json.loads((source / 'production-manifest-screenshots.json').read_text())
    preview_path = source / 'production-manifest-preview.json'
    preview_receipt = json.loads(preview_path.read_text()) if preview_path.exists() else {'locales': {}}
    labels = {'en-US': 'English', 'zh-Hans': '简体中文', 'ja': '日本語'}
    names = {'touchpad': 'Touchpad', 'keyboard': 'Keyboard', 'devices': 'Devices', 'scanner': 'Scan QR code', 'guide': 'Gesture guide'}
    gallery = {'locales': {locale: gallery_item(locale, entry, labels, names) for locale, entry in existing.get('locales', {}).items()}}
    public = {'version': 1, 'brand': 'Sofatap', 'preparedAt': datetime.now(timezone.utc).isoformat(), 'locales': existing.get('locales', {}).copy()}
    public['recipeReceipts'] = {name: {key: receipt[key] for key in ('manifestSHA256', 'storyboardSHA256', 'scriptSHA256') if key in receipt} for name, receipt in [('screenshots', shot_receipt), ('preview', preview_receipt)]}
    for entry in public['locales'].values():
        entry.setdefault('recipeReceipts', existing.get('recipeReceipts', {}))
    for locale in args.locales:
        if locale not in shot_receipt['locales']:
            raise ValueError(f'No rendered screenshots for {locale}')
        planned = {f"screenshots/{locale}/{'x'.join(str(n) for n in shot['dimensions'])}/{Path(shot['file']).name}" for shot in shot_receipt['locales'][locale]['screenshots']}
        planned.add(f'contact-sheets/{locale}.png')
        previous_entry = existing.get('locales', {}).get(locale, {})
        if locale in preview_receipt['locales']:
            preview = preview_receipt['locales'][locale]['preview']
            planned.update((f"previews/{locale}/{preview['file']}", f"previews/{locale}/{preview['poster']['file']}"))
        elif previous_entry.get('preview'):
            planned.update((previous_entry['preview']['file'], previous_entry['preview']['poster']['file']))
        previous = {record['file'] for record in media_records(previous_entry)}
        if previous - planned:
            raise ValueError('Updated media plan would leave old files unmanifested; preserve this delivery and use a fresh directory')
    destination.mkdir(parents=True, exist_ok=True)
    for locale in args.locales:
        if locale not in shot_receipt['locales']:
            raise ValueError(f'No rendered screenshots for {locale}')
        item = {'label': labels.get(locale, locale), 'screenshots': {}, 'preview': None}
        records = []
        for shot in shot_receipt['locales'][locale]['screenshots']:
            relative = Path(shot['file'])
            if relative.is_absolute() or '..' in relative.parts:
                raise ValueError('Unsafe output path in receipt')
            size = 'x'.join(str(n) for n in shot['dimensions'])
            target = destination / 'screenshots' / locale / size / relative.name
            copy_verified(source / locale / relative, target, shot['sha256'])
            file = target.relative_to(destination).as_posix()
            state = relative.stem.split('-', 1)[1]
            item['screenshots'].setdefault(size, []).append({'file': file, 'label': names.get(state, state)})
            records.append({**shot, 'file': file})
        preferred = item['screenshots']['1320x2868']
        sheet = Image.new('RGB', (len(preferred) * 264, 610), (18, 25, 29))
        draw = ImageDraw.Draw(sheet)
        for index, shot in enumerate(preferred):
            with Image.open(destination / shot['file']) as image:
                image.thumbnail((254, 566))
                sheet.paste(image, (index * 264 + 5, 8))
            draw.text((index * 264 + 8, 584), shot['label'], fill=(234, 249, 241))
        contact = destination / 'contact-sheets' / f'{locale}.png'
        contact.parent.mkdir(exist_ok=True)
        sheet.save(contact, optimize=True)
        item['contactSheet'] = contact.relative_to(destination).as_posix()
        entry = {'screenshots': records, 'contactSheet': {'file': item['contactSheet'], 'sha256': digest(contact)}, 'recipeReceipts': public['recipeReceipts']}
        if locale in preview_receipt['locales']:
            preview = preview_receipt['locales'][locale]['preview']
            video_source = source / locale / 'preview' / preview['file']
            poster_source = source / locale / 'preview' / preview['poster']['file']
            if Path(preview['file']).name != preview['file'] or Path(preview['poster']['file']).name != preview['poster']['file']:
                raise ValueError('Unsafe preview path in receipt')
            target = destination / 'previews' / locale / preview['file']
            poster = target.parent / preview['poster']['file']
            copy_verified(video_source, target, preview['sha256'])
            copy_verified(poster_source, poster, preview['poster']['sha256'])
            file = target.relative_to(destination).as_posix()
            poster_file = poster.relative_to(destination).as_posix()
            item['preview'] = {'file': file, 'poster': poster_file}
            entry['preview'] = {**preview, 'file': file, 'poster': {**preview['poster'], 'file': poster_file}}
        elif existing.get('locales', {}).get(locale, {}).get('preview'):
            entry['preview'] = existing['locales'][locale]['preview']
            item['preview'] = {'file': entry['preview']['file'], 'poster': entry['preview']['poster']['file']}
        public['locales'][locale] = entry
        gallery['locales'][locale] = item
    repo = Path(__file__).resolve().parents[2]
    documentation = Path(__file__).parent if Path(__file__).with_name('media-production.md').is_file() else repo / 'docs/app-store'
    tool_sources = [Path(__file__), Path(__file__).with_name('produce.py'), documentation / 'media-production.md', documentation / 'media-storyboard.json']
    public['productionTools'] = []
    for tool_source in tool_sources:
        target = destination / 'tools' / tool_source.name
        expected_hash = digest(tool_source)
        copy_verified(tool_source, target, expected_hash)
        public['productionTools'].append({'file': target.relative_to(destination).as_posix(), 'sha256': expected_hash})
    serialized = json.dumps(public, ensure_ascii=False, indent=2)
    # Strict allowlist copy above; reject local execution paths in the final receipt.
    if any(marker in serialized for marker in ('/Users/', '/tmp/', 'sofatap://', 'pairingToken', 'deviceUDID')):
        raise ValueError('Private execution data in the public receipt')
    (destination / 'production-manifest.json').write_text(serialized + '\n')
    (destination / 'index.html').write_text(HTML.replace('__DATA__', json.dumps(gallery, ensure_ascii=False).replace('</', '<\\/')))
    locale_names = ', '.join(labels.get(locale, locale) for locale in public['locales'])
    readme = f'''# Sofatap App Store media — 1.0 (15)

Open `index.html` to view the responsive gallery. Available screenshot languages: {locale_names}.

- Five screenshots per language, each in **1320 × 2868** and **1206 × 2622** RGB PNG.
- App Preview files, when listed in the manifest: **24 seconds**, **886 × 1920**, **30 fps**, H.264 High 4.0, with silent stereo AAC. Each preview folder includes its poster.
- Contact sheets and a public-safe production manifest with output hashes, source hashes, exact source placement and video trims.
- Reproducible production and packaging scripts, storyboard and workflow notes in `tools/`. Raw inputs are deliberately excluded.

Every app screen comes from the physical iPhone 16 Pro Max running iOS 18.6.2 and Sofatap 1.0 (15). Real connected states use an authenticated receiver confined to a private Linux virtual display. The app screen is uniformly scaled and framed; captions are outside it. Device-list screenshots blur only the numeric private IP addresses. All other source pixels remain unchanged before uniform scaling. These narrow privacy edits and original hashes are recorded.

The English preview remains available as a clearly labeled fallback when another screenshot language is selected. The preview uses actual iOS screen recordings at normal speed. Non-app footage, private addresses, source audio and raw recordings are excluded. The original system status bars and keyboard labels remain as captured. The English capture currently has Chinese labels on the iOS space/return keys; the app UI itself is English.

Only final media and review files belong in this folder. Raw recordings, test fixtures, intermediate encoding segments, pairing information, device identifiers and local source paths are intentionally excluded. Apple upload, review and publication are separate outcomes.

Apple references: [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/), [App Preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications/), [Review Guidelines](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata).
'''
    (destination / 'README.md').write_text(readme)
    inspect_existing(destination)
    listed = {'index.html', 'README.md', 'production-manifest.json'}
    listed.update(record['file'] for entry in public['locales'].values() for record in media_records(entry))
    listed.update(record['file'] for record in public['productionTools'])
    files = [destination / name for name in sorted(listed)]
    (destination / 'SHA256SUMS').write_text(''.join(digest(path) + '  ' + path.relative_to(destination).as_posix() + '\n' for path in files))
    print(json.dumps({'destination': str(destination), 'locales': list(public['locales']), 'files': len(files) + 1}))


if __name__ == '__main__':
    main()
