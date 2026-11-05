-- Observe ONLY quotes requested by the player through the native AH.
-- Never call Start/ConfirmCommoditiesPurchase or PlaceBid from this addon.
local _,ST=...; local M=ST.Model; local Q={}; ST.Quotes=Q
local function copy(r)local x={};for k,v in pairs(r)do x[k]=v end;return x end
function Q.invalidate(reason)
    if Q.pending and Q.pending.row then
        Q.pending.row.executable=false; Q.pending.row.verification=reason or 'QUOTE EXPIRED'
    end
    Q.pending=nil
    if Q.label then Q.label:SetText('') end
    if ST.Changed then ST.Changed() end
end
function Q.start(id,quantity)
    if ST.scan then ST.scan:external() end
    if ST.verify then ST.verify:external() end
    Q.invalidate('New native quote requested')
    local source=ST.nativeTarget
    if not source or source.id~=id or not M.integer(quantity) or quantity<1 then return end
    Q.pending={source=source,id=id,quantity=quantity,started=GetTime()}
end
function Q.event(event,unit,total)
    local p=Q.pending; if not p then return end
    if event~='COMMODITY_PRICE_UPDATED' then Q.invalidate(event); return end
    if GetTime()-p.started>10 or not M.integer(unit) or not M.integer(total) or total<1 then Q.invalidate('Invalid or late quote'); return end
    if p.row then p.row.executable=false; p.row.verification='Superseded quote' end
    local r=copy(p.source); r.count=p.quantity; r.buyout=total; r.source='commodity-quote';r.executable=true
    r.observed=time();r.quoteUntil=GetTime()+5;r.verification='NATIVE QUOTE - confirm only in native AH';r.auctionID=nil
    p.row=r;p.expires=r.quoteUntil
    local vendor,why=M.vendor(r,ST.db.settings)
    local risk,reason=ST.Evaluate(r,ST.db.history[r.key])
    local message
    if vendor then
        for k,v in pairs(vendor)do r[k]=v end
        -- At most one current quote for this commodity; depth rows never enter Vendor Sell.
        for i=#ST.vendor,1,-1 do if ST.vendor[i].source=='commodity-quote' and ST.vendor[i].key==r.key then table.remove(ST.vendor,i)end end
        ST.vendor[#ST.vendor+1]=r
        message='StockTrader: vendor margin '..ST.money(r.profit)..' for '..r.count..' items. Current native quote only.'
    elseif risk then
        for k,v in pairs(risk)do r[k]=v end
        for i=#ST.market,1,-1 do if ST.market[i].source=='commodity-quote' and ST.market[i].key==r.key then table.remove(ST.market,i) end end
        ST.market[#ST.market+1]=r;message='StockTrader: speculative '..ST.money(r.profit)..'; downside '..ST.money(-r.downside)
    else message='StockTrader: NO TRADE RECOMMENDED. '..(ST.tab==1 and why or reason or 'Unverified economics') end
    r.reason=message; ST.message=message
    if AuctionHouseFrame and AuctionHouseFrame.BuyDialog and AuctionHouseFrame.BuyDialog.CreateFontString then
        if not Q.label then
            Q.label=AuctionHouseFrame.BuyDialog:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
            Q.label:SetPoint('TOP',AuctionHouseFrame.BuyDialog,'BOTTOM',0,-8); Q.label:SetSize(320,48)
        end
        Q.label:SetText(message);Q.label:SetTextColor(1,.8,.35)
    end
    ST.Changed()
end
function Q.tick()
    if Q.pending and GetTime()>(Q.pending.expires or Q.pending.started+10) then Q.invalidate('QUOTE EXPIRED - request a fresh native quote') end
end
function Q.install()
    if Q.hooked or not C_AuctionHouse or not hooksecurefunc then return end
    Q.hooked=true
    if C_AuctionHouse.StartCommoditiesPurchase then hooksecurefunc(C_AuctionHouse,'StartCommoditiesPurchase',Q.start) end
    if C_AuctionHouse.CancelCommoditiesPurchase then hooksecurefunc(C_AuctionHouse,'CancelCommoditiesPurchase',function()Q.invalidate('Native quote cancelled')end)end
end
function ST.OpenNative(row)
    if not row or not ST.open or ST.scan.active or (ST.verify and ST.verify.active) then ST.message='Pause the scan first, then open the native AH.';ST.Changed();return end
    if not row.itemKey or not AuctionHouseFrame or not AuctionHouseFrame.SelectBrowseResult then ST.message='Native navigation unavailable; search this item manually.';ST.Changed();return end
    Q.invalidate(); ST.nativeTarget=row
    local ok,err=pcall(AuctionHouseFrame.SelectBrowseResult,AuctionHouseFrame,{itemKey=row.itemKey,minPrice=math.floor(row.buyout/row.count),totalQuantity=row.count})
    ST.message=ok and 'Check quantity and price in native AH. Commodity advice follows its live quote; you confirm purchases.' or tostring(err)
    ST.Changed()
end
