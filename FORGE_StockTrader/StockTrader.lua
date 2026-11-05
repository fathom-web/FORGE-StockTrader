local ADDON, ST = ...
local COOLDOWN, CHUNK, MAX_DEALS = 900, 250, 160
local scan, ahOpen, tab = nil, false, 1
local vendorDeals, marketDeals = {}, {}
local status = "Open an Auction House and press SCAN."
local ui, list, scroll, rows = nil, nil, nil, {}
local db

-- All amounts are copper. Buyouts are for complete stacks.
local function money(value)
    value = math.max(0, math.floor(value or 0))
    local g, s, c = math.floor(value / 10000), math.floor(value % 10000 / 100), value % 100
    if g > 0 then return string.format("%dg %02ds %02dc", g, s, c) end
    if s > 0 then return string.format("%ds %02dc", s, c) end
    return c .. "c"
end
local function median(data)
    if #data == 0 then return nil end
    local copy = {}
    for i = 1, #data do copy[i] = data[i] end
    table.sort(copy)
    local middle = math.floor((#copy + 1) / 2)
    if #copy % 2 == 1 then return copy[middle] end
    return math.floor((copy[middle] + copy[middle + 1]) / 2)
end
local function store()
    FORGEStockTraderDB = FORGEStockTraderDB or { realms = {} }
    FORGEStockTraderDB.realms = FORGEStockTraderDB.realms or {}
    local realm = (GetRealmName() or "Unknown") .. ":" .. (UnitFactionGroup("player") or "Unknown")
    local entry = FORGEStockTraderDB.realms[realm]
    if not entry then
        entry = { history = {}, minVendor = 0, minMarket = 10000 }
        FORGEStockTraderDB.realms[realm] = entry
    end
    entry.history = entry.history or {}
    entry.minVendor = entry.minVendor or 0
    entry.minMarket = entry.minMarket or 10000
    return entry
end
local function rank(deals)
    table.sort(deals, function(a, b)
        if a.profit == b.profit then return a.buyout < b.buyout end
        return a.profit > b.profit
    end)
    while #deals > MAX_DEALS do table.remove(deals) end
end
local function itemKey(link)
    -- Keeping the full item-string avoids merging gear with different modifiers.
    return type(link) == "string" and link:match("|H(item:[^|]+)|h") or nil
end
local function vendorValue(link, id)
    if not C_Item or not C_Item.GetItemInfo then return nil end
    local _, _, _, _, _, _, _, _, _, _, value = C_Item.GetItemInfo(link or id)
    if type(value) ~= "number" then
        _, _, _, _, _, _, _, _, _, _, value = C_Item.GetItemInfo(id)
    end
    return type(value) == "number" and value > 0 and value or nil
end
local function offer(group, row)
    local entries = group.cheapest
    local position = #entries + 1
    while position > 1 and entries[position - 1].unit > row.unit do
        position = position - 1
    end
    if position <= 5 then
        table.insert(entries, position, row)
        if #entries > 5 then table.remove(entries) end
    end
end
local function pushVendor(row, value, collection)
    if not value then return false end
    local profit = value * row.count - row.buyout
    if profit > 0 then
        row.profit, row.value = profit, value * row.count
        collection[#collection + 1] = row
        return true
    end
    return false
end
local function loadRow(index)
    local name, _, count, _, _, _, _, _, _, buyout,
        _, _, _, _, _, _, id = C_AuctionHouse.GetReplicateItemInfo(index)
    if type(id) ~= "number" or type(count) ~= "number" or count < 1
       or type(buyout) ~= "number" or buyout <= 0 then return end
    local link = C_AuctionHouse.GetReplicateItemLink(index)
    local row = { name = name and name ~= "" and name or ("Item #" .. id),
                  id = id, link = link, count = count, buyout = buyout,
                  unit = buyout / count }
    local value = vendorValue(link, id)
    if value then
        pushVendor(row, value, scan.vendor)
    else
        scan.pending[#scan.pending + 1] = row
        if not scan.requests[id] and C_Item and C_Item.RequestLoadItemDataByID then
            scan.requests[id] = true
            pcall(C_Item.RequestLoadItemDataByID, id)
        end
    end
    local key = itemKey(link)
    if not key then return end
    local group = scan.groups[key]
    if not group then
        group = { count = 0, cheapest = {} }
        scan.groups[key] = group
    end
    group.count = group.count + 1
    offer(group, row)
end

local function makeMarketDeals(history)
    local deals = {}
    for key, group in pairs(scan.groups) do
        local prior = history[key]
        local cheapest = group.cheapest[1]
        if prior and #prior >= 3 and cheapest and group.count >= 2 then
            local observations = {}
            for i = 1, #prior do
                if type(prior[i].price) == "number" and prior[i].price > 0 then
                    observations[#observations + 1] = prior[i].price
                end
            end
            if #observations >= 3 then
                local estimate = median(observations)
                -- Require 25% discount versus median of previous asking prices.
                if estimate and cheapest.unit <= estimate * .75 then
                    local value = math.floor(estimate * cheapest.count)
                    local profit = math.floor(value * .95) - cheapest.buyout
                    if profit > 0 then
                        deals[#deals + 1] = {
                            id = cheapest.id, name = cheapest.name, link = cheapest.link,
                            count = cheapest.count, buyout = cheapest.buyout,
                            value = value, profit = profit, sample = #observations
                        }
                    end
                end
            end
        end
    end
    rank(deals)
    return deals
end

local function saveHistory(history)
    local now, cutoff = time(), time() - 30 * 86400
    for key, observations in pairs(history) do
        local keep = {}
        for i = 1, #observations do
            if observations[i].at and observations[i].at >= cutoff then
                keep[#keep + 1] = observations[i]
            end
        end
        if #keep == 0 then history[key] = nil else history[key] = keep end
    end
    for key, group in pairs(scan.groups) do
        if group.count >= 3 and #group.cheapest >= 3 then
            local values = {}
            for i = 1, #group.cheapest do values[i] = group.cheapest[i].unit end
            local estimate = median(values)
            if estimate then
                local observations = history[key] or {}
                if #observations == 0 or now - observations[#observations].at >= COOLDOWN - 10 then
                    observations[#observations + 1] = { at = now, price = estimate }
                    while #observations > 12 do table.remove(observations, 1) end
                    history[key] = observations
                end
            end
        end
    end
    -- Bound SavedVariables so a long-running private addon does not grow forever.
    local index = {}
    for key, observations in pairs(history) do
        index[#index + 1] = { key = key, at = observations[#observations].at }
    end
    if #index > 3000 then
        table.sort(index, function(a, b) return a.at > b.at end)
        for i = 3001, #index do history[index[i].key] = nil end
    end
end

local function refresh()
    if not ui then return end
    local data = store()
    ui.tabs[1]:SetText(tab == 1 and "> VENDOR SELL" or "VENDOR SELL")
    ui.tabs[2]:SetText(tab == 2 and "> AH KOOPJES" or "AH KOOPJES")
    ui.scanButton:SetEnabled(not scan)
    ui.scanButton:SetText(scan and "SCANNING..." or "SCAN AUCTION HOUSE")
    local last = data.lastScan and date("%d-%m %H:%M", data.lastScan) or "Never"
    ui.status:SetText(status)
    ui.last:SetText("Last completed scan: " .. last)
    local all = tab == 1 and vendorDeals or marketDeals
    local threshold = tab == 1 and data.minVendor or data.minMarket
    if not ui.input:HasFocus() then ui.input:SetText(tostring(math.floor(threshold / 100))) end
    local filtered = {}
    for _, result in ipairs(all) do
        if result.profit >= threshold then
            filtered[#filtered + 1] = result
            if #filtered >= 70 then break end
        end
    end
    ui.count:SetText(string.format("%d visible / %d found  |  %s",
        #filtered, #all, tab == 1 and "Positive vendor margin" or "Speculative resale"))
    for i = 1, math.max(#rows, #filtered) do
        local r = rows[i]
        if not r then
            r = CreateFrame("Button", nil, scroll)
            r:SetSize(716, 28)
            r:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -(i - 1) * 29)
            r.bg = r:CreateTexture(nil, "BACKGROUND")
            r.bg:SetAllPoints()
            r.bg:SetColorTexture(.16, .17, .19, i % 2 == 0 and .6 or .3)
            r.labels = {}
            local widths = {230, 52, 110, 110, 108, 95}
            local positions = {6, 239, 292, 402, 513, 623}
            for col = 1, 6 do
                local t = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                t:SetPoint("LEFT", r, "LEFT", positions[col], 0)
                t:SetSize(widths[col], 22)
                t:SetJustifyH(col == 1 and "LEFT" or "RIGHT")
                t:SetMaxLines(1)
                r.labels[col] = t
            end
            r:SetScript("OnClick", function(self)
                local d = self.deal
                if not d or not ahOpen then
                    status = "Open the Auction House to recheck this deal."; refresh(); return
                end
                -- The replicated snapshot cannot be purchased directly.
                -- Always manually VERIFY current stack, variant, and buyout.
                local key = C_AuctionHouse.MakeItemKey and C_AuctionHouse.MakeItemKey(d.id)
                    or {itemID = d.id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0}
                local ok = pcall(C_AuctionHouse.SendSearchQuery, key, {}, false)
                status = ok and "Search sent. VERIFY item variant, stack and live buyout before buying."
                    or "Could not open search; look up the item in the AH manually."
                refresh()
            end)
            r:SetScript("OnEnter", function(self)
                if self.deal and self.deal.link then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink(self.deal.link)
                    GameTooltip:Show()
                end
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            rows[i] = r
        end
        local d = filtered[i]
        if d then
            r.deal = d
            r.labels[1]:SetText(d.name)
            r.labels[2]:SetText(d.count)
            r.labels[3]:SetText(money(d.buyout))
            r.labels[4]:SetText(money(d.value))
            r.labels[5]:SetText("|cff66ee88+" .. money(d.profit) .. "|r")
            r.labels[6]:SetText(tab == 1 and "VENDOR" or (d.sample .. " scans"))
            r:Show()
        else
            r.deal = nil
            r:Hide()
        end
    end
    scroll:SetHeight(math.max(256, #filtered * 29))
end

local function startScan()
    if scan then return end
    if not ahOpen then status = "Open an Auction House first."; refresh(); return end
    if not C_AuctionHouse or not C_AuctionHouse.ReplicateItems then
        status = "Full AH scan API is unavailable on this client."; refresh(); return
    end
    local data = store()
    local remaining = COOLDOWN - (time() - (data.lastScan or 0))
    if remaining > 0 then
        status = string.format("Full scan cooldown: %dm %02ds.",
            math.floor(remaining / 60), remaining % 60)
        refresh()
        return
    end
    scan = { phase = "waiting", started = GetTime(), nextIndex = 0,
             groups = {}, vendor = {}, pending = {}, requests = {}, total = 0 }
    status = "Requesting complete AH snapshot..."
    refresh()
    local ok, err = pcall(C_AuctionHouse.ReplicateItems)
    if not ok then
        scan = nil
        status = "Scan failed: " .. tostring(err)
        refresh()
    end
end

local function finishScan()
    local missing = 0
    for i = 1, #scan.pending do
        local row = scan.pending[i]
        local vendor = vendorValue(row.link, row.id)
        if not vendor then missing = missing + 1
        else pushVendor(row, vendor, scan.vendor) end
    end
    local data = store()
    marketDeals = makeMarketDeals(data.history)  -- Only prior scans count.
    vendorDeals = scan.vendor
    rank(vendorDeals)
    saveHistory(data.history)
    data.lastScan = time()
    local count = scan.total
    scan = nil
    status = string.format("Scanned %d auctions. Vendor: %d | AH bargains: %d | No vendor data: %d",
        count, #vendorDeals, #marketDeals, missing)
    refresh()
end

local function build()
    ui = CreateFrame("Frame", "FORGEStockTraderFrame", UIParent, "BackdropTemplate")
    ui:SetSize(800, 550)
    ui:SetPoint("CENTER")
    ui:SetFrameStrata("HIGH")
    ui:SetClampedToScreen(true)
    ui:SetMovable(true)
    ui:EnableMouse(true)
    ui:RegisterForDrag("LeftButton")
    ui:SetScript("OnDragStart", ui.StartMoving)
    ui:SetScript("OnDragStop", ui.StopMovingOrSizing)
    ui:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16, insets = {left = 3, right = 3, top = 3, bottom = 3}})
    ui:SetBackdropColor(.05, .065, .08, .98)
    ui:SetBackdropBorderColor(.55, .43, .23, 1)
    local function text(x, y, width, label, template)
        local t = ui:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
        t:SetPoint("TOPLEFT", ui, "TOPLEFT", x, y)
        t:SetSize(width, 25)
        t:SetJustifyH("LEFT")
        t:SetText(label)
        return t
    end
    local title = text(20, -12, 420, "FORGE StockTrader", "GameFontNormalLarge")
    title:SetTextColor(1, .78, .33)
    text(22, -40, 640, "NOVYX FORGE  /  PRIVATE EDITION  /  WOW FOREVER")
    local close = CreateFrame("Button", nil, ui, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    local function button(label, x, w, onclick)
        local b = CreateFrame("Button", nil, ui, "UIPanelButtonTemplate")
        b:SetPoint("TOPLEFT", x, -75)
        b:SetSize(w, 27)
        b:SetText(label)
        b:SetScript("OnClick", onclick)
        return b
    end
    ui.tabs = {
        button("VENDOR SELL", 20, 165, function() tab = 1; refresh() end),
        button("AH KOOPJES", 190, 165, function() tab = 2; refresh() end)
    }
    ui.scanButton = button("SCAN AUCTION HOUSE", 570, 207, startScan)
    ui.status = text(22, -111, 755, "")
    ui.status:SetHeight(35)
    ui.last = text(22, -144, 460, "")
    ui.count = text(22, -173, 450, "")
    text(524, -174, 158, "Min. profit (silver):")
    ui.input = CreateFrame("EditBox", nil, ui, "InputBoxTemplate")
    ui.input:SetSize(88, 23)
    ui.input:SetPoint("TOPLEFT", 682, -166)
    ui.input:SetNumeric(true)
    ui.input:SetMaxLetters(8)
    ui.input:SetAutoFocus(false)
    ui.input:SetScript("OnEnterPressed", function(self)
        local data = store()
        local threshold = math.max(0, tonumber(self:GetText()) or 0) * 100
        if tab == 1 then data.minVendor = threshold else data.minMarket = threshold end
        self:ClearFocus()
        refresh()
    end)
    ui.input:SetScript("OnEscapePressed", function(self) self:ClearFocus(); refresh() end)
    text(28, -209, 740,
        "ITEM                                               QTY        BUYOUT              VALUE             PROFIT             BASIS")
    list = CreateFrame("ScrollFrame", nil, ui, "UIPanelScrollFrameTemplate")
    list:SetPoint("TOPLEFT", 21, -238)
    list:SetSize(734, 260)
    scroll = CreateFrame("Frame", nil, list)
    scroll:SetSize(718, 260)
    list:SetScrollChild(scroll)
    text(22, -512, 754,
        "Click a deal to search. Verify the live listing. AH resale is speculation, never guaranteed.")
    ui:Hide()
    refresh()
end

function ST.Toggle()
    if not ui then build() end
    if ui:IsShown() then ui:Hide() else ui:Show(); refresh() end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("AUCTION_HOUSE_SHOW")
f:RegisterEvent("AUCTION_HOUSE_CLOSED")
f:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
f:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" and arg == ADDON then
        db = store()
        SLASH_FORGESTOCKTRADER1 = "/fst"
        SLASH_FORGESTOCKTRADER2 = "/stocktrader"
        SlashCmdList.FORGESTOCKTRADER = ST.Toggle
        print("|cffffcc55FORGE StockTrader|r v0.1.0 loaded. Type /fst")
    elseif event == "AUCTION_HOUSE_SHOW" then
        ahOpen = true
        refresh()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        ahOpen = false
        if scan then
            scan = nil
            status = "Scan cancelled because you closed the Auction House."
        end
        refresh()
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" and scan and scan.phase == "waiting" then
        local n = C_AuctionHouse.GetNumReplicateItems()
        if type(n) == "number" and n > 0 then
            scan.total = n
            scan.phase = "reading"
            status = "Reading " .. n .. " auction listings..."
            refresh()
        end
    end
end)
f:SetScript("OnUpdate", function()
    if not scan then return end
    if scan.phase == "waiting" then
        if GetTime() - scan.started > 45 then
            scan = nil
            status = "No scan response. The server may be on its 15-minute throttle."
            refresh()
        end
    elseif scan.phase == "reading" then
        local last = math.min(scan.nextIndex + CHUNK, scan.total)
        for index = scan.nextIndex, last - 1 do
            loadRow(index)
        end
        scan.nextIndex = last
        if last >= scan.total then
            scan.phase = "caching"
            scan.untilTime = GetTime() + 6
            status = "Finishing item-price lookups..."
            refresh()
        elseif last % 2500 < CHUNK then
            status = string.format("Reading auctions: %d / %d", last, scan.total)
            refresh()
        end
    elseif scan.phase == "caching" and GetTime() >= scan.untilTime then
        finishScan()
    end
end)
