"""Render actual UI declarations through the frame mock; not a WoW screenshot.
Usage: python3 tests/render_ui.py /absolute/output/directory
"""
import os, sys, math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from lupa.lua51 import LuaRuntime
os.chdir(Path(__file__).resolve().parent.parent)
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute(Path('tests/test.lua').read_text())
lua.execute('''
local ST=ForgeTest.ST
ForgeTest.setClock(100,100000)
ST.scan.state='COMPLETE';ST.scan.scope='quick';ST.scan.checkedKeys=60;ST.scan.marketKeys=1240;ST.scan.keys={}
for i=1,60 do ST.scan.keys[i]={} end
ST.scan.browseComplete=true;ST.scan.active=false;ST.scan.paused=false;ST.verify=nil;ST.analysis=nil
ST.scan.message='60 priority keys checked. Full scan available for wider coverage.'
ST.vendor={};ST.market={};ST.rejected={};ST.commodities={}
local names={'Heavy Leather','Wild Steelbloom','Jade','Rugged Leather','Silk Cloth'}
for i,name in ipairs(names)do
    ST.vendor[i]={name=name,id=i,key='item:'..i,count=i*5,buyout=12345*i,value=15555*i,profit=3210*i,roi=.26,observed=100000,executable=true,auctionID=i,depth=5}
end
ST.message='Checked listings only. Reverify before buying; resale is never guaranteed.'
ST.tab=1;ST.view=nil;ST.Toggle();ST.Refresh()
function ExportUI()
    local out={}
    for i,f in ipairs(ForgeTest.created)do
        local a=rawget(f,'anchor');local raw={index=i,kind=f.kind,name=f.name,text=rawget(f,'text'),width=rawget(f,'width'),height=rawget(f,'height'),shown=rawget(f,'shown'),fill=rawget(f,'fill'),textColor=rawget(f,'textColor'),backdrop=rawget(f,'backdrop'),font=rawget(f,'font'),align=rawget(f,'align'),maxLines=rawget(f,'maxLines')}
        for j,p in ipairs(ForgeTest.created)do if f.parent==p then raw.parent=j end;if rawget(f,'allPoints')==p then raw.all=j end;if a and a[2]==p then raw.relative=j end end
        if a then raw.point=a[1];raw.x=a[4] or 0;raw.y=a[5] or 0 end
        if f==ST.ui then raw.root=true end
        out[#out+1]=raw
    end
    return out
end
''')
outdir=Path(sys.argv[1] if len(sys.argv)>1 else '/tmp/stocktrader-previews');outdir.mkdir(parents=True,exist_ok=True)
font_path='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
scale=2

def rgb(arr,default):
    if arr is None:return default
    return tuple(round(max(0,min(1,float(arr[i])))*255) for i in range(1,4))
def render(name):
    records=[dict(x.items()) for x in lua.globals().ExportUI().values()]
    nodes={r['index']:r for r in records};root=next(r for r in records if r.get('root'))
    def desc(r):
        if r is root:return True
        return desc(nodes[r['parent']]) if r.get('parent') else False
    def visible(r):
        if r.get('shown') is False:return False
        if r is root:return True
        return visible(nodes[r['parent']]) if r.get('parent') else False
    cache={}
    def rect(r):
        if r['index'] in cache:return cache[r['index']]
        if r is root:v=(0,0,676,421)
        elif r.get('all'):v=rect(nodes[r['all']])
        else:
            p=nodes.get(r.get('relative') or r.get('parent'));px,py,pw,ph=rect(p) if p else (0,0,0,0)
            v=(px+r.get('x',0),py-r.get('y',0),r.get('width',0),r.get('height',0))
        cache[r['index']]=v;return v
    img=Image.new('RGB',(676*scale,445*scale),(12,15,19));draw=ImageDraw.Draw(img)
    fonts={n:ImageFont.truetype(font_path,n*scale) for n in (9,10,11,12,16)}
    # Parent textures first, then children. Fonts over their textures.
    active=[r for r in records if desc(r) and visible(r)]
    clickable=[r for r in active if r['kind'] in ('Button','EditBox')]
    for r in clickable:
        x,y,w,h=rect(r)
        assert x>=0 and y>=0 and x+w<=676 and y+h<=421, (name,r.get('text'),'out of bounds',rect(r))
    for i,a in enumerate(clickable):
        ax,ay,aw,ah=rect(a)
        for b in clickable[i+1:]:
            bx,by,bw,bh=rect(b)
            assert not (max(ax,bx)<min(ax+aw,bx+bw) and max(ay,by)<min(ay+ah,by+bh)), (name,'overlap',a.get('text'),b.get('text'))
    def depth(r):return 0 if r is root else 1+depth(nodes[r['parent']])
    active.sort(key=lambda r:(depth(r),0 if r['kind']=='Texture' else 1,r['index']))
    for r in active:
        x,y,w,h=rect(r);box=(x*scale,y*scale,(x+w)*scale,(y+h)*scale)
        if r.get('fill') or r.get('backdrop'):draw.rectangle(box,fill=rgb(r.get('fill') or r.get('backdrop'),(10,14,18)))
        kind=r['kind']
        if kind=='Button':draw.rounded_rectangle(box,radius=3*scale,fill=(33,38,45),outline=(70,72,77),width=scale)
        if kind=='EditBox':draw.rectangle(box,fill=(13,17,23),outline=(75,85,98),width=scale)
        text=r.get('text');
        if not text:continue
        size=16 if r.get('font')=='GameFontNormalLarge' else 11 if r.get('font')=='GameFontNormal' else 10
        font=fonts[size];fill=rgb(r.get('textColor'),(226,230,236))
        if kind=='EditBox':text=str(text)
        lines=[]
        for line in str(text).split('\n'):
            if r.get('maxLines')==1:
                while line and draw.textlength(line,font=font)>(w-2)*scale:line=line[:-1]
                lines.append(line)
            else:lines.append(line)
        if r.get('maxLines')==1:lines=lines[:1]
        for j,line in enumerate(lines):
            line_width=draw.textlength(line,font=font)/scale
            tx=x+(w-line_width)/2 if kind=='Button' or r.get('align')=='CENTER' else x+w-line_width if r.get('align')=='RIGHT' else x+ (4 if kind=='EditBox' else 0)
            ty=y+(h-size)/2-1 if kind=='Button' else y
            # Match native frame clipping for edits/scroll content.
            if ty+j*(size+3)>min(y+h,421):break
            draw.text((tx*scale,(ty+j*(size+3))*scale),line,font=font,fill=fill)
    draw.text((12*scale,426*scale),'UI CODE PREVIEW - synthetic fixtures; not a live WoW screenshot',font=fonts[9],fill=(155,162,174))
    img.save(outdir/(name+'.png'))

render('results')
lua.execute("ForgeTest.ST.Select(ForgeTest.ST.vendor[1])")
render('details')
lua.execute("ForgeTest.ST.SetPanel('settings')")
render('settings')
lua.execute("ForgeTest.ST.SetPanel('journal')")
render('journal')
print('Rendered UI previews:',outdir)
