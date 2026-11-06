local ADDON,ST=...; local M,D=ST.Model,ST.Database
ST.version='0.4.2'; ST.vendor={}; ST.market={}; ST.rejected={}; ST.tab=1; ST.sort='profit'; ST.open=false
ST.message='Quick scan checks priority items first. Full scan builds wider price history.'
ST.commodities={}; ST.pendingGroups={}
function ST.money(n)
    if type(n)~='number' then return '?' end
    local sign=n<0 and '-' or ''; n=math.floor(math.abs(n))
    return sign..string.format('%dg %02ds %02dc',math.floor(n/10000),math.floor(n/100)%100,n%100)
end
local function database()
    FORGEStockTraderDB,ST.db=D.open(FORGEStockTraderDB,D.market()); D.prune(ST.db,time())
end
local function changed() ST.dirty=true end
ST.Changed=changed
local function itemInfo(link,id)
    if not C_Item or not C_Item.GetItemInfo then return nil end
    local name,full,quality,_,_,_,_,_,_,icon,vendor,_,_,bind=C_Item.GetItemInfo(link or id)
    if not name or type(vendor)~='number' then
        if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        return nil
    end
    return {name=name,link=link or full,quality=quality,icon=icon,vendor=vendor,restricted=bind==1 or bind==4}
end
function ST.Resolve(kind,index,key,api)
    local r
    if kind=='detail' then
        local v=api.GetItemSearchResultInfo(key,index)
        if not v then return nil,'Missing item search record' end
        if not v.buyoutAmount or v.buyoutAmount==0 or v.containsOwnerItem or v.containsAccountItem then return false end
        if not M.integer(v.quantity) or v.quantity < 1 then
            return nil, 'Missing item search quantity'
        end
        -- Forever can group many units at one displayed buyout. With a single
        -- unit both interpretations agree. Other rows need a confirmed total.
        if v.quantity > 1 then
            return false
        end
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
    r.icon=info.icon
    r.link=r.link or info.link; r.observed=time()
    return r
