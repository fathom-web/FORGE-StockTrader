-- A native, inset trading terminal. All content stays inside the existing AH tab.
local _,ST=...;local M,D=ST.Model,ST.Database
local ui,lib,attached;local panel='results';local page=1;local sort='profit';local ascending=false
local C={bg={.045,.055,.07,1},surface={.075,.09,.11,1},line={.22,.24,.27,1},gold={.88,.71,.40,1},muted={.61,.66,.72,1},text={.90,.92,.94,1},green={.38,.86,.61,1},amber={1,.73,.34,1},red={.97,.40,.42,1}}
local function color(t,c)t:SetTextColor(unpack(C[c] or C.text))end
local function texture(parent,x,y,w,h,c)
    local t=parent:CreateTexture(nil,'BACKGROUND');t:SetPoint('TOPLEFT',parent,'TOPLEFT',x,-y);t:SetSize(w,h);t:SetColorTexture(unpack(C[c]));return t
end
local function label(parent,x,y,w,text,font,h)
    local t=parent:CreateFontString(nil,'OVERLAY',font or 'GameFontHighlightSmall');t:SetPoint('TOPLEFT',parent,'TOPLEFT',x,-y)
    t:SetSize(w,h or 18);t:SetJustifyH('LEFT');t:SetJustifyV('TOP');t:SetText(text or '');color(t,'text');return t
end
local function button(parent,x,y,w,text,fn)
    local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate');b:SetPoint('TOPLEFT',parent,'TOPLEFT',x,-y);b:SetSize(w,24);b:SetText(text);b:SetScript('OnClick',fn);return b
end
local function edit(parent,x,y,w)
    local e=CreateFrame('EditBox',nil,parent,'InputBoxTemplate');e:SetPoint('TOPLEFT',parent,'TOPLEFT',x,-y);e:SetSize(w,22);e:SetAutoFocus(false);e:SetMaxLetters(18)
    e:SetScript('OnEscapePressed',function(self)self:ClearFocus()end);return e
end
local function tooltip(owner,lines,link)
    GameTooltip:SetOwner(owner,'ANCHOR_RIGHT');if link then GameTooltip:SetHyperlink(link) else GameTooltip:SetText(lines[1] or '') end
    for i=2,#lines do GameTooltip:AddLine(lines[i],.85,.88,.9,true)end;GameTooltip:Show()
end
local function itemIcon(parent, x, y, size)
    local icon = parent:CreateTexture(nil, 'ARTWORK')
    icon:SetPoint('TOPLEFT', parent, 'TOPLEFT', x, -y)
    icon:SetSize(size, size)
    return icon
end

local function vendorTotal(row)
    if row.executable and M.integer(row.count) and row.count > 0 and M.integer(row.vendor) then
        return ST.money(row.vendor * row.count)
    end
    return '--'
end

