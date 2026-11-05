-- Native AH shell retained from 0.2.0; calculations/scanning live in testable modules.
local _,ST=...; local M,D=ST.Model,ST.Database
local ui,lib,attached; local rows={}; local page=1; local panel=nil; local sort='profit'; local ascending=false
local function label(parent,x,y,w,text,font)
    local t=parent:CreateFontString(nil,'OVERLAY',font or 'GameFontHighlightSmall')
    t:SetPoint('TOPLEFT',parent,'TOPLEFT',x,y); t:SetSize(w,20); t:SetJustifyH('LEFT'); t:SetText(text or ''); return t
end
local function button(parent,x,y,w,text,fn)
    local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate'); b:SetPoint('TOPLEFT',x,y); b:SetSize(w,24); b:SetText(text); b:SetScript('OnClick',fn); return b
end
local function input(parent,x,y,w)
    local e=CreateFrame('EditBox',nil,parent,'InputBoxTemplate'); e:SetPoint('TOPLEFT',x,y); e:SetSize(w,22); e:SetAutoFocus(false); e:SetMaxLetters(16)
    e:SetScript('OnEscapePressed',function(self) self:ClearFocus() end); return e
end
local function tip(r)
    GameTooltip:SetOwner(ui,'ANCHOR_RIGHT')
    if r.link then GameTooltip:SetHyperlink(r.link) else GameTooltip:SetText(r.name) end
    GameTooltip:AddLine(r.reason or 'Positive vendor margin; exact auction must still exist',1,.8,.3,true)
    GameTooltip:AddLine('ROI: '..string.format('%.1f%%',(r.roi or 0)*100)..' | Per item: '..ST.money((r.profit or 0)/r.count),.7,1,.7,true)
    GameTooltip:AddLine('Observed '..date('%H:%M:%S',r.observed or time())..' | '..(r.verification or 'Not reverified'),1,.8,.3,true)
    if r.prices then
        GameTooltip:AddLine(r.prices.method,1,1,1,true)
        GameTooltip:AddLine('Base/unit '..ST.money(r.prices.base)..' | Upside/unit '..ST.money(r.prices.optimistic),1,1,1,true)
        GameTooltip:AddLine(r.prices.sample..' changed snapshots; latest '..date('%d-%m %H:%M',r.prices.last),1,1,1,true)
        GameTooltip:AddLine('Supply depth: '..r.depth..'. Demand and sale probability unknown.',1,.8,.3,true)
        for _,s in ipairs(r.scenarios) do GameTooltip:AddLine(string.format('Price -%d%%: %s',s.drop*100,ST.money(s.profit)),1,1,1,true) end
        if r.ev then GameTooltip:AddLine('USER probability scenario '..string.format('%.0f%%',r.probability*100)..': EV '..ST.money(r.ev)..' (not measured)',1,.8,.3,true) end
        GameTooltip:AddLine('1 failure + 15% decline: '..ST.money(r.oneFailure),1,.8,.3,true)
    end
    GameTooltip:Show()
