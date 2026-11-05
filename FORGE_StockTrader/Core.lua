local ADDON,ST=...; local M,D=ST.Model,ST.Database
ST.version='0.3.0'; ST.vendor={}; ST.market={}; ST.rejected={}; ST.tab=1; ST.sort='profit'; ST.open=false
ST.message='Open the Auction House. Browse + detail scan checks every supported item key.'
function ST.money(n)
    if type(n)~='number' then return '?' end
    local sign=n<0 and '-' or ''; n=math.floor(math.abs(n))
    return sign..string.format('%dg %02ds %02dc',math.floor(n/10000),math.floor(n/100)%100,n%100)
end
local function database()
    FORGEStockTraderDB,ST.db=D.open(FORGEStockTraderDB,D.market()); D.prune(ST.db,time())
end
local function changed() if ST.Refresh then ST.Refresh() end end
local function itemInfo(link,id)
    if not C_Item or not C_Item.GetItemInfo then return nil end
    local name,full,quality,_,_,_,_,_,_,_,vendor,_,_,bind=C_Item.GetItemInfo(link or id)
    if not name or type(vendor)~='number' then
        if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        return nil
    end
    return {name=name,link=link or full,quality=quality,vendor=vendor,restricted=bind==1 or bind==4}
end
function ST.Resolve(kind,index,key,api)
    local r
    if kind=='detail' then
        local v=api.GetItemSearchResultInfo(key,index)
        if not v then return nil,'Missing item search record' end
        if not v.buyoutAmount or v.buyoutAmount==0 or v.containsOwnerItem or v.containsAccountItem then return false end
        if not v.itemLink or not M.key(v.itemLink) or not M.integer(v.auctionID) then return nil,'Missing exact variant or auction ID' end
        r={id=key.itemID,key=M.key(v.itemLink),link=v.itemLink,count=v.quantity,buyout=v.buyoutAmount,auctionID=v.auctionID,
           itemKey=key,executable=true,source='item-search'}
    elseif kind=='commodity' then
        local v=api.GetCommoditySearchResultInfo(key.itemID,index)
        if not v then return nil,'Missing commodity record' end
        if v.containsOwnerItem then return false end
        -- Commodity depth does not establish an executable quote. Never vendor-arbitrage it.
        r={id=key.itemID,key='commodity:'..key.itemID,count=v.quantity,buyout=v.unitPrice*v.quantity,auctionID=v.auctionID,
            itemKey=key,executable=false,source='commodity-depth'}
    else
        local name,_,count,quality,_,_,_,_,_,buyout,_,_,_,_,_,sale,id,all=api.GetReplicateItemInfo(index)
        if buyout==0 or (sale and sale~=0) then return false end
        if not id or all~=true then return nil,'Replicate record incomplete' end
        local link=api.GetReplicateItemLink(index)
        if not M.key(link) then return nil,'Replicate item link missing' end
        r={id=id,key=M.key(link),link=link,count=count,buyout=buyout,executable=false,source='replicate'}
    end
    local info=itemInfo(r.link,r.id); if not info then return nil,'Waiting for item information' end
    r.name,r.quality,r.vendor,r.restricted=info.name,info.quality,info.vendor,info.restricted
    r.link=r.link or info.link; r.observed=time()
    return r
end
function ST.Evaluate(row,history)
    if row.observed and time()-row.observed>120 then return nil,'STALE DATA: reverify the listing' end
    local cfg=ST.db.settings; local p,reason=M.prices(history,time())
    if not p then return nil,reason end
    local total,position=D.exposure(ST.db,row.key)
    return M.risk(row,p,cfg,GetMoney(),total,position,ST.db.fees[row.key])
end
local function merge(row,calc)
    local d={}; for k,v in pairs(row) do d[k]=v end; for k,v in pairs(calc) do d[k]=v end; return d