end
function ST.Evaluate(row,history)
    if row.observed and time()-row.observed>120 then return nil,'STALE DATA: reverify the listing' end
    local prior={}
    for _,o in ipairs(history or {}) do if not row.referenceBefore or o.at<row.referenceBefore then prior[#prior+1]=o end end
    local cfg=ST.db.settings; local p,reason=M.prices(prior,time())
    if not p then return nil,reason end
    local total,position=D.exposure(ST.db,row.key)
    local fee,why=ST.Costs.resolve(ST.db,row); if not fee then return nil,why end
    return M.risk(row,p,cfg,GetMoney(),total,position,fee)
end
local function merge(row,calc)
    local d={}; for k,v in pairs(row) do d[k]=v end; for k,v in pairs(calc) do d[k]=v end; return d
end
-- Priority is discovery only. Browse minima are NEVER execution evidence.
function ST.Prioritize(scan,keys)
    local cursor=ST.db.scanCursor or 0
    for i,r in ipairs(keys) do
        local info=itemInfo(nil,r.itemKey.itemID); local price=tonumber(r.minPrice)
        local score=0
        if info and price and price>0 and info.vendor>price then score=100000+math.min(99999,info.vendor-price) end
        local known=ST.db.browseReferences and ST.db.browseReferences[M.browseKey(r.itemKey)]
        if known and known.at and time()-known.at<86400 and price and price>0 and price<known.price*.7 then score=math.max(score,50000+known.price/price) end
        r.priority=score; r.order=(i-cursor-1)%math.max(1,#keys)
    end
    table.sort(keys,function(a,b)if a.priority==b.priority then return a.order<b.order end; return a.priority>b.priority end)
    if scan.scope=='full' then return keys end
    local selected={}; for i=1,math.min(#keys,ST.db.settings.scanLimit or 60) do selected[i]=keys[i] end
    ST.db.scanCursor=(cursor+#selected)%math.max(1,#keys)
    return selected
end
local function append(target,row,calc)
    target[#target+1]=merge(row,calc or {})
end
local function analyzeGroup(key,group,commit)
    local cheapest
    for _,r in ipairs(group) do
        r.depth=#group; r.referenceBefore=r.referenceBefore or ST.scan.wallStarted
        if not cheapest or r.buyout/r.count<cheapest.buyout/cheapest.count then cheapest=r end
        local vendor=M.vendor(r,ST.db.settings)
        if vendor then append(ST.vendor,r,vendor) end
    end
    if cheapest then
        if cheapest.source=='commodity-depth' then
            append(ST.commodities,cheapest,{reason='Supply only. Open native AH and request a quote for your chosen quantity.'})
        else
            local risk,why=ST.Evaluate(cheapest,ST.db.history[key])
            if risk then append(ST.market,cheapest,risk) else append(ST.rejected,cheapest,{reason=why,profit=0}) end
        end
        if commit then
            -- Each complete key is independently valid; the whole scan may remain partial.
            D.record(ST.db,key,group,cheapest.observed or time())
            ST.db.browseReferences=ST.db.browseReferences or {}
            local bkey=M.browseKey(cheapest.itemKey)
            if bkey then ST.db.browseReferences[bkey]={price=cheapest.buyout/cheapest.count,at=time()} end
        end
    end
end
function ST.KeyComplete(scan,groups)
    for key,group in pairs(groups) do ST.validatedKeys=ST.validatedKeys or {}; ST.validatedKeys[key]=true; ST.pendingGroups[#ST.pendingGroups+1]={key=key,group=group} end
    changed()
end
function ST.BeginAnalysis(scan)
    if scan.mode=='replicate' then ST.KeyComplete(scan,scan.groups) end
    ST.analysis={scan=scan}; scan:set('VALIDATING','Finishing validated item groups')
end
local function analyzeTick()
    local pending=table.remove(ST.pendingGroups,1)
    if pending then analyzeGroup(pending.key,pending.group,true); changed(); return end
    if not ST.analysis then return end
    local a=ST.analysis; ST.analysis=nil; D.prune(ST.db,time()); ST.db.lastScan=time()
    ST.db.lastScope=a.scan.scope or 'full'; ST.db.lastChecked=a.scan.checkedKeys or 0
    a.scan:set('COMPLETE',string.format('%s COMPLETE | %d/%d market keys checked | %d vendor | %d speculative',
        a.scan.scope=='quick' and 'QUICK SCAN' or 'SCAN',a.scan.checkedKeys or 0,a.scan.marketKeys or 0,#ST.vendor,#ST.market))
    ST.message=a.scan.message
    if ST.db.settings.alerts then print('|cff66ee88FORGE StockTrader:|r '..ST.message) end
    changed()
end
function ST.Reassess()
    ST.vendor={}; ST.market={}; ST.rejected={}; ST.commodities={}
    for key,group in pairs(ST.scan.groups or {}) do
        if ST.validatedKeys[key] then analyzeGroup(key,group,false) end
    end
    changed()
end
function ST.Start(mode)
    if not ST.open or ST.scan.active or ST.analysis or (ST.verify and ST.verify.active) then ST.message='Open AH; finish or cancel the current operation first.'; changed(); return end
    if mode=='replicate' and time()<(ST.db.nextReplicate or 0) then ST.message='Replicate cooldown until '..date('%H:%M:%S',ST.db.nextReplicate); changed(); return end
    ST.vendor={}; ST.market={}; ST.rejected={}; ST.commodities={}; ST.selected=nil; ST.pendingGroups={}; ST.validatedKeys={}
    ST.scan.wallStarted=time(); ST.scan.onBrowse=ST.Prioritize; ST.scan.onKey=ST.KeyComplete; ST.scan.scope=mode=='full' and 'full' or 'quick'
    if mode=='replicate' then ST.db.nextReplicate=time()+900 end
    ST.message='Partial results appear after each complete item check. Pause to inspect or verify.'
    ST.scan:start(mode); changed()
end
function ST.Cancel()
    ST.analysis=nil; ST.pendingGroups={}
    if ST.scan then ST.scan:stop('CANCELLED','Cancelled. Complete item checks retained; overall scan is partial.') end
    if ST.verify then ST.verify:stop('CANCELLED','Verification cancelled') end
    if ST.Quotes then ST.Quotes.invalidate('Cancelled') end
    ST.message='Cancelled'; changed()
end
function ST.Verify(row)
    if row and (row.source=='commodity-depth' or row.source=='commodity-quote') then ST.OpenNative(row); return end
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
            found.depth=#(s.groups[found.key] or {}); found.observed=time(); found.referenceBefore=row.referenceBefore
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
    ST.db.settings.cutBP=math.floor(cut*100+.5)
    ST.db.fees[row.key]={cutBP=math.floor(cut*100+.5),deposit=math.ceil(deposit*10000),source='User scenario',duration=ST.db.settings.duration or 1,at=time()}
    ST.message='Market commission saved. Exact stack deposit saved; current results reassessed.'
    ST.db.fees[row.key].quantity=row.count; ST.Reassess(); changed(); return true
end
function ST.RecordSelected(actualCost)
    local r=ST.selected
    if not r then return end
    local actual=tonumber(actualCost) or r.buyout
    if not M.integer(actual) or actual<1 then ST.message='Actual purchase must be positive integer copper.'; changed(); return end
    if r.recorded then ST.message='This selection is already recorded. Select another actual purchase to record it.';changed();return end
    local copy=merge(r,{}); copy.buyout=actual
    local t,why=D.acquire(ST.db,copy,time())
    if t then r.recorded=t.id end
    ST.message=t and ('Manual purchase recorded as trade #'..t.id..'. Only record purchases you actually made.') or why; changed()
end
local function commands(msg)
    local words={}; for w in (msg or ''):gmatch('%S+') do words[#words+1]=w end
    if words[1]=='diag' then
        for _,l in ipairs(ST.scan.log or {}) do print(string.format('%.1f %s %s',l.at,l.state,l.message)) end
    elseif words[1]=='probability' then
        local p=tonumber(words[2])
        if words[2]=='off' then ST.db.settings.probability=nil elseif p and p>=0 and p<=1 then ST.db.settings.probability=p else print('Use /fst probability 0..1 or off; this is a hypothetical scenario.'); return end
        ST.market={}; ST.message='Probability scenario updated. Rescan. This is NOT measured sale probability.'; changed()
    elseif words[1]=='close' then
        local t,err=D.close(ST.db,tonumber(words[2]),words[3],tonumber(words[4]),tonumber(words[5]),tonumber(words[6]),tonumber(words[7]),time())
        print(t and ('Trade #'..t.id..': '..ST.money(t.profit)) or (err or 'Usage: /fst close ID sold|vendored|abandoned gross fees lostDeposits attempts (copper)'))
    elseif words[1]=='set' and D.defaults[words[2]]~=nil then
        local key=words[2]; local n=tonumber(words[3])
        if key=='alerts' then ST.db.settings.alerts=words[3]=='on'
        elseif n and n>=0 and n<1e10 and ((key=='minVendor' or key=='minMarket') or (key=='failures' and n<=20 and n==math.floor(n)) or (key=='scanLimit' and M.integer(n) and n>=10 and n<=300) or (key=='duration' and M.integer(n) and n>=1 and n<=3) or (key~='failures' and key~='scanLimit' and key~='duration' and n<1)) then ST.db.settings[key]=n
        else print('Invalid setting. Fractions must be <1; money is copper; failures 0-20.'); return end
        ST.message='Setting changed. Rescan to recalculate candidates.'; ST.vendor={}; ST.market={}; changed()
    elseif words[1]=='journal' then
        for _,t in ipairs(ST.db.journal) do print('#'..t.id..' '..t.name..' '..t.outcome..' '..ST.money(t.profit or -t.purchase)) end
    elseif words[1]=='replicate' then ST.Start('replicate')
    else ST.Toggle() end
end
ST.validatedKeys={}
local f=CreateFrame('Frame'); ST.events=f
for _,event in ipairs({'ADDON_LOADED','AUCTION_HOUSE_SHOW','AUCTION_HOUSE_CLOSED','REPLICATE_ITEM_LIST_UPDATE','AUCTION_HOUSE_BROWSE_RESULTS_UPDATED','AUCTION_HOUSE_BROWSE_RESULTS_ADDED','ITEM_SEARCH_RESULTS_UPDATED','ITEM_SEARCH_RESULTS_ADDED','COMMODITY_SEARCH_RESULTS_UPDATED','COMMODITY_PRICE_UPDATED','COMMODITY_PRICE_UNAVAILABLE','COMMODITY_PURCHASE_FAILED','COMMODITY_PURCHASE_SUCCEEDED','BAG_UPDATE_DELAYED'}) do f:RegisterEvent(event) end
f:SetScript('OnEvent',function(_,event,arg,arg2)
    if event=='ADDON_LOADED' and arg==ADDON then
        database(); ST.scan=ST.Scanner.new(C_AuctionHouse or {},GetTime,ST.Resolve,changed); ST.scan.onComplete=ST.BeginAnalysis
        SLASH_FORGESTOCKTRADER1='/fst'; SLASH_FORGESTOCKTRADER2='/stocktrader'; SlashCmdList.FORGESTOCKTRADER=commands
    elseif event=='AUCTION_HOUSE_SHOW' then
        ST.open=true; ST.Costs.reset(); if not ST.db then database() end
        ST.scan.api=C_AuctionHouse or {}; ST.Attach(); changed()
    elseif event=='AUCTION_HOUSE_CLOSED' then ST.open=false; ST.Cancel(); if ST.Quotes then ST.Quotes.invalidate('AH closed') end
    elseif event=='BAG_UPDATE_DELAYED' then ST.Costs.reset()
    elseif event=='COMMODITY_PRICE_UPDATED' or event=='COMMODITY_PRICE_UNAVAILABLE' or event=='COMMODITY_PURCHASE_FAILED' or event=='COMMODITY_PURCHASE_SUCCEEDED' then
        ST.Quotes.event(event,arg,arg2)
    else
        if ST.scan then ST.scan:event(event,arg) end
        if ST.verify then ST.verify:event(event,arg) end
    end
end)
local elapsed,displayElapsed=0,0
f:SetScript('OnUpdate',function(_,dt)
    elapsed=elapsed+dt; displayElapsed=displayElapsed+dt
    if displayElapsed>=1 then displayElapsed=0; if ST.open then changed() end end
    if elapsed<.1 then return end; elapsed=0
    local ok,err=pcall(function()
        if ST.scan then ST.scan:tick() end
        if ST.verify then ST.verify:tick() end
        analyzeTick(); if ST.Quotes then ST.Quotes.tick() end
    end)
    if not ok then ST.analysis=nil; if ST.scan then ST.scan:stop('ERROR',tostring(err)) end end
    if ST.dirty and ST.Refresh then ST.dirty=false; ST.Refresh() end
end)
function ST.InstallHooks()
    if ST.hooked or not hooksecurefunc or not C_AuctionHouse then return end
    ST.hooked=true; if ST.Quotes then ST.Quotes.install() end
    for _,name in ipairs({'SendBrowseQuery','RequestMoreBrowseResults','SendSearchQuery','SendSellSearchQuery','RequestMoreItemSearchResults','RequestMoreCommoditySearchResults','ReplicateItems','SearchForItemKeys','SearchForFavorites','RefreshItemSearchResults','RefreshCommoditySearchResults'}) do
        if type(C_AuctionHouse[name])=='function' then
            hooksecurefunc(C_AuctionHouse,name,function()
                if (ST.scan and ST.scan.ownRequest) or (ST.verify and ST.verify.ownRequest) then
                    if ST.scan then ST.scan.lastRequest=GetTime() end
                    if ST.verify then ST.verify.lastRequest=GetTime() end
                    return
                end
                if ST.scan then ST.scan:external() end
                if ST.verify then ST.verify:external() end
                if ST.analysis then ST.analysis=nil; ST.scan:stop('CANCELLED','Another AH search interrupted validation') end
            end)
        end
    end
end