function ST.DetailLines(r)
    local lines={r.name or 'Item',r.reason or 'Positive vendor margin. Verify the exact auction before buying.',
        'Observed '..date('%d-%m %H:%M:%S',r.observed or time()),'Quantity '..r.count..' | Buyout '..ST.money(r.buyout),
        'ROI '..string.format('%.1f%%',(r.roi or 0)*100)..' | Profit/item '..ST.money((r.profit or 0)/r.count),r.verification or 'NOT REVERIFIED'}
    lines[#lines+1] = 'NPC sell / item: '..ST.money(r.vendor)
    if r.executable then
        lines[#lines+1] = 'NPC sell for '..r.count..': '..vendorTotal(r)
    end
    if r.prices then
        lines[#lines+1]=r.prices.method
        lines[#lines+1]='Base/unit '..ST.money(r.prices.base)..' | Upside/unit '..ST.money(r.prices.optimistic)
        lines[#lines+1]=r.prices.sample..' changed observations | Latest '..date('%d-%m %H:%M',r.prices.last)
        lines[#lines+1]='Break-even stack '..ST.money(r.breakEven)..' | Failed deposits '..ST.money(r.lostDeposits)
        lines[#lines+1]='Costs: '..(r.fee.source or 'Assumed')
        for _,s in ipairs(r.scenarios)do lines[#lines+1]=string.format('Price -%d%%: %s',s.drop*100,ST.money(s.profit))end
        lines[#lines+1]='One failure + 15% decline: '..ST.money(r.oneFailure)
        if r.ev then lines[#lines+1]='User probability scenario '..string.format('%.0f%%',r.probability*100)..': EV '..ST.money(r.ev)..' (not measured)'end
        lines[#lines+1]='Score is a heuristic, not profit probability. Supply depth does not prove demand.'
    end
    local evidence=D.calibration(ST.db,r.key)
    lines[#lines+1]=string.format('Your records: %d sold / %d closed; %d still held. Not a demand forecast.',evidence.sold,evidence.closed,evidence.held)
    return lines
end
function ST.VisibleRows()
    local all=ST.tab==1 and ST.vendor or ST.market
    if ST.tab==2 and ST.view=='research' then all=ST.rejected elseif ST.tab==2 and ST.view=='commodities' then all=ST.commodities end
    local result={};for _,r in ipairs(all or {})do result[#result+1]=r end
    table.sort(result,function(a,b)
        local av,bv=a[sort] or (sort=='name' and '' or 0),b[sort] or (sort=='name' and '' or 0)
        if av==bv then return (a.auctionID or 0)<(b.auctionID or 0)end
        if ascending then return av<bv end;return av>bv
    end);return result
end
function ST.SetPanel(name)panel=name or 'results';ST.Refresh()end
function ST.Select(row)
    ST.selected=row;panel='detail'
    ui.detail.paid:SetText(tostring(row.buyout));ui.detail.cut:SetText(ST.db.settings.cutBP and tostring(ST.db.settings.cutBP/100) or '')
    local fee=ST.db.fees[row.key];ui.detail.deposit:SetText(type(fee)=='table' and fee.quantity==row.count and tostring(fee.deposit/10000) or '')
    ST.Refresh()
end
local fields={
    {'minVendor','Min vendor profit (gold)',10000},{'vendorROI','Min vendor ROI (%)',.01},
    {'minMarket','Min AH profit (gold)',10000},{'marketROI','Min AH ROI (%)',.01},
    {'positionCap','Per-item gold limit (%)',.01},{'totalCap','Total gold limit (%)',.01},
    {'lossCap','Max loss / gold (%)',.01},{'lossFraction','Max loss / purchase (%)',.01},
    {'discount','Minimum discount (%)',.01},{'failures','Failed listing attempts',1},
    {'scanLimit','Quick scan: item keys',1},{'cutBP','Market commission (%)',100}}
ST.settingFields=fields
function ST.SaveSettings()
    local nextValues={}
    for _,spec in ipairs(fields)do
        local k=spec[1];local raw=ui.settings.inputs[k]:GetText();local n=tonumber(raw)
        if k=='cutBP' and raw=='' then nextValues[k]=false
        else
            n=n and n*spec[3];local valid=n and n==n and n>=0 and n<1e10
            if k=='failures' then valid=valid and M.integer(n) and n<=20
            elseif k=='scanLimit' then valid=valid and M.integer(n) and n>=10 and n<=300
            elseif k=='cutBP' then valid=valid and M.integer(n) and n<10000
            elseif k~='minVendor' and k~='minMarket' then valid=valid and n<1
            else valid=valid and M.integer(n)end
            if not valid then ST.message='Invalid value: '..spec[2];ST.Refresh();return false end
            nextValues[k]=n
        end
    end
    for k,v in pairs(nextValues)do ST.db.settings[k]=v~=false and v or nil end
    ST.Costs.reset();ST.Reassess();panel='results';ST.message='Settings saved. Validated results recalculated.';ST.Refresh();return true
end
local function metric(parent,x,y,w,title)
    texture(parent,x,y,w,47,'surface');local a=label(parent,x+10,y+6,w-20,title);color(a,'muted')
    return label(parent,x+10,y+24,w-20,'','GameFontNormal',20)
end
function ST.Refresh()
    if not ui or not ST.db then return end
    local s=ST.scan;local op=ST.verify and ST.verify.active and ST.verify or s
    local busy=(s and s.active) or ST.analysis or (ST.verify and ST.verify.active)
    local state=op and op.state or 'IDLE';local tint='muted';local title=state
    if state=='COMPLETE' then tint='green';title=(s.scope=='quick' and 'QUICK SCAN COMPLETE' or 'SCAN COMPLETE')
    elseif state=='ERROR' or state=='TIMEOUT' then tint='red';title='SCAN FAILED'
    elseif state=='PAUSED' then tint='amber';title='PAUSED - PARTIAL RESULTS'
    elseif state=='CANCELLED' then title='STOPPED - PARTIAL RESULTS'
    elseif busy then tint='amber';title=ST.verify and ST.verify.active and 'VERIFYING LISTING' or 'SCANNING' end
    ui.banner.caption:SetText(title);color(ui.banner.caption,tint)
    ui.status:SetText(op and op.message or ST.message)
    local checked=s and s.checkedKeys or 0;local selected=s and #(s.keys or {}) or 0;local total=s and s.marketKeys or 0
    ui.coverage:SetText(string.format('MARKET %s   |   CHECKED %d/%d selected   |   %d market keys',s and s.browseComplete and 'LOADED' or 'WAITING',checked,selected,total))
    local last=ST.db.lastScan and date('%H:%M',ST.db.lastScan) or 'never'
    ui.count:SetText(string.format('%d vendor   /   %d AH   /   %d research   |   last success %s',#ST.vendor,#ST.market,#ST.rejected+#ST.commodities,last))
    local frac=selected>0 and math.min(1,checked/selected) or 0;ui.progress:SetWidth(math.max(1,(ui.width-36)*frac))
    ui.note:SetText(ST.message);ui.count:SetShown(panel=='results')
    ui.quick:SetEnabled(not busy and ST.open);ui.full:SetEnabled(not busy and ST.open)
    ui.pause:SetText(s and s.paused and 'Resume' or 'Pause');ui.pause:SetEnabled(s and (s.active or s.paused) and not (ST.verify and ST.verify.active))
    ui.cancel:SetEnabled(not not (busy or (s and s.paused)))
    for i,b in ipairs(ui.tabs)do b:SetText((ST.tab==i and '> ' or '')..(i==1 and 'Vendor Sell' or 'AH Koopjes'))end
    ui.research:SetShown(ST.tab==2);ui.commodity:SetShown(ST.tab==2)
    ui.research:SetText(ST.view=='research' and 'Candidates' or 'Rejections');ui.commodity:SetText(ST.view=='commodities' and 'Candidates' or 'Commodities')
    for _,p in pairs(ui.panels)do p:Hide()end
    ui.panels[panel]:Show()
    if panel=='results' then
        local data=ST.VisibleRows();local pages=math.max(1,math.ceil(#data/ui.rowCount));page=math.max(1,math.min(page,pages))
        ui.table.page:SetText(string.format('%d results   |   %d / %d',#data,page,pages))
        ui.table.empty:SetShown(#data==0)
        ui.table.empty:SetText(ST.tab==1 and 'NO VERIFIED VENDOR DEALS\nComplete item checks appear here while scanning.\nOnly positive full-stack margins qualify.' or 'NO TRADE RECOMMENDED\nUse Rejections to inspect evidence and costs.\nCommodities require a native price quote.')
        for i,r in ipairs(ui.rows)do
            local d=data[(page-1)*ui.rowCount+i];r.deal=d;r:SetShown(d~=nil)
            if d then
                local expired=time()-(d.observed or 0)>120 or (d.quoteUntil and GetTime()>d.quoteUntil)
                r.icon:SetTexture(d.icon or 134400)
                r.labels[7]:SetText(ST.money(d.vendor))
                r.labels[1]:SetText(d.name);r.labels[2]:SetText(tostring(d.count));r.labels[3]:SetText(ST.money(d.buyout));r.labels[4]:SetText(d.profit and ST.money(d.profit) or '--')
                r.labels[5]:SetText(d.roi and string.format('%.1f%%',d.roi*100) or '--')
                r.labels[6]:SetText(expired and 'STALE' or (d.source=='commodity-depth' and 'QUOTE NEEDED' or (d.score and tostring(d.score)..'/100' or 'RECHECK')))
                color(r.labels[4],expired and 'amber' or ((d.profit or 0)>0 and 'green' or 'muted'));color(r.labels[6],expired and 'amber' or 'muted')
            end
        end
    elseif panel=='detail' then
        local d=ST.selected;if not d then panel='results';return ST.Refresh()end
        local p=ui.detail
        p.icon:SetTexture(d.icon or 134400)
        p.sell:SetText('NPC sell / item: '..ST.money(d.vendor)..'   |   NPC total: '..vendorTotal(d))
        p.title:SetText(d.name..'  x'..d.count);p.status:SetText(d.verification or 'SNAPSHOT - RECHECK BEFORE BUYING')
        p.metrics[1]:SetText(ST.money(d.buyout));p.metrics[2]:SetText(ST.money(d.profit));p.metrics[3]:SetText(d.downside and ST.money(-d.downside) or ST.money(d.value));p.metrics[4]:SetText(d.safe and ST.money(d.safe) or (d.roi and string.format('%.1f%% ROI',d.roi*100) or '--'))
        color(p.metrics[2],(d.profit or 0)>0 and 'green' or 'amber')
        p.reason:SetText(d.reason or 'Positive vendor margin for this exact full stack. Verify availability.')
        p.verify:SetEnabled(not busy);p.native:SetEnabled(not busy);p.record:SetEnabled(not busy)
        local deposit,source=ST.Costs.deposit(d,ST.db.settings.duration or 1)
        p.costSource:SetText(deposit~=nil and ('API deposit '..ST.money(deposit)..' | commission is your setting') or 'Deposit: manual until exact owned item is available. Commission: your setting.')
    elseif panel=='settings' then
        for _,spec in ipairs(fields)do local e=ui.settings.inputs[spec[1]];if not e:HasFocus()then local n=ST.db.settings[spec[1]];e:SetText(n and tostring(n/spec[3]) or '')end end
        ui.settings.duration:SetText('Duration: '..({'Short','Medium','Long'})[ST.db.settings.duration or 1])
        ui.settings.alerts:SetText('Alerts: '..(ST.db.settings.alerts and 'on' or 'off'))
    elseif panel=='journal' then
        local p=D.performance(ST.db);local cal=D.calibration(ST.db)
        ui.history.metrics[1]:SetText(ST.money(p.net));ui.history.metrics[2]:SetText(ST.money(p.capital));ui.history.metrics[3]:SetText(p.winRate and string.format('%.1f%%',p.winRate*100) or '--');ui.history.metrics[4]:SetText(cal.meanError and ST.money(cal.meanError) or '--')
        local j=ST.db.journal;local last=math.min(#j,ST.journalEnd or #j);local first=math.max(1,last-2)
        for i,b in ipairs(ui.history.rows)do local t=j[first+i-1];b.trade=t;b:SetShown(t~=nil and first+i-1<=last);if t then b:SetText('#'..t.id..'  '..t.name..'  |  '..t.outcome..'  |  '..ST.money(t.profit or -t.purchase))end end
        ui.history.outcome:SetText(ST.exitOutcome or 'sold')
    elseif panel=='diagnostics' then
        local lines={'FORGE StockTrader '..ST.version,'Build '..tostring(select(2,GetBuildInfo())),'Scope '..tostring(s.scope)..' | state '..s.state}
        for _,l in ipairs(s.log or {})do lines[#lines+1]=string.format('%.1f %s: %s',l.at,l.state,l.message)end
        if not ui.diagnostics.text:HasFocus()then ui.diagnostics.text:SetText(table.concat(lines,'\n'))end
    end
end
local function build()
    ui=CreateFrame('Frame','FORGEStockTraderFrame',AuctionHouseFrame,'BackdropTemplate');ST.ui=ui
    -- Preserve the proven 0.2 native content footprint. No resize of Blizzard's AH.
    ui.width,ui.height=676,421;local w,h=ui.width,ui.height
    ui:SetSize(w,h);ui:SetPoint('TOPLEFT',AuctionHouseFrame,'TOPLEFT',30,-39);ui:SetFrameLevel(AuctionHouseFrame:GetFrameLevel()+15);ui:EnableMouse(true)
    ui:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=10,insets={left=2,right=2,top=2,bottom=2}});ui:SetBackdropColor(unpack(C.bg));ui:SetBackdropBorderColor(unpack(C.line))
    color(label(ui,18,12,400,'FORGE  STOCKTRADER','GameFontNormalLarge',24),'gold');color(label(ui,18,37,450,'NOVYX FORGE   /   PROTECT YOUR GOLD'),'muted')
    label(ui,514,15,144,'QUANTUM  '..ST.version):SetJustifyH('RIGHT')
    ui.quick=button(ui,18,61,105,'Quick scan',function()panel='results';ST.Start('quick')end)
    ui.full=button(ui,129,61,94,'Full scan',function()panel='results';ST.Start('full')end)
    ui.pause=button(ui,229,61,74,'Pause',function()if ST.scan.paused then ST.scan:resume()else ST.scan:pause()end;ST.Changed()end)
    ui.cancel=button(ui,309,61,70,'Stop',ST.Cancel)
    button(ui,401,61,80,'Settings',function()panel=panel=='settings' and 'results' or 'settings';ST.Refresh()end)
    button(ui,487,61,80,'Journal',function()panel=panel=='journal' and 'results' or 'journal';ST.Refresh()end)
    button(ui,573,61,85,'Diagnostics',function()panel=panel=='diagnostics' and 'results' or 'diagnostics';ST.Refresh()end)
    texture(ui,18,94,w-36,59,'surface');ui.banner={caption=label(ui,28,102,240,'READY','GameFontNormal')};ui.status=label(ui,270,103,378,'');ui.status:SetMaxLines(1)
    ui.coverage=label(ui,28,126,620,'');color(ui.coverage,'muted');texture(ui,18,151,w-36,2,'line');ui.progress=texture(ui,18,151,1,2,'gold')
    ui.tabs={button(ui,18,164,130,'Vendor Sell',function()ST.tab=1;ST.view=nil;panel='results';page=1;ST.Refresh()end),button(ui,154,164,130,'AH Koopjes',function()ST.tab=2;ST.view=nil;panel='results';page=1;ST.Refresh()end)}
    ui.research=button(ui,410,164,108,'Rejections',function()ST.view=ST.view=='research' and nil or 'research';panel='results';page=1;ST.Refresh()end)
    ui.commodity=button(ui,524,164,134,'Commodities',function()ST.view=ST.view=='commodities' and nil or 'commodities';panel='results';page=1;ST.Refresh()end)
    ui.panels={};for _,name in ipairs({'results','detail','settings','journal','diagnostics'})do local f=CreateFrame('Frame',nil,ui);f:SetAllPoints(ui);ui.panels[name]=f end
    ui.table=ui.panels.results;ui.detail=ui.panels.detail;ui.settings=ui.panels.settings;ui.history=ui.panels.journal;ui.diagnostics=ui.panels.diagnostics
    local columns={{18,155,'ITEM','name'},{176,38,'QTY','count'},{217,96,'BUYOUT','buyout'},
        {417,96,'NET PROFIT','profit'},{516,54,'ROI','roi'},{573,85,'STATUS','score'},
        {316,98,'NPC / ITEM','vendor'}}
    for _,col in ipairs(columns)do local field=col[4];button(ui.table,col[1],199,col[2],col[3],function()if sort==field then ascending=not ascending else sort=field;ascending=false end;ST.Refresh()end)end
    ui.rows={};ui.rowCount=5
    for i=1,ui.rowCount do
        local r=CreateFrame('Button',nil,ui.table);r:SetPoint('TOPLEFT',ui.table,'TOPLEFT',18,-(228+(i-1)*27));r:SetSize(w-36,25)
        texture(r,0,0,w-36,25,i%2==0 and 'surface' or 'bg');r:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight','ADD');r.labels={}
        r.icon=itemIcon(r,3,3,19)
        for j,col in ipairs(columns)do local inset=j==1 and 25 or 5;local t=label(r,col[1]-18+inset,5,col[2]-inset-5,'');t:SetMaxLines(1);if j>1 then t:SetJustifyH(j==6 and 'LEFT' or 'RIGHT')end;r.labels[j]=t end
        r:SetScript('OnClick',function(self)if self.deal then ST.Select(self.deal)end end)
        r:SetScript('OnEnter',function(self)if self.deal then tooltip(self,ST.DetailLines(self.deal),self.deal.link)end end);r:SetScript('OnLeave',function()GameTooltip:Hide()end);ui.rows[i]=r
    end
    ui.table.empty=label(ui.table,32,255,w-64,'','GameFontHighlight',70);ui.table.empty:SetJustifyH('CENTER');color(ui.table.empty,'muted')
    button(ui.table,18,367,36,'<',function()page=math.max(1,page-1);ST.Refresh()end);button(ui.table,60,367,36,'>',function()page=page+1;ST.Refresh()end)
    ui.table.page=label(ui.table,108,371,190,'');ui.count=label(ui,310,371,348,'');ui.count:SetMaxLines(1);color(ui.count,'muted')
    ui.note=label(ui,18,400,w-36,'');ui.note:SetMaxLines(1);color(ui.note,'muted')
    -- Details: strong numeric hierarchy; formulas and scenarios live in the explanation tooltip.
    local p=ui.detail;p.icon=itemIcon(p,18,197,31);p.title=label(p,57,197,475,'','GameFontNormal');p.title:SetMaxLines(1)
    button(p,548,196,110,'Back',function()panel='results';ST.Refresh()end)
    p.sell=label(p,57,215,480,'');color(p.sell,'gold')
    p.status=label(p,18,231,635,'');p.status:SetMaxLines(1);color(p.status,'amber')
    p.metrics={};for i,t in ipairs({'BUYOUT','NET PROFIT','DOWNSIDE / VALUE','MAX BUY / ROI'})do p.metrics[i]=metric(p,18+(i-1)*163,249,151,t)end
    p.reason=label(p,18,298,508,'');p.reason:SetMaxLines(1)
    local explain=button(p,548,293,110,'Explain',function()if ST.selected then tooltip(p,ST.DetailLines(ST.selected))end end)
    explain:SetScript('OnLeave',function()GameTooltip:Hide()end)
    label(p,18,325,44,'Fee %');p.cut=edit(p,66,321,48);label(p,128,325,96,'Deposit (gold)');p.deposit=edit(p,228,321,70)
    button(p,310,319,92,'Save costs',function()if not ST.SetFee(ST.selected,p.cut:GetText(),p.deposit:GetText())then ST.message='Enter valid fee % and full-quantity deposit gold.'end;ST.Refresh()end)
    label(p,415,325,76,'Paid copper');p.paid=edit(p,494,321,80)
    p.record=button(p,584,319,74,'Record',function()ST.RecordSelected(p.paid:GetText());ST.Refresh()end)
    p.costSource=label(p,18,347,640,'');p.costSource:SetMaxLines(1);color(p.costSource,'muted')
    p.verify=button(p,18,367,206,'Verify live listing',function()ST.Verify(ST.selected);ST.Refresh()end)
    p.native=button(p,232,367,206,'Open native AH',function()ST.OpenNative(ST.selected);ST.Refresh()end)
    -- Risk settings use player-facing units, with a single commission setting for the market.
    ui.settings.inputs={}
    for i,spec in ipairs(fields)do local x=i%2==1 and 18 or 346;local y=202+math.floor((i-1)/2)*27
        label(ui.settings,x,y+3,228,spec[2]);ui.settings.inputs[spec[1]]=edit(ui.settings,x+235,y,64)
    end
    button(ui.settings,18,367,150,'Save risk limits',ST.SaveSettings)
    ui.settings.duration=button(ui.settings,176,367,142,'Duration',function()ST.db.settings.duration=(ST.db.settings.duration or 1)%3+1;ST.Costs.reset();ST.Reassess();ST.Refresh()end)
    ui.settings.alerts=button(ui.settings,326,367,132,'Alerts',function()ST.db.settings.alerts=not ST.db.settings.alerts;ST.Refresh()end)
    button(ui.settings,466,367,192,'Back',function()panel='results';ST.Refresh()end)
    -- Manual outcomes, with labelled fields instead of a raw command string.
    p=ui.history;p.metrics={};for i,title in ipairs({'REALIZED NET','OPEN CAPITAL','RECORDED WIN RATE','ACTUAL MINUS PLAN'})do p.metrics[i]=metric(p,18+(i-1)*163,199,151,title)end
    p.rows={};for i=1,3 do local b=button(p,18,252+(i-1)*25,640,'',function()end);b:SetScript('OnClick',function(self)if self.trade then p.id:SetText(tostring(self.trade.id))end end);p.rows[i]=b end
    local specs={{'id',18,42,'ID'},{'gross',164,110,'Gross copper'},{'fees',282,102,'Fees copper'},{'lost',392,120,'Lost deposits'},{'attempts',520,54,'Fails'}}
    for _,spec in ipairs(specs)do label(p,spec[2],332,spec[3],spec[4]);p[spec[1]]=edit(p,spec[2]+3,349,spec[3]-5)end
    label(p,68,332,88,'Outcome');p.outcome=button(p,68,347,88,'sold',function()local nextState={sold='vendored',vendored='abandoned',abandoned='sold'};ST.exitOutcome=nextState[ST.exitOutcome or 'sold'];ST.Refresh()end)
    button(p,584,347,74,'Save',function()
        local t,err=D.close(ST.db,tonumber(p.id:GetText()),ST.exitOutcome or 'sold',tonumber(p.gross:GetText()),tonumber(p.fees:GetText()),tonumber(p.lost:GetText()),tonumber(p.attempts:GetText()),time())
        ST.message=t and ('Trade #'..t.id..' closed: '..ST.money(t.profit)) or err;ST.Refresh()
    end)
    button(p,18,375,36,'<',function()ST.journalEnd=math.max(3,(ST.journalEnd or #ST.db.journal)-3);ST.Refresh()end)
    button(p,60,375,36,'>',function()ST.journalEnd=math.min(#ST.db.journal,(ST.journalEnd or #ST.db.journal)+3);ST.Refresh()end)
    color(label(p,108,379,546,'Click a trade to select it. Record actual outcomes; refunded deposits are excluded.'),'muted')
    local sf=CreateFrame('ScrollFrame',nil,ui.diagnostics,'UIPanelScrollFrameTemplate');sf:SetPoint('TOPLEFT',ui.diagnostics,'TOPLEFT',24,-206);sf:SetSize(610,151)
    ui.diagnostics.text=edit(sf,0,0,600);ui.diagnostics.text:SetMultiLine(true);ui.diagnostics.text:SetMaxLetters(16000);ui.diagnostics.text:SetHeight(900);sf:SetScrollChild(ui.diagnostics.text)
    button(ui.diagnostics,18,367,170,'Select diagnostic text',function()ui.diagnostics.text:SetFocus();ui.diagnostics.text:HighlightText()end)
    button(ui.diagnostics,200,367,170,'Experimental replicate',function()panel='results';ST.Start('replicate')end)
    button(ui.diagnostics,382,367,276,'Back',function()panel='results';ST.Refresh()end)
    ui:Hide();ST.Refresh()
end
function ST.Attach()
    if not ST.open or not AuctionHouseFrame then return end
    ST.InstallHooks();if attached then return end;if not ui then build()end
    lib=LibStub and LibStub('LibAHTab-1-0',true)
    if not lib then ST.message='Missing LibAHTab; reinstall the complete addon folder.';ST.Refresh();return end
    local ok,err=pcall(function()if not lib:DoesIDExist('FORGE_STOCKTRADER')then lib:CreateTab('FORGE_STOCKTRADER',ui,'StockTrader','FORGE StockTrader')end end)
    if ok then attached=true else ST.message=tostring(err)end;ST.Refresh()
end
function ST.Toggle()
    if not ST.open then print('FORGE StockTrader: Open the Auction House first.');return end
    ST.Attach();if attached then lib:SetSelected('FORGE_STOCKTRADER')end
end
