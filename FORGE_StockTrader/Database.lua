local _,ST=...; local M=ST.Model; local D={}; ST.Database=D
D.defaults={minVendor=100,vendorROI=0,minMarket=10000,marketROI=.3,discount=.3,positionCap=.1,totalCap=.25,lossCap=.02,lossFraction=.5,failures=2,alerts=true}
function D.open(root,market)
    root=type(root)=='table' and root or {}; root.realms=type(root.realms)=='table' and root.realms or {}
    root.markets=type(root.markets)=='table' and root.markets or {}; root.schema=3
    -- Legacy realms remain intact; their market provenance is insufficient for model use.
    local d=root.markets[market]; if type(d)~='table' then d={}; root.markets[market]=d end
    for _,k in ipairs({'history','journal','fees','settings'}) do if type(d[k])~='table' then d[k]={} end end
    for k,v in pairs(D.defaults) do
        if type(d.settings[k])~=type(v) or (type(v)=='number' and (not (d.settings[k]>=0) or d.settings[k]==math.huge)) then d.settings[k]=v end
    end
    for _,k in ipairs({'positionCap','totalCap','marketROI','vendorROI','discount','lossCap','lossFraction'}) do
        if d.settings[k]>=1 then d.settings[k]=D.defaults[k] end
    end
    d.settings.failures=math.min(20,math.floor(d.settings.failures))
    return root,d
end
function D.market()
    local _,_,_,iface=GetBuildInfo()
    return table.concat({GetCurrentRegion and GetCurrentRegion() or 'unknown-region',iface or 'unknown-client',GetRealmName() or 'unknown-ruleset',UnitFactionGroup('player') or 'unknown-faction'},':')
end
function D.prune(d,now)
    local keys={}
    for key,h in pairs(d.history) do
        local keep={}
        if type(h)=='table' then for _,o in ipairs(h) do
            if type(o)=='table' and M.integer(o.at) and o.at<=now and now-o.at<=30*86400 and type(o.price)=='number' and o.price>0 and type(o.signature)=='string' then keep[#keep+1]=o end
        end end
        table.sort(keep,function(a,b)return a.at<b.at end)
        while #keep>24 do table.remove(keep,1) end
        if #keep>0 then d.history[key]=keep; keys[#keys+1]={key=key,at=keep[#keep].at} else d.history[key]=nil end
    end
    table.sort(keys,function(a,b)return a.at>b.at end)
    for i=3001,#keys do d.history[keys[i].key]=nil end
end
function D.record(d,key,group,now)
    if #group<3 then return end
    local signatureParts,values,quantity,unitPrices={}, {},0,{}
    local minStack,maxStack=math.huge,0
    for _,r in ipairs(group) do
        signatureParts[#signatureParts+1]=tostring(r.auctionID or 'snapshot')..':'..r.buyout..':'..r.count
        values[#values+1]={price=r.buyout/r.count,weight=math.min(r.count,20)}; quantity=quantity+r.count
        unitPrices[#unitPrices+1]=r.buyout/r.count; minStack=math.min(minStack,r.count); maxStack=math.max(maxStack,r.count)
    end
    table.sort(signatureParts)
    -- Two bounded modular hashes; provenance is a multiset, not claimed independent sales.
    local h1,h2=0,0
    for _,s in ipairs(signatureParts) do for i=1,#s do h1=(h1*33+s:byte(i))%2147483647; h2=(h2*65599+s:byte(i))%2147483629 end end
    local sig=#group..':'..h1..':'..h2
    local h=d.history[key] or {}
    for _,o in ipairs(h) do if o.signature==sig then return end end
    if #h>0 and now-h[#h].at<1800 then return end
    h[#h+1]={at=now,price=M.weightedMedian(values),low=(function() local n=math.huge; for _,v in ipairs(values) do n=math.min(n,v.price) end; return n end)(),
        q1=M.quantile(unitPrices,.25),q3=M.quantile(unitPrices,.75),minStack=minStack,maxStack=maxStack,signature=sig,quantity=quantity,listings=#group,source=group[1].source or 'unknown',complete=true}
    while #h>24 do table.remove(h,1) end; d.history[key]=h
end
function D.exposure(d,key)
    local total,position=0,0
    for _,t in ipairs(d.journal) do if type(t)=='table' and t.outcome=='held' and M.integer(t.purchase) then
        total=total+t.purchase; if t.key==key then position=position+t.purchase end
    end end
    return total,position
end
function D.acquire(d,row,now)
    if #d.journal>=2000 then return nil,'Journal full; export/archive before recording more trades' end
    if not row.key or not M.integer(row.buyout) or row.buyout<1 then return nil,'Invalid purchase' end
    d.nextTrade=(tonumber(d.nextTrade) or 0)+1
    local t={id=d.nextTrade,key=row.key,name=row.name,quantity=row.count,purchase=row.buyout,at=now,planned=row.value,outcome='held'}
    d.journal[#d.journal+1]=t; return t
end
function D.close(d,id,outcome,gross,fees,lost,attempts,now)
    if outcome~='sold' and outcome~='vendored' and outcome~='abandoned' then return nil,'Invalid outcome' end
    if not M.integer(gross) or not M.integer(fees) or not M.integer(lost) or not M.integer(attempts) then return nil,'Use non-negative integer copper / attempts' end
    if outcome=='abandoned' and gross~=0 then return nil,'Abandoned revenue must be zero' end
    for _,t in ipairs(d.journal) do if t.id==id and t.outcome=='held' then
        t.outcome,t.gross,t.fees,t.lostDeposits,t.attempts,t.closed=outcome,gross,fees,lost,attempts,now
        t.profit=gross-fees-lost-t.purchase; return t
    end end
    return nil,'No open trade with that ID'
end
function D.performance(d)
    local p={wins=0,losses=0,positive=0,negative=0,net=0,largestLoss=0,capital=0,n=0,holding=0}; local returns={}
    for _,t in ipairs(d.journal) do if type(t)=='table' then
        if t.outcome=='held' then p.capital=p.capital+(tonumber(t.purchase) or 0)
        elseif type(t.profit)=='number' and t.purchase and t.purchase>0 and t.closed and t.at then
            p.n=p.n+1; p.net=p.net+t.profit; p.holding=p.holding+t.closed-t.at; returns[#returns+1]=t.profit/t.purchase
            if t.profit>0 then p.wins=p.wins+1; p.positive=p.positive+t.profit elseif t.profit<0 then p.losses=p.losses+1; p.negative=p.negative+t.profit end
            p.largestLoss=math.min(p.largestLoss,t.profit)
        end
    end end
    if p.n>0 then p.winRate=p.wins/p.n; p.medianReturn=M.quantile(returns,.5); p.holding=p.holding/p.n end
    p.averageWin=p.wins>0 and p.positive/p.wins or nil; p.averageLoss=p.losses>0 and p.negative/p.losses or nil
    return p
end