end
function ST.VisibleRows()
    local all=ST.tab==1 and ST.vendor or (ST.showRejected and ST.rejected or ST.market)
    local result={}; for _,r in ipairs(all) do result[#result+1]=r end
    table.sort(result,function(a,b)
        local av,bv=a[sort] or (sort=='name' and '' or 0),b[sort] or (sort=='name' and '' or 0)
        if av==bv then return (a.auctionID or 0)<(b.auctionID or 0) end
        if ascending then return av<bv else return av>bv end
    end); return result
end
function ST.Refresh()
    if not ui or not ST.db then return end
    local s=ST.scan; local busy=s and (s.active or ST.analysis or (ST.verify and ST.verify.active))
    local state=s and s.state or 'IDLE'; local caption=state
    local r,g,b=.28,.29,.31
    if state=='COMPLETE' then r,g,b=.06,.38,.15; caption='SCAN COMPLETE'
    elseif state=='ERROR' or state=='TIMEOUT' then r,g,b=.5,.08,.1; caption='SCAN FAILED: '..state
    elseif busy then r,g,b=.5,.32,.05; caption='SCANNING: '..state end
    ui.banner.bg:SetColorTexture(r,g,b,.96); ui.banner.caption:SetText(caption)
    ui.status:SetText((s and s.message or ST.message)..(busy and string.format(' | %ds | %d listings | keys %d/%d',GetTime()-s.started,s.processed or 0,math.min(s.keyIndex or 0,#(s.keys or {})),#(s.keys or {})) or ''))
    ui.note:SetText(ST.message)
    ui.last:SetText('Last success: '..(ST.db.lastScan and date('%d-%m %H:%M',ST.db.lastScan) or 'Never')..' | Browse: when AH idle; requests >=2s apart')
    ui.scan:SetEnabled(not busy and ST.open); ui.cancel:SetEnabled(not not busy)
    ui.tabs[1]:SetText(ST.tab==1 and '> Vendor Sell' or 'Vendor Sell'); ui.tabs[2]:SetText(ST.tab==2 and '> AH Koopjes' or 'AH Koopjes')
    ui.reject:SetShown(ST.tab==2); ui.journal:SetShown(ST.tab==2)
    ui.reject:SetText(ST.showRejected and 'Show candidates' or 'Rejections / research')
    ui.table:Hide(); ui.detail:Hide(); ui.settings:Hide(); ui.history:Hide()
    if panel=='detail' and ST.selected then
        ui.detail:Show(); local d=ST.selected
        ui.detail.title:SetText(d.name..' x'..d.count..' | '..(d.verification or 'NOT REVERIFIED'))
        ui.detail.body:SetText('Buyout '..ST.money(d.buyout)..'   Value '..ST.money(d.value)..'   Profit '..ST.money(d.profit)..'\n'..
            'ROI '..string.format('%.1f%%',(d.roi or 0)*100)..'   Per item '..ST.money((d.profit or 0)/d.count)..'   Age '..math.max(0,time()-(d.observed or 0))..'s\n'..
            (d.prices and ('Conservative unit '..ST.money(d.prices.conservative)..' | '..d.prices.confidence..' confidence | Score '..d.score..'/100\n'..
            'Vendor downside '..ST.money(-d.downside)..' | Break-even stack '..ST.money(d.breakEven)..'\n'..
            'MAX SAFE BUY PRICE '..ST.money(d.safe)..' (model threshold, no guarantee)\n') or '')..
            (d.reason or 'Deterministic margin only if this exact listing remains available.'))
        local fee=ST.db.fees[d.key]
        if not ui.detail.cut:HasFocus() then ui.detail.cut:SetText(fee and tostring(fee.cutBP/100) or '') end
        if not ui.detail.deposit:HasFocus() then ui.detail.deposit:SetText(fee and tostring(fee.deposit/10000) or '') end
        ui.detail.verify:SetEnabled(not busy); ui.detail.record:SetEnabled(not busy)
    elseif panel=='settings' then
        ui.settings:Show()
        for k,e in pairs(ui.settings.inputs) do if not e:HasFocus() then e:SetText(tostring(ST.db.settings[k])) end end
    elseif panel=='journal' then
        ui.history:Show(); local p=D.performance(ST.db)
        ui.history.summary:SetText('Realized net '..ST.money(p.net)..' | Open capital '..ST.money(p.capital)..' | Closed '..p.n..'\n'..
            'Win rate '..(p.winRate and string.format('%.1f%%',p.winRate*100) or 'N/A')..' | Largest loss '..ST.money(p.largestLoss)..' | Median ROI '..(p.medianReturn and string.format('%.1f%%',p.medianReturn*100) or 'N/A'))
        local lines={}; local j=ST.db.journal; for i=math.max(1,#j-3),#j do local t=j[i]; lines[#lines+1]='#'..t.id..' '..t.name..' | '..t.outcome..' | '..ST.money(t.profit or -t.purchase) end
        ui.history.entries:SetText(table.concat(lines,'\n'))
    else
        panel=nil; ui.table:Show(); local data=ST.VisibleRows(); local pages=math.max(1,math.ceil(#data/5)); page=math.min(page,pages)
        ui.table.count:SetText(string.format('%d %s | page %d/%d',#data,ST.showRejected and ST.tab==2 and 'rejected / research only' or 'snapshot candidates - reverify',page,pages))
        ui.table.empty:SetText(#data==0 and (ST.tab==1 and 'NO VERIFIED VENDOR DEALS\nOnly exact individual listings with positive margins qualify.\nOlder than 120s? Rescan; never buy from a stale snapshot.' or 'NO TRADE RECOMMENDED\nBuild history over multiple periods. Set costs in item details.\nOpen Rejections / research for reasons; asking prices do not prove demand.') or '')
        for i=1,5 do
            local row=rows[i]; local d=data[(page-1)*5+i]; row.deal=d
            if d then
                row:Show(); row.labels[1]:SetText(d.name); row.labels[2]:SetText(d.count); row.labels[3]:SetText(ST.money(d.buyout))
                row.labels[4]:SetText(ST.money(d.value)); row.labels[5]:SetText(ST.money(d.profit)); row.labels[6]:SetText(d.roi and string.format('%.0f%%',d.roi*100) or '?')
                row.labels[7]:SetText(time()-(d.observed or 0)>120 and 'STALE' or (d.score or (d.executable and 'Check' or 'Research')))
            else row:Hide() end
        end
    end
end
local function build()
    ui=CreateFrame('Frame','FORGEStockTraderFrame',AuctionHouseFrame,'BackdropTemplate'); ST.ui=ui
    ui:SetSize(676,421); ui:SetPoint('TOPLEFT',AuctionHouseFrame,'TOPLEFT',30,-39); ui:SetFrameLevel(AuctionHouseFrame:GetFrameLevel()+15); ui:EnableMouse(true)
    ui:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=12,insets={left=3,right=3,top=3,bottom=3}})
    ui:SetBackdropColor(.045,.055,.07,.99); ui:SetBackdropBorderColor(.55,.43,.23,1)
    label(ui,16,-8,630,'FORGE StockTrader  |  QUANTUM 0.3.0','GameFontNormalLarge'):SetTextColor(1,.78,.33)
    label(ui,18,-31,630,'NOVYXFORGE.COM  /  BUY LOW. SELL HIGH. PROTECT YOUR GOLD.')
    ui.tabs={button(ui,16,-57,130,'Vendor Sell',function()ST.tab=1; ST.showRejected=false; panel=nil; page=1; ST.Refresh()end),button(ui,150,-57,130,'AH Koopjes',function()ST.tab=2; panel=nil; page=1; ST.Refresh()end)}
    button(ui,290,-57,90,'Risk / filters',function()panel=panel=='settings' and nil or 'settings'; ST.Refresh()end)
    ui.cancel=button(ui,390,-57,75,'Cancel',ST.Cancel); ui.scan=button(ui,472,-57,186,'SCAN AH',function()panel=nil; ST.Start('browse')end)
    ui.banner=CreateFrame('Frame',nil,ui); ui.banner:SetPoint('TOPLEFT',16,-89); ui.banner:SetSize(642,26)
    ui.banner.bg=ui.banner:CreateTexture(nil,'BACKGROUND'); ui.banner.bg:SetAllPoints(); ui.banner.caption=label(ui.banner,8,-3,625,'','GameFontNormal')
    ui.status=label(ui,18,-119,638,''); ui.status:SetHeight(32)
    ui.last=label(ui,18,-153,640,''); ui.note=label(ui,18,-385,638,''); ui.note:SetHeight(30)
    ui.reject=button(ui,16,-177,170,'Rejections / research',function()ST.showRejected=not ST.showRejected; page=1; panel=nil; ST.Refresh()end)
    ui.journal=button(ui,194,-177,100,'Journal',function()panel=panel=='journal' and nil or 'journal'; ST.Refresh()end)
    ui.table=CreateFrame('Frame',nil,ui); ui.table:SetAllPoints()
    ui.table.count=label(ui.table,310,-178,345,'')
    local pos={18,213,254,349,444,546,600}; local widths={190,36,90,90,98,49,55}
    local headings={'Item','Qty','Buyout','Value','Profit','ROI','Score'}; local fields={'name','count','buyout','value','profit','roi','score'}
    for i=1,7 do local index=i; button(ui.table,pos[i],-207,widths[i],headings[i],function() if sort==fields[index] then ascending=not ascending else sort=fields[index]; ascending=false end; ST.Refresh()end) end
    for i=1,5 do
        local r=CreateFrame('Button',nil,ui.table); r:SetPoint('TOPLEFT',16,-235-(i-1)*25); r:SetSize(642,24)
        r.bg=r:CreateTexture(nil,'BACKGROUND'); r.bg:SetAllPoints(); r.bg:SetColorTexture(.18,.18,.2,i%2==0 and .7 or .35)
        r.labels={}; for col=1,7 do r.labels[col]=label(r,pos[col]-16,-2,widths[col]-4,'') end
        r:SetScript('OnEnter',function(self)if self.deal then tip(self.deal)end end); r:SetScript('OnLeave',function()GameTooltip:Hide()end)
        r:SetScript('OnClick',function(self)ST.selected=self.deal; panel='detail'; ui.detail.paid:SetText(tostring(self.deal.buyout)); ST.Refresh()end); rows[i]=r
    end
    ui.table.empty=label(ui.table,22,-243,625,''); ui.table.empty:SetHeight(95)
    button(ui.table,16,-361,60,'<',function()page=math.max(1,page-1); ST.Refresh()end); button(ui.table,80,-361,60,'>',function()page=page+1; ST.Refresh()end)
    label(ui.table,153,-361,500,'Click for details / live verification. Green margin is not a resale guarantee.')
    ui.detail=CreateFrame('Frame',nil,ui); ui.detail:SetAllPoints()
    ui.detail.title=label(ui.detail,18,-207,635,'','GameFontNormal'); ui.detail.body=label(ui.detail,18,-230,636,''); ui.detail.body:SetHeight(104); ui.detail.body:SetJustifyV('TOP')
    label(ui.detail,18,-336,90,'Fee % (assumed)'); ui.detail.cut=input(ui.detail,113,-337,44)
    label(ui.detail,172,-336,143,'Deposit gold / full stack'); ui.detail.deposit=input(ui.detail,320,-337,68)
    button(ui.detail,400,-335,110,'Save costs',function() if not ST.SetFee(ST.selected,ui.detail.cut:GetText(),ui.detail.deposit:GetText()) then ST.message='Enter valid fee percent and deposit gold.'; ST.Refresh()end end)
    button(ui.detail,520,-335,135,'Back to results',function()panel=nil; ST.Refresh()end)
    ui.detail.verify=button(ui.detail,18,-361,220,'Verify exact live listing',function()ST.Verify(ST.selected)end)
    label(ui.detail,248,-364,84,'Paid (copper)'); ui.detail.paid=input(ui.detail,336,-363,92)
    ui.detail.record=button(ui.detail,442,-361,212,'I bought this: record',function()ST.RecordSelected(ui.detail.paid:GetText())end)
    ui.settings=CreateFrame('Frame',nil,ui); ui.settings:SetAllPoints(); ui.settings.inputs={}
    local settings={{'minVendor','Min vendor profit (copper)'},{'vendorROI','Vendor ROI (fraction)'},{'minMarket','Min AH profit (copper)'},{'marketROI','AH ROI (fraction)'},{'positionCap','Position cap (fraction)'},{'totalCap','Total exposure (fraction)'},{'lossCap','Max loss / gold (fraction)'},{'lossFraction','Max loss / cost (fraction)'},{'discount','Min discount (fraction)'},{'failures','Failed posting attempts'}}
    for i,p in ipairs(settings) do local x=i%2==1 and 18 or 340; local y=-210-math.floor((i-1)/2)*29; label(ui.settings,x,y,222,p[2]); ui.settings.inputs[p[1]]=input(ui.settings,x+225,y,65) end
    button(ui.settings,18,-361,150,'Save risk limits',function()
        local cfg={}; for k,e in pairs(ui.settings.inputs) do
            local n=tonumber(e:GetText()); local valid=n and n>=0 and n<1e10
            if k=='failures' then valid=valid and n<=20 and n==math.floor(n) elseif k~='minVendor' and k~='minMarket' then valid=valid and n<1 end
            if not valid then ST.message='Invalid '..k; ST.Refresh(); return end; cfg[k]=n
        end
        for k,v in pairs(cfg) do ST.db.settings[k]=v end; ST.vendor={}; ST.market={}; ST.message='Limits saved; rescan to recalculate.'; panel=nil; ST.Refresh()
    end)
    button(ui.settings,180,-361,150,'Toggle chat alerts',function()ST.db.settings.alerts=not ST.db.settings.alerts; ST.message='Alerts '..(ST.db.settings.alerts and 'on' or 'off'); ST.Refresh()end)
    button(ui.settings,345,-361,150,'Experimental replicate',function()panel=nil; ST.Start('replicate')end)
    ui.history=CreateFrame('Frame',nil,ui); ui.history:SetAllPoints(); ui.history.summary=label(ui.history,18,-207,635,''); ui.history.summary:SetHeight(40)
    ui.history.entries=label(ui.history,18,-249,635,''); ui.history.entries:SetHeight(66)
    label(ui.history,18,-320,635,'Close entire trade: ID outcome grossCopper feesCopper lostDepositsCopper attempts')
    ui.history.close=input(ui.history,23,-342,620)
    button(ui.history,18,-365,155,'Save actual outcome',function()SlashCmdList.FORGESTOCKTRADER('close '..ui.history.close:GetText()); ST.Refresh()end)
    label(ui.history,183,-365,465,'Outcome: sold, vendored, abandoned. /fst journal shows all records.')
    ui:Hide(); ST.Refresh()
end
function ST.Attach()
    if not ST.open or not AuctionHouseFrame then return end
    ST.InstallHooks()
    if attached then return end
    if not ui then build() end
    lib=LibStub and LibStub('LibAHTab-1-0',true)
    if not lib then ST.message='LibAHTab missing; installation is incomplete.'; ST.Refresh(); return end
    local ok,err=pcall(function()if not lib:DoesIDExist('FORGE_STOCKTRADER') then lib:CreateTab('FORGE_STOCKTRADER',ui,'StockTrader','FORGE StockTrader')end end)
    if ok then attached=true else ST.message='Tab registration failed: '..tostring(err) end; ST.Refresh()
end
function ST.Toggle()
    if not ST.open then print('FORGE StockTrader: Open the Auction House first.'); return end
    ST.Attach(); if attached then lib:SetSelected('FORGE_STOCKTRADER') end
end
