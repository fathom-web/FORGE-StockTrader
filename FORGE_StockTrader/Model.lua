local _, ST = ...
local M = {}; ST.Model = M
local floor, min, max = math.floor, math.min, math.max
function M.integer(n) return type(n)=='number' and n==n and n>=0 and n<=9007199254740991 and n==floor(n) end
function M.key(link) return type(link)=='string' and link:match('|H(item:[^|]+)|h') or nil end
function M.browseKey(k)
    if type(k)~='table' or not M.integer(k.itemID) or k.itemID==0 then return nil end
    return table.concat({k.itemID,k.itemLevel or 0,k.itemSuffix or 0,k.battlePetSpeciesID or 0},':')
end
function M.quantile(values, p)
    if #values==0 then return nil end
    local a={}; for i,v in ipairs(values) do a[i]=v end; table.sort(a)
    local x=1+(#a-1)*p; local lo=floor(x)
    return a[lo]+(a[min(lo+1,#a)]-a[lo])*(x-lo)
end
function M.weightedMedian(values)
    local a,total={},0
    for _,v in ipairs(values) do if v.weight>0 then a[#a+1]=v; total=total+v.weight end end
    table.sort(a,function(x,y) return x.price<y.price end)
    local sum=0; for _,v in ipairs(a) do sum=sum+v.weight; if sum>=total/2 then return v.price end end
end
function M.vendor(row, cfg)
    if not row.key or not row.executable or not M.integer(row.count) or row.count<1 or
       not M.integer(row.buyout) or row.buyout<1 or not M.integer(row.vendor) or row.vendor<1 or
       row.restricted or not M.integer(row.extra or 0) then return nil,'Missing executable identity, quantity or vendor value' end
    local cost=row.buyout+(row.extra or 0); local value=row.vendor*row.count
    if not M.integer(value) or not M.integer(cost) then return nil,'Amount overflow' end
    local profit=value-cost; local roi=profit/cost
    if profit<=0 or profit<(cfg.minVendor or 100) or roi<(cfg.vendorROI or 0) then return nil,'Vendor margin below limits' end
    return {value=value,profit=profit,roi=roi,perItem=profit/row.count,cost=cost}
end
-- Upper-bound fee rounding: never overstate proceeds if the server floors its cut.
function M.net(gross, bp) return gross-math.ceil(gross*bp/10000) end
function M.breakEven(cost,bp)
    if not M.integer(cost) or not M.integer(bp) or bp>=10000 then return nil end
    local n=math.ceil(cost*10000/(10000-bp))
    while M.net(n,bp)<cost do n=n+1 end
    return n
end
function M.prices(history,now)
    local values, times, last, seen={}, {}, nil, {}
    for _,o in ipairs(history or {}) do
        if type(o)=='table' and M.integer(o.at) and o.at<=now and now-o.at<=7*86400 and
           type(o.price)=='number' and o.price>0 and o.price<1e12 and o.signature and not seen[o.signature] then
            values[#values+1]=o.price; times[#times+1]=o.at; seen[o.signature]=true
            if not last or o.at>last.at then last=o end
        end
    end
    if #values<3 then return nil,'Insufficient changed historical snapshots (need 3)' end
    table.sort(times)
    if times[#times]-times[1]<6*3600 then return nil,'History spans less than 6 hours' end
    if now-last.at>86400 then return nil,'Stale reference prices (>24 hours)' end
    local med=M.quantile(values,.5); local deviations={}
    for _,v in ipairs(values) do deviations[#deviations+1]=math.abs(v-med) end
    local mad=M.quantile(deviations,.5)
    local clean={}
    for _,v in ipairs(values) do
        -- Remove high outliers only: low prices remain downside evidence.
        if v<=med+max(3*mad,med*.5) then clean[#clean+1]=v end
    end
    if #clean<3 then return nil,'Reference depends on extreme listings' end
    local q1,q3=M.quantile(clean,.25),M.quantile(clean,.75)
    local volatility=(q3-q1)/max(1,med)
    if volatility>.5 then return nil,'Unstable prices (IQR >50%)' end
    local chronological={}
    for _,o in ipairs(history) do if o.at and o.at<=now and now-o.at<=86400 and o.price then chronological[#chronological+1]=o end end
    table.sort(chronological,function(a,b) return a.at<b.at end)
    local n=#chronological
    if n>=3 and chronological[n].price<chronological[n-1].price and chronological[n-1].price<chronological[n-2].price and chronological[n].price<chronological[n-2].price*.8 then
        return nil,'Falling knife: consecutive decline >20%'
    end
    local haircut=.10+min(.15,volatility*.25)+(#clean<6 and .10 or 0)
    return {base=floor(M.quantile(clean,.5)),optimistic=floor(q3),conservative=floor(min(q1,last.price)*(1-haircut)),
        volatility=volatility,sample=#clean,last=last.at,confidence=#clean>=6 and 'Medium' or 'Low',
        method='Lower quartile capped by latest ask, minus 10-35% haircut; asking prices, not sales'}
end
function M.risk(row, prices, cfg, gold, exposure, position, fee)
    if not row.executable or not row.key then return nil,'No executable listing' end
    if type(fee)~='table' or not M.integer(fee.cutBP) or fee.cutBP>=10000 or not M.integer(fee.deposit) then
        return nil,'Set explicit fee and per-stack deposit assumptions first'
    end
    if fee.quantity and fee.quantity~=row.count then return nil,'Deposit assumption is for a different stack quantity' end
    if not M.integer(row.vendor) or row.restricted then return nil,'Unknown liquidation value' end
    if not M.integer(row.buyout) or row.buyout<1 or not M.integer(row.count) or row.count<1 then return nil,'Invalid stack' end
    if not M.integer(row.extra or 0) then return nil,'Invalid acquisition costs' end
    local cost=row.buyout+(row.extra or 0); local attempts=cfg.failures or 2
    local lost=fee.deposit*attempts; local gross=floor(prices.conservative*row.count)
    if not M.integer(gross) then return nil,'Amount overflow' end
    local proceeds=M.net(gross,fee.cutBP); local profit=proceeds-cost-lost
    local liquidation=row.vendor*row.count-cost-lost; local downside=max(0,-liquidation)
    local budget=min(gold*(cfg.positionCap or .1)-(position or 0),gold*(cfg.totalCap or .25)-(exposure or 0),gold)
    if cost+fee.deposit>budget then return nil,'Large-stack / capital exposure limit' end
    if row.buyout/row.count>prices.base*(1-(cfg.discount or .3)) then return nil,'Discount below minimum' end
    if profit<(cfg.minMarket or 10000) or profit/cost<(cfg.marketROI or .3) then return nil,'Conservative profit / ROI below limits (deposit trap)' end
    if downside>gold*(cfg.lossCap or .02) or downside/cost>(cfg.lossFraction or .5) then return nil,'Vendor liquidation loss exceeds risk limit' end
    if (row.depth or 0)<3 then return nil,'Low-depth illusion: fewer than 3 listings' end
    local safe=min((proceeds-lost)/(1+(cfg.marketROI or .3)),proceeds-lost-(cfg.minMarket or 10000),budget-fee.deposit,
        row.vendor*row.count-lost+gold*(cfg.lossCap or .02),
        (row.vendor*row.count-lost)/(1-(cfg.lossFraction or .5)))
    safe=floor(max(0,min(safe-(row.extra or 0),prices.base*(1-(cfg.discount or .3))*row.count)))
    local scenarios={}
    for _,drop in ipairs({0,.1,.15,.2,.3}) do scenarios[#scenarios+1]={drop=drop,profit=M.net(floor(gross*(1-drop)),fee.cutBP)-cost-lost} end
    local confidence=min(1,prices.sample/12)*.5 -- supply-only evidence caps contribution
    local ev
    if cfg.probability~=nil then
        ev=M.ev(cfg.probability,profit,liquidation)
        if ev and ev<0 then return nil,'Negative EV under your probability scenario (not measured demand)' end
    end
    local score=floor(100*(.25*min(1,profit/cost)+.25*(1-min(1,downside/cost))+.20*confidence+
        .10*(1-min(1,prices.volatility))+.10*min(1,row.depth/10)+.10*(1-min(1,cost/max(1,gold)))))
    return {value=gross,profit=profit,roi=profit/cost,cost=cost,downside=downside,liquidation=liquidation,
        safe=safe,score=score,breakEven=M.breakEven(cost+lost,fee.cutBP),scenarios=scenarios,
        successProfit=proceeds-cost,oneFailure=M.net(floor(gross*.85),fee.cutBP)-cost-fee.deposit,
        lostDeposits=lost,deposit=fee.deposit,maxQuantity=row.count,ev=ev,probability=cfg.probability,
        prices=prices,fee=fee,reason='Candidate - verify listing; fees are user assumptions, demand unknown'}
end
function M.ev(probability,sold,unsold)
    if type(probability)~='number' or probability<0 or probability>1 then return nil end
    return probability*sold+(1-probability)*unsold -- scenario, never measured probability
end
