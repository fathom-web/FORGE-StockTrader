local _,ST=...; local M=ST.Model; local C={}; ST.Costs=C
-- Cache only inside one AH session, and never pretend an itemID is an exact variant.
function C.reset() C.cache={} end
C.reset()
function C.deposit(row,duration,api,itemAPI,bagAPI)
    api=api or C_AuctionHouse; itemAPI=itemAPI or C_Item; bagAPI=bagAPI or C_Container
    if not row or not row.key or not M.integer(row.count) or row.count<1 then return nil,'Invalid quantity' end
    local key=row.key..':'..row.count..':'..duration
    if C.cache[key] then return C.cache[key].value,C.cache[key].source end
    local value,source
    if row.source=='commodity-depth' or row.source=='commodity-quote' then
        if api and api.CalculateCommodityDeposit then
            local ok,n=pcall(api.CalculateCommodityDeposit,row.id,duration,row.count)
            if ok and M.integer(n) then value=n; source='Live commodity deposit API' end
        end
    elseif api and api.CalculateItemDeposit and bagAPI and bagAPI.GetContainerNumSlots and bagAPI.GetContainerItemLink and ItemLocation then
        for bag=0,(NUM_BAG_SLOTS or 4) do
            for slot=1,bagAPI.GetContainerNumSlots(bag) do
                if M.key(bagAPI.GetContainerItemLink(bag,slot))==row.key then
                    local location=ItemLocation:CreateFromBagAndSlot(bag,slot)
                    local ok,n=pcall(api.CalculateItemDeposit,location,duration,row.count)
                    if ok and M.integer(n) then value=n; source='Live exact-variant bag deposit API'; break end
                end
            end
            if value then break end
        end
    end
    if value~=nil then C.cache[key]={value=value,source=source}; return value,source end
    return nil,'Deposit unavailable until exact item is owned; enter a stack assumption'
end
function C.resolve(db,row)
    local setting=db.settings; local old=db.fees[row.key]
    local cut=setting.cutBP
    if not M.integer(cut) and type(old)=='table' then cut=old.cutBP end
    local duration=setting.duration or 1
    local amount,source=C.deposit(row,duration)
    if amount==nil and type(old)=='table' and old.quantity==row.count and (old.duration or 1)==duration then
        amount=old.deposit; source='Manual stack deposit assumption'
    end
    if not M.integer(cut) or cut>=10000 then return nil,'Set market commission once in Settings (not auto-confirmed)' end
    if not M.integer(amount) then return nil,source end
    return {cutBP=cut,deposit=amount,quantity=row.count,duration=duration,source=source..'; commission entered by you'}
end
