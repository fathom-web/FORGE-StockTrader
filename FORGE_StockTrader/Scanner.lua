local _,ST=...; local M=ST.Model; local S={}; ST.Scanner=S; S.__index=S
local unpack=unpack or table.unpack
function S.new(api,clock,resolve,notify)
    return setmetatable({api=api,clock=clock,resolve=resolve,notify=notify,state='IDLE',active=false,lastExternal=-100,lastRequest=-100,requestGap=0.8},S)
end
function S:set(state,message)
    if self.state==state and self.message==(message or state) then return end
    self.state,self.message=state,message or state
    self.log=self.log or {}; self.log[#self.log+1]={at=self.clock(),state=state,message=self.message}; if #self.log>60 then table.remove(self.log,1) end
    if self.notify then self.notify(self) end
end
function S:stop(state,message)
    self.active=false; self.paused=false; self.pauseRequested=false; self.waiting=nil; self.request=nil; self.work=nil
    self:set(state,message)
end
function S:call(name,...)
    if type(self.api[name])~='function' then error('Missing API: '..name) end
    return self.api[name](...)
end
function S:external()
    self.lastExternal=self.clock()
    if self.active and not self.ownRequest then self:stop('CANCELLED','Another AH search took over. Scan cancelled; restart when idle.') end
end
function S:queue(name,args,kind)
    self.request={name=name,args=args or {},kind=kind}; self.queued=self.clock(); self.waiting=nil
    self:set('REQUESTING',name)
end
function S:start(mode)
    if self.active then return false end
    self.mode=mode or 'browse'; self.active=true; self.started=self.clock(); self.processed=0; self.excluded=0; self.incomplete=0
    self.rows={}; self.groups={}; self.keys={}; self.keyIndex=0; self.seen={}; self.work=nil; self.waiting=nil; self.request=nil
    self.keyStarted=nil; self.marketKeys=nil; self.detailStarted=nil; self.lastProgress=self.clock(); self.browseComplete=false; self.checkedKeys=0; self.pauseRequested=false; self.paused=false; self.keySeen={}
    if self.mode=='replicate' then self:queue('ReplicateItems',{},'replicate')
    else self:queue('SendBrowseQuery',{{searchString='',sorts={},filters={},itemClassFilters={}}},'browse') end
    return true
end
function S:nextKey()
    if self.pauseRequested then self.pauseRequested=false; self.paused=true; self.active=false; self.pausedAt=self.clock(); self:set('PAUSED','Paused after a complete item search; results are partial'); return end
    self.keyStarted=nil; self.keyIndex=self.keyIndex+1
    if self.keyIndex>#self.keys then
        self.work={kind='validate'}; self:set('VALIDATING','Validating complete listing data'); return
    end
    self.current=self.keys[self.keyIndex].itemKey; self.keyGroups={}; self.keyStarted=self.clock()
    self:queue('SendSearchQuery',{self.current,{},false},'detail')
end
function S:accept(row)
    self.processed=self.processed+1
    if self.processed>200000 then error('Safety limit: snapshot exceeds 200000 listings') end
    if row==false then self.excluded=self.excluded+1; return true end
    if not row then return false end
    if not M.integer(row.count) or row.count<1 or not M.integer(row.buyout) or row.buyout<1 or not row.key then return false end
    if row.auctionID then
        local id=tostring(row.auctionID)
        if self.seen[id] then self.processed=self.processed-1; return true end
        self.seen[id]=true
    end
    row.at=self.clock(); self.rows[#self.rows+1]=row
    local group=self.groups[row.key] or {}; group[#group+1]=row
    if #group>5000 then error('Safety limit: more than 5000 listings for one variant') end
    self.groups[row.key]=group; self.keyGroups=self.keyGroups or {}; self.keyGroups[row.key]=group; return true
end
function S:event(event,arg)
    if not self.active or not self.waiting then return end
    local ok,err=pcall(function()
        local kind=self.waiting
        if kind=='browse' and (event=='AUCTION_HOUSE_BROWSE_RESULTS_UPDATED' or event=='AUCTION_HOUSE_BROWSE_RESULTS_ADDED') then
            if not self:call('HasFullBrowseResults') then self:queue('RequestMoreBrowseResults',{},'browse'); return end
            local results=self:call('GetBrowseResults')
            if type(results)~='table' then error('Invalid browse response') end
            self.waiting=nil; self.work={kind='browse',data=results,index=1}; self:set('PROCESSING','Indexing browse keys (aggregate prices are not deals)')
        elseif kind=='replicate' and event=='REPLICATE_ITEM_LIST_UPDATE' then
            local n=self:call('GetNumReplicateItems')
            if not M.integer(n) or n>200000 then error('Invalid replicate count') end
            self.waiting=nil; self.work={kind='replicate',index=0,total=n}; self:set('PROCESSING','Reading experimental replicated snapshot')
        elseif kind=='detail' and M.browseKey(arg)==M.browseKey(self.current) and (event=='ITEM_SEARCH_RESULTS_UPDATED' or event=='ITEM_SEARCH_RESULTS_ADDED') then
            if not self:call('HasFullItemSearchResults',self.current) then self:queue('RequestMoreItemSearchResults',{self.current},'detail'); return end
            local n=self:call('GetNumItemSearchResults',self.current)
            if not M.integer(n) or n>200000 then error('Invalid item result count') end
            self.waiting=nil; self.work={kind='detail',index=1,total=n}; self:set('PROCESSING','Reading individual auctions')
        elseif kind=='detail' and event=='COMMODITY_SEARCH_RESULTS_UPDATED' and arg==self.current.itemID then
            if not self:call('HasFullCommoditySearchResults',arg) then self:queue('RequestMoreCommoditySearchResults',{arg},'detail'); return end
            local n=self:call('GetNumCommoditySearchResults',arg)
            if not M.integer(n) or n>200000 then error('Invalid commodity result count') end
            self.waiting=nil; self.work={kind='commodity',index=1,total=n}; self:set('PROCESSING','Reading commodity supply (manual quote required)')
        end
    end)
    if not ok then self:stop('ERROR',tostring(err)) end
end
function S:tick()
    if not self.active then return end
    local ok,err=pcall(function()
        local now=self.clock()
        if self.keyStarted and now-self.keyStarted>120 then self:stop('TIMEOUT','Item search exceeded two minutes; remaining scope not checked'); return end
        if now-self.started>7200 then self:stop('TIMEOUT','Scan exceeded two hours; unfinished scope not committed'); return end
        if self.request then
            if now-self.queued>45 then self:stop('TIMEOUT','AH request could not be sent within 45 seconds'); return end
            -- Give external searches their original grace period. Inside our own
            -- scan, pace the next request against actual client readiness.
            if now-self.lastExternal<2 or now-self.lastRequest<self.requestGap then return end
            if not self:call('IsThrottledMessageSystemReady') then
                self.requestGap=2
                self:set('THROTTLED','Waiting for shared AH throttle')
                return
            end
            self.requestGap=math.max(0.8,self.requestGap-0.1)
            local q=self.request; self.request=nil; self.waiting=q.kind; self.sent=now; self.lastRequest=now
            self:set('RECEIVING','Waiting: '..q.name)
            self.ownRequest=true
            local sent,reason=pcall(function() self:call(q.name,unpack(q.args)) end)
            self.ownRequest=false
            if not sent then error(reason) end
            return
        end
        if self.waiting then
            if now-self.sent>45 then self:stop('TIMEOUT','No complete server response within 45 seconds; unfinished scope not committed') end
            return
        end
        local w=self.work; if not w then return end
        if w.kind=='browse' then
            for i=1,100 do
                local r=w.data[w.index]; if not r then
                    self.work=nil; self.browseComplete=true; self.marketKeys=#self.keys; self.detailStarted=now
                    if self.onBrowse then self.keys=self.onBrowse(self,self.keys) or self.keys end
                    self:nextKey(); return
                end
                if not M.browseKey(r.itemKey) then error('Invalid browse identity') end
                if (r.itemKey.battlePetSpeciesID or 0)>0 then self.excluded=self.excluded+1
                elseif not self.keySeen[M.browseKey(r.itemKey)] then
                    self.keySeen[M.browseKey(r.itemKey)]=true
                    if self.rankKey then self.rankKey(r) end
                    self.keys[#self.keys+1]=r end
                if #self.keys>10000 then error('Safety limit: >10000 item keys') end
                w.index=w.index+1
            end
        elseif w.kind=='validate' then
            self.work=nil
            if self.incomplete>0 then self:stop('ERROR','Incomplete item data; scan discarded'); return end
            self.active=false
            if self.onComplete then self.onComplete(self) else self:set('COMPLETE','SCAN COMPLETE - '..self.processed..' listings checked') end
        else
            local limit=w.kind=='replicate' and w.total-1 or w.total
            for i=1,100 do
                if w.index>limit then
                    self.work=nil
                    if w.kind=='replicate' then self.work={kind='validate'}; self:set('VALIDATING','Validating replicated snapshot') else
                        self.checkedKeys=self.checkedKeys+1
                        if self.onKey then self.onKey(self,self.keyGroups) end
                        self:nextKey()
                    end
                    return
                end
                local row,reason=self.resolve(w.kind,w.index,self.current,self.api)
                if row==nil then
                    w.pendingSince=w.pendingSince or now
                    if now-w.pendingSince<8 then return end
                    self.incomplete=self.incomplete+1
                    error('Incomplete listing/item cache: '..tostring(reason or w.index))
                end
                if not self:accept(row) then self.incomplete=self.incomplete+1; error('Invalid listing') end
                w.pendingSince=nil; w.index=w.index+1
            end
        end
    end)
    if not ok then self:stop('ERROR',tostring(err)) end
end

function S:pause()
    if not self.active then return end
    self.pauseRequested=true; self:set(self.state,'Pausing after current complete item search...')
end
function S:resume()
    if not self.paused then return false end
    local pauseTime=self.clock()-self.pausedAt
    if self.detailStarted then self.detailStarted=self.detailStarted+pauseTime end
    self.started=self.started+pauseTime; self.paused=false; self.active=true
    self:nextKey(); return true
end
