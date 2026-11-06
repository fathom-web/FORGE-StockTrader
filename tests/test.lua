local tests,passed={},0
local function test(name,fn) tests[#tests+1]={name,fn} end
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
local function near(a,b) assert(math.abs(a-b)<.00001,tostring(a)..' not near '..b) end
local ST={}
for _,name in ipairs({'Model','Database','Scanner'}) do assert(loadfile('FORGE_StockTrader/'..name..'.lua'))('FORGE_StockTrader',ST) end
local M,D,S=ST.Model,ST.Database,ST.Scanner
local function row() return {key='item:1',name='Test',count=5,buyout=500,vendor=150,executable=true,depth=5,auctionID=1,source='item-search'} end
local function cfg()local c={}; for k,v in pairs(D.defaults)do c[k]=v end; return c end
local function hist()return {{at=10000,price=500,signature='a'},{at=21000,price=520,signature='b'},{at=33000,price=510,signature='c'}}end
local now=34000
local prices={conservative=400,base=500,volatility=.1,sample=6}
local fee={cutBP=500,deposit=10,quantity=5}
test('vendor single item',function()local r=row();r.count=1;r.buyout=100;eq(M.vendor(r,{minVendor=0}).profit,50)end)
test('vendor full stack and ROI',function()local v=M.vendor(row(),cfg());eq(v.profit,250);near(v.roi,.5);eq(v.perItem,50)end)
test('vendor zero and missing value',function()for _,v in ipairs({0,-1,'bad'})do local r=row();r.vendor=v;eq(M.vendor(r,cfg()),nil)end;local r=row();r.vendor=nil;eq(M.vendor(r,cfg()),nil)end)
test('no executable buyout or identity',function()for _,field in ipairs({'executable','key','buyout'})do local r=row();r[field]=nil;eq(M.vendor(r,cfg()),nil)end end)
test('zero and fractional stack rejected',function()for _,n in ipairs({0,1.1})do local r=row();r.count=n;eq(M.vendor(r,cfg()),nil)end end)
test('vendor integer cost and restrictions',function()local r=row();r.extra=249;eq(M.vendor(r,{minVendor=0}).profit,1);r.extra=250;eq(M.vendor(r,cfg()),nil);r.extra=0;r.restricted=true;eq(M.vendor(r,cfg()),nil)end)
test('median even and odd',function()eq(M.quantile({1,3,2},.5),2);eq(M.quantile({1,5},.5),3)end)
test('weighted median',function()eq(M.weightedMedian({{price=10,weight=10},{price=100,weight=1}}),10)end)
test('history yields conservative lower bound',function()local p=M.prices(hist(),now);assert(p.conservative<p.base);eq(p.confidence,'Low')end)
test('missing or thin history',function()eq(M.prices({},now),nil);eq(M.prices({hist()[1]},now),nil)end)
test('unchanged fingerprints not independent',function()local h=hist();h[2].signature='a';eq(M.prices(h,now),nil)end)
test('extreme high outlier cannot inflate value',function()local h=hist();h[#h+1]={price=10000000,signature='d',at=33500};local p=M.prices(h,now);assert(p and p.base<600)end)
test('history expiry and stale reference',function()eq(M.prices(hist(),now+8*86400),nil);eq(M.prices(hist(),now+86400),nil)end)
test('future history excluded',function()eq(M.prices(hist(),20000),nil)end)
test('declining prices reject',function()local h=hist();h[1].price=1000;h[2].price=900;h[3].price=700;eq(M.prices(h,now),nil)end)
test('short history span rejected',function()local h=hist();h[1].at=31000;eq(M.prices(h,now),nil)end)
test('wrong variant stays distinct',function()assert(M.key('|Hitem:1:0:1|h[x]|h')~=M.key('|Hitem:1:0:2|h[x]|h'))end)
test('break even minimal integer copper',function()for cost=1,100 do for _,bp in ipairs({0,500,1500,9999})do local n=M.breakEven(cost,bp);assert(M.net(n,bp)>=cost);assert(n==0 or M.net(n-1,bp)<cost)end end end)
test('fee conservative rounding',function()eq(M.net(1,500),0);eq(M.net(101,500),95)end)
test('deposit refunded on success, lost on failure',function()local c=cfg();c.minMarket=1;local r=M.risk(row(),prices,c,100000,0,0,fee);assert(r);eq(r.successProfit,1400);eq(r.profit,1380);eq(r.lostDeposits,20);eq(r.oneFailure,1105)end)
test('unknown fees hard rejection',function()eq(M.risk(row(),prices,cfg(),1e6,0,0,nil),nil)end)
test('mismatched deposit stack rejected',function()local f={cutBP=500,deposit=10,quantity=1};eq(M.risk(row(),prices,cfg(),1e6,0,0,f),nil)end)
test('negative EV scenario',function()eq(M.ev(.2,100,-100),-60);eq(M.ev(2,100,-100),nil)end)
test('position and total caps',function()local c=cfg();c.minMarket=1;eq(M.risk(row(),prices,c,1000,0,0,fee),nil);eq(M.risk(row(),prices,c,100000,24900,0,fee),nil);eq(M.risk(row(),prices,c,100000,0,9950,fee),nil)end)
test('vendor downside rejects excess risk',function()local c=cfg();c.minMarket=1;local r=row();r.vendor=1;eq(M.risk(r,prices,c,100000,0,0,fee),nil)end)
test('safe price respects ROI and discount',function()local c=cfg();c.minMarket=1;local r=M.risk(row(),prices,c,100000,0,0,fee);assert(r.safe>=500);assert(r.safe<=1750);assert((1900-20-r.safe)/r.safe>=.3)end)
test('scenario declines use whole stack',function()local c=cfg();c.minMarket=1;local r=M.risk(row(),prices,c,100000,0,0,fee);eq(r.scenarios[5].profit,810)end)
test('thin depth rejected',function()local c=cfg();c.minMarket=1;local r=row();r.depth=2;eq(M.risk(r,prices,c,100000,0,0,fee),nil)end)
test('migration keeps old data but isolates markets',function()local old={realms={legacy={history={saved=1}}}};local root,d=D.open(old,'EU:PVE');eq(root.realms.legacy.history.saved,1);eq(root.schema,3);local _,other=D.open(root,'US:PVE');assert(d~=other)end)
test('corruption recovery',function()local root,d=D.open({markets={m={history='bad',settings={positionCap=10}}}},'m');eq(d.settings.positionCap,.1);d.history.bad={false,{at='x'}};D.prune(d,now);eq(d.history.bad,nil)end)
test('record skips unchanged observations',function()local _,d=D.open({},'m');local g={row(),row(),row()};D.record(d,'a',g,now);D.record(d,'a',g,now+2000);eq(#d.history.a,1)end)
test('history retention bounded and old records trimmed',function()local _,d=D.open({},'m');local h={};for i=1,50 do h[i]={at=now+i,price=1,signature=tostring(i)}end;d.history.a=h;D.prune(d,now+100);eq(#d.history.a,24);D.prune(d,now+31*86400);eq(d.history.a,nil)end)
test('manual journal exposure and realized results',function()local _,d=D.open({},'m');local t=D.acquire(d,row(),100);eq(D.exposure(d,'item:1'),500);D.close(d,t.id,'sold',1000,50,20,2,200);eq(D.exposure(d),0);local p=D.performance(d);eq(p.net,430);eq(p.winRate,1);eq(p.holding,100)end)
test('journal no fake win rate',function()local _,d=D.open({},'m');D.acquire(d,row(),100);eq(D.performance(d).winRate,nil);eq(D.close(d,1,'sold',nil,0,0,0,200),nil)end)
test('journal tracks losses and abandoned outcome',function()local _,d=D.open({},'m');D.acquire(d,row(),100);D.close(d,1,'abandoned',0,0,10,1,200);local p=D.performance(d);eq(p.net,-510);eq(p.largestLoss,-510);eq(p.averageLoss,-510)end)
local function scanner(options)
    options=options or {};local t=0;local calls={}; local key={itemID=1,itemLevel=0,itemSuffix=0,battlePetSpeciesID=0}
    local api={IsThrottledMessageSystemReady=function()return not options.throttled end,
        SendBrowseQuery=function()calls[#calls+1]='browse';if options.fail then error('API failed')end end,
        HasFullBrowseResults=function()return not options.more end,GetBrowseResults=function()return options.empty and {} or {{itemKey=key}} end,
        RequestMoreBrowseResults=function()calls[#calls+1]='more'end,SendSearchQuery=function()calls[#calls+1]='search'end,
        HasFullItemSearchResults=function()return true end,GetNumItemSearchResults=function()return options.count or 1 end,
        ReplicateItems=function()calls[#calls+1]='replicate'end,GetNumReplicateItems=function()return options.count or 0 end}
    local s=S.new(api,function()return t end,function(_,i)local r=row();r.auctionID=i;if options.missing then return nil end;return r end)
    local function tick(dt)t=t+(dt or .1);s:tick()end
    return s,tick,calls,key,options
end
local function complete(s,tick,key)
    s:start();tick(2);s:event('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED');tick();tick(2);s:event('ITEM_SEARCH_RESULTS_UPDATED',key)
    for i=1,10 do tick()end
end
test('successful scan',function()local s,t,_,k=scanner();complete(s,t,k);eq(s.state,'COMPLETE');eq(#s.rows,1)end)
test('valid empty scan',function()local s,t=scanner({empty=true});s:start();t(2);s:event('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED');t();t();eq(s.state,'COMPLETE');eq(s.processed,0)end)
test('throttle queues rather than spams',function()local s,t,c=scanner({throttled=true});s:start();t(2);eq(s.state,'THROTTLED');eq(#c,0);t(50);eq(s.state,'TIMEOUT')end)
test('request timeout not success',function()local s,t=scanner();s:start();t(2);t(46);eq(s.state,'TIMEOUT')end)
test('API exception becomes error',function()local s,t=scanner({fail=true});s:start();t(2);eq(s.state,'ERROR')end)
test('repeated completion ignored',function()local s,t,_,k=scanner();complete(s,t,k);s:event('ITEM_SEARCH_RESULTS_UPDATED',k);t();eq(#s.rows,1);eq(s.state,'COMPLETE')end)
test('incomplete cache fails',function()local s,t,_,k=scanner({missing=true});complete(s,t,k);t(9);eq(s.state,'ERROR');assert(s.incomplete>0)end)
test('delayed cache resolves',function()local s,t,_,k,o=scanner({missing=true});complete(s,t,k);o.missing=false;t();t();t();eq(s.state,'COMPLETE')end)
test('external query cancels without results',function()local s,t=scanner();s:start();t(2);s:external();eq(s.state,'CANCELLED');assert(not s.active)end)
test('cancel and reopen restart',function()local s,t,_,k=scanner();s:start();t(2);s:stop('CANCELLED','closed');complete(s,t,k);eq(s.state,'COMPLETE')end)
test('large snapshot bounded per tick',function()local s,t,_,k=scanner({count=10000});s:start();t(2);s:event('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED');t();t(2);s:event('ITEM_SEARCH_RESULTS_UPDATED',k);t();eq(s.processed,100);assert(s.active)end)
test('replicate requires event including empty',function()local s,t=scanner();s:start('replicate');t(2);eq(s.state,'RECEIVING');s:event('REPLICATE_ITEM_LIST_UPDATE');t();t();eq(s.state,'COMPLETE')end)
test('browse paging only one request at a time',function()local s,t,c,_,o=scanner({more=true});s:start();t(2);s:event('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED');s:event('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED');t(1);eq(#c,1);t(1);eq(c[2],'more');o.more=false;s:event('AUCTION_HOUSE_BROWSE_RESULTS_ADDED');t();eq(#s.keys,1)end)
-- WoW-native frame mocks exercise actual UI and bundled LibAHTab, not just model code.
local clock=0; local epoch=100000; local created={}; local chat={}
function GetTime()return clock end; function time()return epoch end; date=os.date
function GetBuildInfo()return '1.60.1','70755','date',16001 end
function GetCurrentRegion()return 3 end; function GetRealmName()return 'PvE'end;function UnitFactionGroup()return 'Horde'end;function GetMoney()return 100000 end
strmatch=string.match; WOW_PROJECT_ID=1;WOW_PROJECT_MAINLINE=1;SlashCmdList={}
local noop=function()end
local frameMethods={}
function frameMethods:SetScript(k,v)self.scripts[k]=v end
function frameMethods:SetText(t)self.text=t end;function frameMethods:GetText()return self.text or ''end
function frameMethods:SetSize(w,h)self.width=w;self.height=h end
function frameMethods:SetWidth(w)self.width=w end;function frameMethods:SetHeight(h)self.height=h end
function frameMethods:SetPoint(point,relative,relativePoint,x,y) self.anchor={point,relative,relativePoint,x,y} end
function frameMethods:SetAllPoints(relative)self.allPoints=relative or self.parent end
function frameMethods:SetColorTexture(...)self.fill={...}end
function frameMethods:SetTextColor(...)self.textColor={...}end
function frameMethods:SetBackdropColor(...)self.backdrop={...}end
function frameMethods:SetJustifyH(v)self.align=v end
function frameMethods:SetMaxLines(v)self.maxLines=v end
function frameMethods:Show()self.shown=true end;function frameMethods:Hide()self.shown=false end
function frameMethods:SetShown(v)self.shown=v end;function frameMethods:IsShown()return self.shown end
function frameMethods:SetEnabled(v)self.enabled=v end;function frameMethods:HasFocus()return false end
function frameMethods:IsObjectType(t)return self.kind==t end;function frameMethods:GetFrameLevel()return 1 end
function frameMethods:RegisterEvent(e)self.events[e]=true end
local function frame(kind,name,parent)
    local f={kind=kind,name=name,parent=parent,scripts={},events={},shown=true}
    setmetatable(f,{__index=function(_,k)return frameMethods[k] or noop end});created[#created+1]=f;if name then _G[name]=f end;return f
end
function CreateFrame(kind,name,parent)return frame(kind,name,parent)end
function frameMethods:CreateTexture()return frame('Texture',nil,self)end
function frameMethods:CreateFontString(_,_,font)local f=frame('FontString',nil,self);f.font=font;return f end
function hooksecurefunc(t,n,fn)local orig=t[n];t[n]=function(...)local result={orig(...)};fn(...);return unpack(result)end end
PanelTemplates_DeselectTab=noop;PanelTemplates_SelectTab=noop;PanelTemplates_TabResize=noop
AuctionHouseFrame=frame('Frame','AuctionHouseFrame');AuctionHouseFrame.Tabs={frame('Button')};AuctionHouseFrame.SetDisplayMode=noop;AuctionHouseFrame.BuyDialog=frame('Frame',nil,AuctionHouseFrame)
GameTooltip=frame('Tooltip');C_AuctionHouse={};C_Item={}
for _,name in ipairs({'Lib/LibStub','Lib/LibAHTab','Costs','Core','Quotes','StockTrader'})do assert(loadfile('FORGE_StockTrader/'..name..'.lua'))('FORGE_StockTrader',ST)end
local function event(e,arg)ST.events.scripts.OnEvent(ST.events,e,arg)end
event('ADDON_LOADED','FORGE_StockTrader');event('AUCTION_HOUSE_SHOW')
test('native AH attachment and no duplicate tab',function()eq(ST.ui.parent,AuctionHouseFrame);local lib=LibStub('LibAHTab-1-0');eq(#lib.internalState.Tabs,1);ST.Attach();event('AUCTION_HOUSE_SHOW');eq(#lib.internalState.Tabs,1)end)
test('exactly two trading tabs and switching',function()eq(#ST.ui.tabs,2);ST.ui.tabs[2].scripts.OnClick();eq(ST.tab,2);ST.ui.tabs[1].scripts.OnClick();eq(ST.tab,1)end)
test('UI shows scan error and completion',function()ST.scan:set('ERROR','test failure');ST.Refresh();eq(ST.ui.banner.caption.text,'SCAN FAILED');ST.scan:set('COMPLETE','done');ST.Refresh();eq(ST.ui.banner.caption.text,'SCAN COMPLETE')end)
test('UI sorts actual rows',function()ST.vendor={{name='A',profit=1,auctionID=1},{name='B',profit=5,auctionID=2}};local r=ST.VisibleRows();eq(r[1].profit,5);ST.vendor={}end)
test('closing AH cancels pending scanner',function()ST.scan.active=true;event('AUCTION_HOUSE_CLOSED');eq(ST.scan.state,'CANCELLED');assert(not ST.open);event('AUCTION_HOUSE_SHOW');assert(ST.open)end)
test('TOC files exist and compile',function()for line in io.lines('FORGE_StockTrader/FORGE_StockTrader.toc')do if line:match('%.lua$')then assert(loadfile('FORGE_StockTrader/'..line))end end end)
test('negative user probability scenario rejects',function()
    local c=cfg();c.minMarket=1;c.probability=0;local r=row();r.vendor=70
    eq(M.risk(r,prices,c,100000,0,0,fee),nil)
end)
test('position sizing never invents extra purchasable stacks',function()
    local c=cfg();c.minMarket=1;eq(M.risk(row(),prices,c,100000,0,0,fee).maxQuantity,5)
end)
local key={itemID=1,itemLevel=0,itemSuffix=0,battlePetSpeciesID=0}
local livePrice,liveCount,liveID=500,1,1
local function setupAPI()
    C_Item.GetItemInfo=function()return 'Test','|Hitem:1|h[Test]|h',1,1,1,'','',20,'',1,750,0,0,0 end
    C_AuctionHouse.IsThrottledMessageSystemReady=function()return true end
    C_AuctionHouse.SendBrowseQuery=noop; C_AuctionHouse.SendSearchQuery=noop
    C_AuctionHouse.HasFullBrowseResults=function()return true end
    C_AuctionHouse.GetBrowseResults=function()return {{itemKey=key}}end
    C_AuctionHouse.HasFullItemSearchResults=function()return true end
    C_AuctionHouse.GetNumItemSearchResults=function()return 1 end
    C_AuctionHouse.GetItemSearchResultInfo=function()return {itemLink='|Hitem:1|h[Test]|h',quantity=liveCount,buyoutAmount=livePrice,auctionID=liveID,itemKey=key}end
    ST.hooked=nil; ST.InstallHooks(); ST.scan.api=C_AuctionHouse
end
local function update(n)
    clock=clock+(n or .2);epoch=epoch+math.ceil(n or .2);ST.events.scripts.OnUpdate(nil,n or .2)
end
local function fullCoreScan()
    ST.Start('browse');update(2);event('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED');update();update(2);event('ITEM_SEARCH_RESULTS_UPDATED',key)
    for i=1,8 do update()end
end
test('core real resolver pipeline publishes vendor only after validation',function()
    setupAPI(); ST.db.settings.minVendor=100;fullCoreScan();eq(ST.scan.state,'COMPLETE');eq(#ST.vendor,1);eq(ST.vendor[1].profit,250);assert(ST.db.lastScan)
end)
test('live recheck higher price becomes DO NOT BUY',function()
    local d=ST.vendor[1];ST.tab=1;livePrice=1000;ST.Verify(d);update(2);event('ITEM_SEARCH_RESULTS_UPDATED',key);for i=1,4 do update()end
    assert(d.verification:match('DO NOT BUY'));livePrice=500
end)
test('live recheck missing exact auction is stale',function()
    local d=ST.vendor[1];liveID=99;ST.Verify(d);update(2);event('ITEM_SEARCH_RESULTS_UPDATED',key);for i=1,4 do update()end
    eq(d.verification,'STALE OPPORTUNITY');liveID=1
end)
test('live recheck still valid updates exact listing',function()
    local d=ST.vendor[1];ST.Verify(d);update(2);event('ITEM_SEARCH_RESULTS_UPDATED',key);for i=1,4 do update()end
    assert(d.verification:match('VERIFIED NOW'));eq(d.profit,250)
end)
test('commodity aggregate cannot become verified vendor deal',function()
    C_AuctionHouse.GetCommoditySearchResultInfo=function()return {quantity=5,unitPrice=10,auctionID=10}end
    local r=ST.Resolve('commodity',1,key,C_AuctionHouse);assert(r);eq(r.executable,false);eq(M.vendor(r,cfg()),nil)
end)
test('failed core scan preserves history and last success',function()
    local before=ST.db.lastScan;local h=ST.db.history;ST.Start('browse');update(2);update(46);eq(ST.scan.state,'TIMEOUT');eq(ST.db.lastScan,before);eq(ST.db.history,h)
end)
test('UI risk filters apply and invalidate old decisions',function()
    ST.ui.settings.inputs.minVendor:SetText('0.09'); ST.ui.settings.inputs.vendorROI:SetText('0')
    for _,spec in ipairs(ST.settingFields)do local k=spec[1];if k~='minVendor' and k~='vendorROI' then ST.ui.settings.inputs[k]:SetText(ST.db.settings[k] and tostring(ST.db.settings[k]/spec[3]) or '')end end
    for _,f in ipairs(created)do if f.text=='Save risk limits' then f.scripts.OnClick()end end
    eq(ST.db.settings.minVendor,900);eq(#ST.vendor,0)
end)
test('UI manual actual purchase amount used in journal',function()
    ST.selected=row();ST.RecordSelected('650');eq(ST.db.journal[#ST.db.journal].purchase,650)
end)
test('priority scan checks vendor lead before exploration',function()
    setupAPI();ST.db.settings.scanLimit=10;ST.db.scanCursor=0
    local keys={};for i=1,20 do keys[i]={itemKey={itemID=i},minPrice=900,totalQuantity=1}end
    keys[19].minPrice=10
    local selected=ST.Prioritize({scope='quick'},keys);eq(#selected,10);eq(selected[1].itemKey.itemID,19)
end)
test('full scope retains all market keys',function()
    local keys={};for i=1,70 do keys[i]={itemKey={itemID=i}}end
    eq(#ST.Prioritize({scope='full'},keys),70)
end)
test('per-key callbacks precede whole-scan completion',function()
    local s,t,_,k=scanner();local calls=0;s.onKey=function(_,groups)calls=calls+1;assert(groups['item:1'])end
    complete(s,t,k);eq(calls,1)
end)
test('pause drains current key, resume finishes scope',function()
    local s,t,_,k=scanner();s:start();t(2);s:event('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED');t();t(2);s:pause();s:event('ITEM_SEARCH_RESULTS_UPDATED',k);t()
    eq(s.state,'PAUSED');eq(s.checkedKeys,1);assert(not s.active);assert(s:resume());t();eq(s.state,'COMPLETE')
end)
test('resume cannot revive cancelled scan',function()local s,t=scanner();s:start();s:stop('CANCELLED');eq(s:resume(),false)end)
test('automatic commodity deposit requires correct quantity and duration',function()
    ST.Costs.reset();local r=row();r.source='commodity-depth';r.id=1
    local a={CalculateCommodityDeposit=function(id,duration,qty)eq(qty,5);eq(duration,2);return 37 end}
    eq(ST.Costs.deposit(r,2,a),37)
end)
test('exact bag variant required for automatic item deposit',function()
    ST.Costs.reset();ItemLocation={CreateFromBagAndSlot=function(_,bag,slot)return {bag=bag,slot=slot}end}
    local bags={GetContainerNumSlots=function()return 1 end,GetContainerItemLink=function()return '|Hitem:1|h[Test]|h'end}
    local api={CalculateItemDeposit=function()return 41 end}
    eq(ST.Costs.deposit(row(),1,api,{},bags),41);ST.Costs.reset()
    bags.GetContainerItemLink=function()return '|Hitem:2|h[Other]|h'end
    eq(ST.Costs.deposit(row(),1,api,{},bags),nil);ItemLocation=nil
end)
test('missing deposit remains unknown, never assumed zero',function()
    ST.Costs.reset();local db={settings={cutBP=500},fees={}};eq(ST.Costs.resolve(db,row()),nil)
end)
test('market fee shared, stack deposit remains quantity specific',function()
    ST.Costs.reset();local db={settings={cutBP=500,duration=1},fees={['item:1']={quantity=5,deposit=10,duration=1}}}
    eq(ST.Costs.resolve(db,row()).cutBP,500);local r=row();r.count=6;eq(ST.Costs.resolve(db,r),nil)
end)
test('duration change invalidates manual deposit',function()
    local db={settings={cutBP=500,duration=2},fees={['item:1']={quantity=5,deposit=10,duration=1}}};eq(ST.Costs.resolve(db,row()),nil)
end)
test('native commodity quote uses server total, not minimum times quantity',function()
    ST.db.settings.minVendor=1;ST.nativeTarget=row();ST.nativeTarget.id=1;ST.nativeTarget.source='commodity-depth';ST.nativeTarget.executable=false
    ST.Quotes.start(1,5);ST.Quotes.event('COMMODITY_PRICE_UPDATED',80,450)
    local r=ST.Quotes.pending.row;eq(r.buyout,450);eq(r.profit,300);eq(r.count,5);assert(r.executable)
end)
test('unrelated quote and stale quote never accepted',function()
    ST.Quotes.start(2,5);eq(ST.Quotes.pending,nil);ST.Quotes.start(1,5);clock=clock+11;ST.Quotes.event('COMMODITY_PRICE_UPDATED',80,450);eq(ST.Quotes.pending,nil)
end)
test('quote cancellation invalidates executable status',function()
    ST.Quotes.start(1,5);ST.Quotes.event('COMMODITY_PRICE_UPDATED',80,450);local r=ST.Quotes.pending.row
    ST.Quotes.invalidate('cancelled');eq(r.executable,false)
end)
test('quotes expire after five seconds and never purchase',function()
    ST.Quotes.start(1,5);ST.Quotes.event('COMMODITY_PRICE_UPDATED',80,450);local r=ST.Quotes.pending.row;clock=clock+6;ST.Quotes.tick();eq(r.executable,false)
    local f=assert(io.open('FORGE_StockTrader/Quotes.lua'));local src=f:read('*a');f:close();assert(not src:match('C_AuctionHouse%.ConfirmCommoditiesPurchase%s*%('))
end)
test('actual versus planned performance uses closed records only',function()
    local _,d=D.open({},'m');local r=row();r.profit=100;D.acquire(d,r,100);D.close(d,1,'sold',700,0,0,0,200)
    local c=D.calibration(d);eq(c.meanError,100);eq(c.sold,1);eq(c.closed,1)
end)
test('duplicate manual purchase click is blocked',function()
    ST.selected=row();local before=#ST.db.journal;ST.RecordSelected('500');ST.RecordSelected('500');eq(#ST.db.journal,before+1)
end)
test('diagnostic log is bounded',function()local s=scanner();for i=1,100 do s:set('IDLE',tostring(i))end;eq(#s.log,60)end)
test('partial key history stays valid after later timeout without full success',function()
    setupAPI();ST.db.settings.minVendor=1;ST.db.history={};ST.scan.wallStarted=time()
    local g={row(),row(),row()};for i,r in ipairs(g)do r.auctionID=i;r.observed=time();r.itemKey=key end
    local before=ST.db.lastScan;ST.KeyComplete(ST.scan,{['item:1']=g});update();assert(ST.db.history['item:1']);ST.scan:stop('TIMEOUT','later key failed');eq(ST.db.lastScan,before)
end)
test('same-scan observations cannot validate their own bargain',function()
    local h=hist();local r=row();r.observed=time();r.referenceBefore=33000
    local result,reason=ST.Evaluate(r,h);eq(result,nil);assert(reason:match('Insufficient') or reason:match('Stale'))
end)
test('Copper Rod price level never becomes an executable stack',function()
    setupAPI()
    livePrice,liveCount=100,3103
    C_Item.GetItemInfo=function() return 'Copper Rod','|Hitem:6217|h[Copper Rod]|h',1,1,1,'','',1,'',1,24,0,0,0 end
    ST.db.settings.minVendor=0
    fullCoreScan()
    eq(ST.scan.state,'COMPLETE');eq(#ST.vendor,0);eq(#ST.market,0);eq(#ST.scan.rows,0)
    local old={id=1,key='item:1',count=3103,buyout=100,itemKey=key,auctionID=1}
    ST.Verify(old);update(2);event('ITEM_SEARCH_RESULTS_UPDATED',key)
    for i=1,4 do update() end
    eq(old.verification,'STALE OPPORTUNITY')
    liveCount=1
    local single=ST.Resolve('detail',1,key,C_AuctionHouse)
    eq(single.vendor*single.count-single.buyout,-76)
    eq(M.vendor(single,ST.db.settings),nil)
end)
test('legacy ambiguous prices isolated on first use only',function()
    local bad={source='item-search',maxStack=3103,price=100/3103}
    local safe={source='item-search',maxStack=1,price=100}
    local root={markets={m={history={rod={bad,safe}},browseReferences={rod=1},journal={{id=7}}}}}
    local _,d=D.open(root,'m')
    eq(#d.history.rod,1);eq(d.history.rod[1],safe);eq(d.pre041PriceArchive.rod[1],bad)
    eq(d.browseReferences.rod,nil);eq(d.journal[1].id,7)
    D.open(root,'m');eq(d.pre041PriceArchive.rod[1],bad)
end)
test('item display uses NPC value independent of speculative resale',function()
    setupAPI()
    liveCount,livePrice=1,100
    local d=ST.Resolve('detail',1,key,C_AuctionHouse)
    eq(d.icon,1)
    d.value=99999
    ST.vendor={d};ST.tab=1;ST.SetPanel('results')
    eq(ST.ui.rows[1].labels[7].text,ST.money(d.vendor))
    ST.Select(d);assert(ST.ui.detail.sell.text:find('NPC total: '..ST.money(d.vendor),1,true))
    d.executable=false;ST.Refresh();assert(ST.ui.detail.sell.text:find('NPC total: --',1,true))
end)
ForgeTest={ST=ST,created=created,frame=frame,setClock=function(t,e)clock=t;epoch=e end}
for _,t in ipairs(tests)do local ok,err=pcall(t[2]);if ok then passed=passed+1;io.write('PASS ',t[1],'\n')else io.write('FAIL ',t[1],': ',tostring(err),'\n')end end
print(string.format('%d/%d tests passed (%s)',passed,#tests,_VERSION));assert(passed==#tests,'Test failures')
