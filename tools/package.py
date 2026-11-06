"""Create an installable addon ZIP; exclude tests, fixtures and development tools."""
import sys, zipfile
from pathlib import Path
root=Path(__file__).resolve().parent.parent
addon=root/'FORGE_StockTrader'
for line in (addon/'FORGE_StockTrader.toc').read_text().splitlines():
    if line.endswith('.lua'):
        assert (addon/line).is_file(), f'Missing TOC dependency: {line}'
out=Path(sys.argv[1] if len(sys.argv)>1 else '/tmp/FORGE_StockTrader_0.4.5.zip')
out.parent.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as z:
    for p in sorted(addon.rglob('*')):
        if p.is_file(): z.write(p,p.relative_to(root))
    for name in ('README.md','CHANGELOG.md'):
        z.write(root/name,'FORGE_StockTrader/'+name)
    for p in sorted((root/'docs').glob('*.md')):
        z.write(p,'FORGE_StockTrader/docs/'+p.name)
with zipfile.ZipFile(out) as z:
    assert z.testzip() is None
    assert all(n.startswith('FORGE_StockTrader/') for n in z.namelist())
    print(f'{out}: {len(z.namelist())} files, {out.stat().st_size} bytes; ZIP and TOC validated')