end
function ST.BeginAnalysis(scan)
    local keys={}; for key in pairs(scan.groups) do keys[#keys+1]=key end
    local history={}; for k,h in pairs(ST.db.history) do local c={}; for i,o in ipairs(h) do c[i]=o end; history[k]=c end
    ST.analysis={scan=scan,keys=keys,index=1,vendor={},market={},rejected={},staged={history=history}}
    scan:set('VALIDATING','Pricing and risk validation')
end
local function analyzeTick()
    local a=ST.analysis; if not a then return end
    for pass=1,1 do
        local key=a.keys[a.index]
        if not key then
            ST.db.history=a.staged.history
            D.prune(ST.db,time()); ST.db.lastScan=time(); ST.vendor=a.vendor; ST.market=a.market; ST.rejected=a.rejected
            ST.analysis=nil; ST.scan:set('COMPLETE',string.format('SCAN COMPLETE | %d listings | %d excluded | %d vendor | %d speculative',a.scan.processed,a.scan.excluded,#ST.vendor,#ST.market))
            ST.message=ST.scan.message
            if ST.db.settings.alerts then print('|cff66ee88FORGE StockTrader:|r '..ST.message) end
            changed(); return
        end
        local group=a.scan.groups[key]; local cheapest
        for _,r in ipairs(group) do
            r.depth=#group
            if not cheapest or r.buyout/r.count<cheapest.buyout/cheapest.count then cheapest=r end
            local v=M.vendor(r,ST.db.settings); if v then a.vendor[#a.vendor+1]=merge(r,v) end
        end
        if cheapest then
            local risk,why=ST.Evaluate(cheapest,ST.db.history[key])
            if risk then a.market[#a.market+1]=merge(cheapest,risk)
            else local r=merge(cheapest,{reason=why,profit=0}); a.rejected[#a.rejected+1]=r end
        end
        D.record(a.staged,key,group,cheapest and cheapest.observed or time()); a.index=a.index+1
    end
end
function ST.Start(mode)
    if not ST.open or ST.analysis or (ST.verify and ST.verify.active) then ST.message='Open AH; finish or cancel the current operation first.'; changed(); return end
    if mode=='replicate' and time()<(ST.db.nextReplicate or 0) then ST.message='Replicate cooldown until '..date('%H:%M:%S',ST.db.nextReplicate); changed(); return end
    ST.vendor={}; ST.market={}; ST.rejected={}; ST.selected=nil
    if mode=='replicate' then ST.db.nextReplicate=time()+900 end
    ST.message='Scanning. All item keys are queried with shared throttling; large markets take time.'
    ST.scan:start(mode); changed()
end
function ST.Cancel()
    ST.analysis=nil
    if ST.scan then ST.scan:stop('CANCELLED','Cancelled; no new history committed') end
    if ST.verify then ST.verify:stop('CANCELLED','Verification cancelled') end
    ST.message='Cancelled'; changed()
end
function ST.Verify(row)
    if not row or not ST.open or ST.scan.active or ST.analysis or (ST.verify and ST.verify.active) then ST.message='Finish the scan before verifying a listing.'; changed(); return end
    if not row.itemKey then ST.message='Snapshot lacks exact search key. Search manually; NOT VERIFIED.'; changed(); return end
    row.verification='VERIFYING'; ST.selected=row; local verifyTab=ST.tab
    local v=ST.Scanner.new(C_AuctionHouse,GetTime,ST.Resolve,function(v) if not v.active and v.state~='VALIDATING' then ST.message=v.message end; changed() end); ST.verify=v; v.lastRequest=ST.scan.lastRequest; v.lastExternal=ST.scan.lastExternal
    v:start('browse'); v.request=nil; v.keys={{itemKey=row.itemKey}}; v.keyIndex=0; v:nextKey()
    v.onComplete=function(s)
        local found
        for _,live in ipairs(s.rows) do
            if live.key==row.key and live.auctionID==row.auctionID and live.count==row.count then found=live; break end
        end
        if not found then row.verification='STALE OPPORTUNITY'
        else
            found.depth=#(s.groups[found.key] or {}); found.observed=time()
            local calc,reason
            if verifyTab==1 then calc,reason=M.vendor(found,ST.db.settings) else calc,reason=ST.Evaluate(found,ST.db.history[found.key]) end
            if not calc or (row.safe and found.buyout>row.safe) then row.verification='DO NOT BUY: '..(reason or 'Price exceeds previous limit')
            else
                for k,value in pairs(found) do row[k]=value end; for k,value in pairs(calc) do row[k]=value end
                row.verification='VERIFIED NOW - buy manually in native AH'; row.verifiedAt=time()
            end
        end
        s:set('COMPLETE',row.verification); ST.message=row.verification; changed()
    end
end
function ST.SetFee(row,cut,deposit)
    cut,deposit=tonumber(cut),tonumber(deposit)
    if not row or not cut or not deposit or cut<0 or cut>=100 or deposit<0 then return false end
    ST.vendor={}; ST.market={}
    ST.db.fees[row.key]={cutBP=math.floor(cut*100+.5),deposit=math.ceil(deposit*10000),source='User scenario',at=time()}
    ST.message='Cost assumptions saved for this exact variant/stack quantity. Rescan to reassess.'
    ST.db.fees[row.key].quantity=row.count; changed(); return true
end
function ST.RecordSelected(actualCost)
    local r=ST.selected
    if not r then return end
    local actual=tonumber(actualCost) or r.buyout
    if not M.integer(actual) or actual<1 then ST.message='Actual purchase must be positive integer copper.'; changed(); return end
    local copy=merge(r,{}); copy.buyout=actual
    local t,why=D.acquire(ST.db,copy,time())
    ST.message=t and ('Manual purchase recorded as trade #'..t.id..'. Only record purchases you actually made.') or why; changed()
end
local function commands(msg)
    local words={}; for w in (msg or ''):gmatch('%S+') do words[#words+1]=w end
    if words[1]=='probability' then
        local p=tonumber(words[2])
        if words[2]=='off' then ST.db.settings.probability=nil elseif p and p>=0 and p<=1 then ST.db.settings.probability=p else print('Use /fst probability 0..1 or off; this is a hypothetical scenario.'); return end
        ST.market={}; ST.message='Probability scenario updated. Rescan. This is NOT measured sale probability.'; changed()
    elseif words[1]=='close' then
        local t,err=D.close(ST.db,tonumber(words[2]),words[3],tonumber(words[4]),tonumber(words[5]),tonumber(words[6]),tonumber(words[7]),time())
        print(t and ('Trade #'..t.id..': '..ST.money(t.profit)) or (err or 'Usage: /fst close ID sold|vendored|abandoned gross fees lostDeposits attempts (copper)'))
    elseif words[1]=='set' and D.defaults[words[2]]~=nil then
        local key=words[2]; local n=tonumber(words[3])
        if key=='alerts' then ST.db.settings.alerts=words[3]=='on'
        elseif n and n>=0 and n<1e10 and ((key=='minVendor' or key=='minMarket') or (key=='failures' and n<=20 and n==math.floor(n)) or (n<1)) then ST.db.settings[key]=n
        else print('Invalid setting. Fractions must be <1; money is copper; failures 0-20.'); return end
        ST.message='Setting changed. Rescan to recalculate candidates.'; ST.vendor={}; ST.market={}; changed()
    elseif words[1]=='journal' then
        for _,t in ipairs(ST.db.journal) do print('#'..t.id..' '..t.name..' '..t.outcome..' '..ST.money(t.profit or -t.purchase)) end
    elseif words[1]=='replicate' then ST.Start('replicate')
    else ST.Toggle() end
end
local f=CreateFrame('Frame'); ST.events=f
for _,event in ipairs({'ADDON_LOADED','AUCTION_HOUSE_SHOW','AUCTION_HOUSE_CLOSED','REPLICATE_ITEM_LIST_UPDATE','AUCTION_HOUSE_BROWSE_RESULTS_UPDATED','AUCTION_HOUSE_BROWSE_RESULTS_ADDED','ITEM_SEARCH_RESULTS_UPDATED','ITEM_SEARCH_RESULTS_ADDED','COMMODITY_SEARCH_RESULTS_UPDATED'}) do f:RegisterEvent(event) end
f:SetScript('OnEvent',function(_,event,arg)
    if event=='ADDON_LOADED' and arg==ADDON then
        database(); ST.scan=ST.Scanner.new(C_AuctionHouse or {},GetTime,ST.Resolve,changed); ST.scan.onComplete=ST.BeginAnalysis
        SLASH_FORGESTOCKTRADER1='/fst'; SLASH_FORGESTOCKTRADER2='/stocktrader'; SlashCmdList.FORGESTOCKTRADER=commands
    elseif event=='AUCTION_HOUSE_SHOW' then
        ST.open=true; if not ST.db then database() end
        ST.scan.api=C_AuctionHouse or {}; ST.Attach(); changed()
    elseif event=='AUCTION_HOUSE_CLOSED' then ST.open=false; ST.Cancel()
    else
        if ST.scan then ST.scan:event(event,arg) end
        if ST.verify then ST.verify:event(event,arg) end
    end
end)
local elapsed=0
f:SetScript('OnUpdate',function(_,dt)
    elapsed=elapsed+dt; if elapsed<.1 then return end; elapsed=0
    local ok,err=pcall(function()
        if ST.scan then ST.scan:tick() end
        if ST.verify then ST.verify:tick() end
        analyzeTick()
    end)
    if not ok then ST.analysis=nil; if ST.scan then ST.scan:stop('ERROR',tostring(err)) end end
    if ST.scan and (ST.scan.active or ST.analysis or (ST.verify and ST.verify.active)) then changed() end
end)
function ST.InstallHooks()
    if ST.hooked or not hooksecurefunc or not C_AuctionHouse then return end
    ST.hooked=true
    for _,name in ipairs({'SendBrowseQuery','RequestMoreBrowseResults','SendSearchQuery','SendSellSearchQuery','RequestMoreItemSearchResults','RequestMoreCommoditySearchResults','ReplicateItems','SearchForItemKeys','SearchForFavorites','RefreshItemSearchResults','RefreshCommoditySearchResults'}) do
        if type(C_AuctionHouse[name])=='function' then
            hooksecurefunc(C_AuctionHouse,name,function()
                if (ST.scan and ST.scan.ownRequest) or (ST.verify and ST.verify.ownRequest) then return end
                if ST.scan then ST.scan:external() end
                if ST.verify then ST.verify:external() end
                if ST.analysis then ST.analysis=nil; ST.scan:stop('CANCELLED','Another AH search interrupted validation') end
            end)
        end
    end
end
