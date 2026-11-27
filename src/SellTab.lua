local GetRealmName=ForeverMarketVenueRealm or function() return _G.GetRealmName and _G.GetRealmName() or '' end
local api=C_AuctionHouse
if not api then return end
local panel,caption,scroll,content
local makeRow
local rows,slots,quotes={}, {}, {}
local readyRanks,quantities = {},{}
local forceLookup={}
local function options(s)
  return ForeverMarketTools and ForeverMarketTools.postOptions and ForeverMarketTools.postOptions(s.k.itemID) or {}
end
local function duration(s) return options(s).duration or 1 end
local function quantity(s)
  if not s.commodity then return 1 end
  local raw=quantities[s.stackKey]
  if raw==nil then return math.min(options(s).size or s.count,s.count) end
  local n=raw:match("^%d+$") and tonumber(raw)
  if n and n>=1 and n<=s.count and n==math.floor(n) then return n end
end
local rowHeight=26
local nativeFallback=false
local query,pending,lastQuery,pendingStack
local failures,warming={},{}
local paused=false
local delay,paintDelay=0,0
local lastDiagnostic,diagnosticAt
local function report(message)
  caption:SetText(message)
  if ForeverMarketSellDiagnostic and (not diagnosticAt or GetTime()-diagnosticAt>10) and message~=lastDiagnostic then
    lastDiagnostic=message;diagnosticAt=GetTime();ForeverMarketSellDiagnostic(message)
  end
end
local function keyOf(k)
  return table.concat({k.itemID,k.itemLevel or 0,k.itemSuffix or 0,k.battlePetSpeciesID or 0},':')
end
local function label(parent,x,y,width)
  local t=parent:CreateFontString(nil,'OVERLAY','GameFontHighlight')
  t:SetPoint('TOPLEFT',x,y);t:SetWidth(width);t:SetJustifyH('LEFT');return t
end
local function button(parent,text,x,y,w,fn)
  local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate')
  b:SetSize(w,24);b:SetPoint('TOPLEFT',x,y);b:SetText(text);b:SetScript('OnClick',fn);return b
end
local function inspect(bag,slot)
  local info=C_Container.GetContainerItemInfo(bag,slot)
  if not info then return end
  local loc=ItemLocation:CreateFromBagAndSlot(bag,slot)
  if not api.IsSellItemValid(loc, false) then return end
  local k=api.GetItemKeyFromItem(loc)
  local status=api.GetItemCommodityStatus(loc)
  local variant=status==Enum.ItemCommodityStatus.Item and ForeverMarketVariant(k,info.hyperlink)
  local tracked=variant and ForeverMarketFundHolding and ForeverMarketFundHolding(variant)>0 and variant
  return {bag=bag,slot=slot,loc=loc,k=k,key=variant or (k and keyOf(k)),tracked=tracked,link=info.hyperlink or ('Item '..info.itemID),
    count=info.stackCount or 1,valid=k and (status==Enum.ItemCommodityStatus.Commodity or status==Enum.ItemCommodityStatus.Item),
    locked=info.isLocked,commodity=status==Enum.ItemCommodityStatus.Commodity}
end
local managing=false
local function blacklist()
  ForeverMarketDB=ForeverMarketDB or {}
  local lists=ForeverMarketDB.__sellBlacklist or {}
  ForeverMarketDB.__sellBlacklist=lists
  local character=UnitGUID and UnitGUID('player') or 'default'
  if not lists[character] then
    lists[character]={[2901]='Mining Pick',[5956]='Blacksmith Hammer'}
  end
  return lists[character]
end
local function bags()
  slots={}
  local protected=blacklist()
  local seen={}
  for bag=0,(NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
    for slot=1,C_Container.GetContainerNumSlots(bag) do
      local s=inspect(bag,slot)
      if s and s.valid and (managing and not seen[s.k.itemID] or not managing and not protected[s.k.itemID]) then
        seen[s.k.itemID]=true
        s.stackKey = table.concat({bag, slot, s.key, s.link}, '/')
        slots[#slots+1]=s
      end
    end
  end
  if managing then
    for id,link in pairs(protected) do
      if not seen[id] then slots[#slots+1]={k={itemID=id},link=link,stackKey='saved/'..id} end
    end
    table.sort(slots,function(a,b)
      return a.k.itemID<b.k.itemID
    end)
  elseif ForeverMarketFundHolding then
    table.sort(slots,function(a,b)
      local x=a.k and ForeverMarketFundHolding(a.k.itemID) or 0
      local y=b.k and ForeverMarketFundHolding(b.k.itemID) or 0
      if (x>0)~=(y>0) then return x>0 end
      return a.bag<b.bag or (a.bag==b.bag and a.slot<b.slot)
    end)
  end
  local offset=scroll:GetVerticalScroll()
  local depth=ForeverMarketDB and ForeverMarketDB.__depth
  local book=depth and depth[GetRealmName()..'|'..UnitFactionGroup('player')]
  for _,s in ipairs(slots) do
    local d=s.commodity and book and book[s.k.itemID]
    if d then
      local age=time()-d.at
      local at=GetTime()-age
      if age>=0 and age<60 and not forceLookup[s.key] and not quotes[s.key] then
        quotes[s.key]={floorPrice=d.floorPrice,floorQty=d.floorQty,at=at,observed=d.at}
      end
    end
  end
  for i=#rows+1,#slots do rows[i]=makeRow(i) end
  content:SetHeight(math.max(1,#slots*rowHeight))
  scroll:SetVerticalScroll(math.max(0,math.min(offset,#slots*rowHeight-scroll:GetHeight())))
end
local function historicalQuote(s, timedOut)
  local q = {at=GetTime(), timedOut=timedOut}
  local db=ForeverMarketHistory()
  local r=db[ForeverMarketHistoryKey(s.k)]
  if ForeverMarketTools then q.average=ForeverMarketTools.history(ForeverMarketHistoryKey(s.k));return q end
  if r then
    local sum,n,today=0,0,math.floor(time()/86400)
    for day,low in pairs(r.l) do
      if day<=today and day>today-15 then sum=sum+low;n=n+1 end
    end
    if n>0 then q.average=math.floor(sum/n+.5) end
  end
  return q
end
local function price(q,s)
  if q.floorPrice then
    if s and ForeverMarketTools and ForeverMarketTools.rule and ForeverMarketTools.rule(s.k.itemID)=='Margin' then return q.floorPrice end
    return ForeverMarketPostPrice(q.floorPrice)
  end
  if not q.timedOut then return q.average end
end
local function quoteDetail(q)
  if q.floorPrice then return ForeverMarketCoins(q.floorPrice)..' x '..q.floorQty end
  if q.timedOut then return q.average and 'Timeout / history avg' or 'No live response' end
  return q.average and 'No buyouts / history avg' or 'No buyouts or history'
end
local function fresh(q) return q~=nil end
local allowHeld=false
local function postingLimit(s,unitPrice,recheck)
  local qty=quantity(s)
  if not qty then return 'Enter 1 to '..s.count end
  if ForeverMarketTools then
    if ForeverMarketTools.rule and ForeverMarketTools.rule(s.k.itemID)=='Keep' then return 'Keep for profession' end
    local need=ForeverMarketTools.materials()[s.k.itemID] or 0
    if need>0 and ForeverMarketTools.bagCount(s.k.itemID)-qty<need then
      local target=ForeverMarketTools.restockList and ForeverMarketTools.restockList()[s.k.itemID]
      return target and 'Reserved for restocking' or 'Reserved for crafting'
    end
  end
  if recheck or s.depositDuration~=duration(s) or s.depositQty~=qty or not s.deposit or not s.vendor then
    s.depositQty=qty;s.depositDuration=duration(s)
    local get=C_Item and C_Item.GetItemInfo or GetItemInfo
    s.vendor=get and select(11,get(s.link))
    if s.commodity then s.deposit=api.CalculateCommodityDeposit(s.k.itemID,duration(s),qty)
    else s.deposit=api.CalculateItemDeposit(s.loc,duration(s),qty) end
  end
  if type(s.vendor)~='number' or type(s.deposit)~='number' then return 'Awaiting values' end
  if GetMoney()<s.deposit then return 'Need deposit' end
  local gross=qty*unitPrice
  local net=ForeverMarketSaleNet(gross)
  if net-ForeverMarketDepositLoss(qty)<=qty*s.vendor then return 'Vendor pays better or equal',true end
  if ForeverMarketFundHoldPrice then
    local minimum=ForeverMarketFundHoldPrice((not s.commodity and ForeverMarketVariant(s.k,s.link)) or s.k.itemID,qty,s.deposit)
    if ForeverMarketTools and ForeverMarketTools.rule and ForeverMarketTools.rule(s.k.itemID)=='Margin' then
      minimum=math.ceil(minimum*(10000+ForeverMarketMarginBP())/10000)
    end
    local target=ForeverMarketInvestmentTarget and ForeverMarketInvestmentTarget(s.k.itemID)
    if target and unitPrice<target then return 'Investment target '..ForeverMarketCoins(target),true end
    if unitPrice<minimum then return 'Min '..ForeverMarketCoins(minimum),true end
  end
end
local function paint()
  if managing then
    local protected=blacklist()
    for i,row in ipairs(rows) do
      local s=slots[i]
      row.marketId=nil;row.priceReason=nil;row.slot=s;row.itemRef=s and (s.link:find("|H",1,true) and s.link or "item:"..s.k.itemID);row.override=false;row.needsCheck=false;row.quote=nil
      row.name:SetText(s and ForeverMarketRowIcon(s.k.itemID,s.link) or '')
      row.qty:Hide();row.price:SetText('')
      local keep=s and protected[s.k.itemID]
      row.detail:SetText(s and (keep and 'Blacklisted' or 'Allowed') or '')
      row.post:SetText(keep and 'Remove' or 'Protect')
      row.post:SetShown(s~=nil);row.hover:SetShown(s~=nil);row.post:SetEnabled(s~=nil)
    end
    return
  end
  local ready, waiting, held = {}, {}, {}
  local editingOrder={}
  for i,row in ipairs(rows) do if row.slot then editingOrder[row.slot.stackKey]=i end end
  local nextRank = #slots
  -- Existing ranks can exceed the current bag count after a stack is removed.
  for _, rank in pairs(readyRanks) do nextRank = math.max(nextRank, rank) end
  for _, s in ipairs(slots) do
    local q = quotes[s.key]
    if not fresh(q) and (failures[s.key] or 0) >= 2 then
      q = historicalQuote(s, true)
      quotes[s.key] = q
    end
    s.holdReason,s.canOverride = nil,false
    if fresh(q) and price(q,s) then
      local ask = price(q,s)
      s.holdReason,s.canOverride = postingLimit(s, ask)

    end
    local group = waiting
    if s.holdReason then
      group = held
    elseif fresh(q) and price(q,s) and not s.locked then
      group = ready
      if not readyRanks[s.stackKey] then
        nextRank = nextRank + 1
        readyRanks[s.stackKey] = nextRank
      end
    end
    group[#group + 1] = s
  end
  local returns=ForeverMarketTools and ForeverMarketTools.account().relist or {}
  table.sort(ready,function(a,b)
    if (returns[a.k.itemID]~=nil)~=(returns[b.k.itemID]~=nil) then return returns[a.k.itemID]~=nil end
    return readyRanks[a.stackKey]<readyRanks[b.stackKey]
  end)
  readyRanks = {}
  for rank, s in ipairs(ready) do readyRanks[s.stackKey] = rank end
  local ordered = ready
  for _, s in ipairs(waiting) do ordered[#ordered + 1] = s end
  for _, s in ipairs(held) do ordered[#ordered + 1] = s end
  for _,row in ipairs(rows) do
    if row.qty.HasFocus and row.qty:HasFocus() then
      table.sort(ordered,function(a,b) return (editingOrder[a.stackKey] or 100000)<(editingOrder[b.stackKey] or 100000) end)
      break
    end
  end
  for i,row in ipairs(rows) do
    local s=ordered[i];row.slot=s
    row.itemRef=s and s.link;row.hover:SetShown(s~=nil)
    local q=s and quotes[s.key]
    row.name:SetText(s and ForeverMarketRowIcon(s.k.itemID,s.link) or '')
    local raw=s and (quantities[s.stackKey] or tostring(s.commodity and math.min(options(s).size or s.count,s.count) or 1)) or ''
    if row.editKey~=(s and s.stackKey) then row.qty:ClearFocus() end
    row.editKey=s and s.stackKey
    if row.qty:GetText()~=raw then row.qty:SetText(raw) end
    row.qty:SetShown(s~=nil);row.qty:SetEnabled(s and s.commodity or false)
    row.detail:SetText(s and (s.locked and 'Item locked' or fresh(q) and quoteDetail(q) or (failures[s.key] or 0)>=2 and 'No live response' or query and query.key==s.key and 'Looking up…' or 'Queued') or '')
    row.price:SetText(s and s.valid and fresh(q) and (price(q,s) or q.average) and ForeverMarketCoins(price(q,s) or q.average) or '')
    if s and fresh(q) and price(q,s) and quantity(s) then row.price:SetText(ForeverMarketCoins(price(q,s)*quantity(s))) end
    row.marketId=s and s.k.itemID
    row.priceReason=s and (s.holdReason or q and price(q,s) and quantity(s) and ('Post '..quantity(s)..' at '..ForeverMarketCoins(price(q,s))..' each / after cut '..ForeverMarketCoins(ForeverMarketSaleNet(quantity(s)*price(q,s)))..' / deposit '..ForeverMarketCoins(s.deposit or 0)) or nil)
    if row.marketId and fresh(q) then row.priceReason=(row.priceReason or '')..' / '..(q.observed and date('%b %d %H:%M',q.observed) or 'This session')..' / Right-click item to recheck' end
    row.hold = s and s.holdReason ~= nil
    row.override=allowHeld and row.hold and s.canOverride and q.floorPrice~=nil
    if row.hold then
      row.detail:SetText(s.holdReason)
      if not row.override then row.price:SetText('Hold') end
    end
    row.post:SetShown(s~=nil)
    row.needsCheck=s and (not fresh(q) or q.timedOut)
    row.post:SetText(row.needsCheck and 'Check' or row.override and (nativeFallback and 'Sell…' or 'Post held') or nativeFallback and 'Sell…' or 'Post')
    row.post:SetEnabled((not row.hold or row.override) and not pending and s and not s.locked and (row.needsCheck or q and price(q,s)~=nil) or false)
    row.quote=q
  end
end
local function post(row)
  local old=row.slot;if (row.hold and not row.override) or pending or not old then return end
  if managing or blacklist()[old.k.itemID] then return end
  local s=inspect(old.bag,old.slot);local q=row.quote
  if not s or not s.valid or s.locked or s.link~=old.link or s.key~=old.key or s.count~=old.count or not fresh(q) or not price(q,s) or q~=quotes[s.key] then
    bags();paint();caption:SetText('Bag or price changed. Review the refreshed row.');return
  end
  s.stackKey=old.stackKey
  local qty=quantity(s)
  if not qty then return end
  local p=price(q,s)
  local limit,canOverride=postingLimit(s,p,true)
  if limit and not (allowHeld and row.override and canOverride and q.floorPrice) then bags();paint();caption:SetText(limit);return end
  if nativeFallback then
    local ah=AuctionHouseFrame
    local form=s.commodity and ah.CommoditiesSellFrame or ah.ItemSellFrame
    if not form or not AuctionHouseFrameDisplayMode then report('Open Blizzard Sell to post this item.');return end
    local ok,err=pcall(function()
      ah:SetPostItem(s.loc)
      form.QuantityInput:SetQuantity(qty)
      form.PriceInput:SetAmount(p)
      if form.Duration and form.Duration.SetDuration then form.Duration:SetDuration(duration(s)) end
      if ForeverMarketFundPost then ForeverMarketFundPost((not s.commodity and ForeverMarketVariant(s.k,s.link)) or s.k.itemID,qty,p,s.deposit,s.k.itemID) end
    end)
    if not ok then print('Forever Market: review quantity, duration and price on the Sell form. '..tostring(err)) end
    return
  end
  if quantities[s.stackKey] and s.commodity and ForeverMarketTools and ForeverMarketTools.setPosting then
    ForeverMarketTools.setPosting(s.k.itemID,qty,duration(s))
  end
  pendingStack=s.stackKey;pending=GetTime();query=nil
  local attempt=pending
  if C_Timer then C_Timer.After(8,function()
    if pending==attempt then
      pending=nil;pendingStack=nil;nativeFallback=true
      report('Post unconfirmed. Check Auctions before using Sell…');paint()
    end
  end) end
  do
    if ForeverMarketFundPost then ForeverMarketFundPost((not s.commodity and ForeverMarketVariant(s.k,s.link)) or s.k.itemID,qty,p,s.deposit,s.k.itemID) end
    if s.commodity then
      if api.PostCommodity(s.loc,duration(s),qty,p) then AuctionHouseFrame.CommoditiesSellFrame:CachePendingPost(s.loc,duration(s),qty,p) end
    elseif api.PostItem(s.loc,duration(s),qty,nil,p) then AuctionHouseFrame.ItemSellFrame:CachePendingPost(s.loc,duration(s),qty,nil,p) end
  end
  if pending then caption:SetText('Waiting for auction confirmation…');paint() end
end
local function result(ev,arg)
  if not query or not arg then return end
  if ev~='COMMODITY_SEARCH_RESULTS_UPDATED' and ev~='ITEM_SEARCH_RESULTS_UPDATED' and ev~='ITEM_SEARCH_RESULTS_ADDED' then return end
  local commodity=ev=='COMMODITY_SEARCH_RESULTS_UPDATED'
  if commodity~=query.commodity or (commodity and arg~=query.k.itemID) or (not commodity and keyOf(arg)~=keyOf(query.searchKey)) then return end
  local levels={}
  local n=commodity and api.GetNumCommoditySearchResults(arg) or api.GetNumItemSearchResults(arg)
  for i=1,n do
    local r=commodity and api.GetCommoditySearchResultInfo(arg,i) or api.GetItemSearchResultInfo(arg,i)
    local match=r~=nil
    if not commodity then match = r and r.itemKey and r.itemKey.itemID == query.k.itemID and (r.itemKey.battlePetSpeciesID or 0) == (query.k.battlePetSpeciesID or 0) end
    if match and not commodity then
      local variant=ForeverMarketVariant(query.k,query.link)
      match=variant and variant==ForeverMarketVariant(r.itemKey,r.itemLink)

    end
    if match then
      local qty=r.quantity or 1
      local p=commodity and r.unitPrice or r.buyoutAmount and math.floor(r.buyoutAmount/math.max(1,qty))
      if p and p>0 and qty>0 then levels[p]=(levels[p] or 0)+qty end
    end
  end
  if not next(levels) then
    local full
    if commodity then full=api.HasFullCommoditySearchResults else full=api.HasFullItemSearchResults end
    if not full or not full(arg) then
      if not commodity and full and api.RequestMoreItemSearchResults and n>0 and n>(query.pageCount or 0) then
        query.pageCount=n
        lastQuery=GetTime()
        api.RequestMoreItemSearchResults(arg)
      end
      return
    end
  end
  caption:SetText("Checked "..query.link.." · "..n.." auction price rows.")
  local q=ForeverMarketPriceDepth(levels)
  if q then
    if ForeverMarketTools then
      local variant=not commodity and ForeverMarketVariant(query.k,query.link)
      ForeverMarketTools.quotes()[variant or query.k.itemID]={price=q.floorPrice,at=time()}
    end
    local total=0;for _,n in pairs(levels) do total=total+n end
    ForeverMarketObserve(ForeverMarketHistoryKey(query.k),q.low,total,q.floorPrice)
  else
    q=historicalQuote(query,false)
    if ForeverMarketTools then
      local variant=not commodity and ForeverMarketVariant(query.k,query.link)
      ForeverMarketTools.quotes()[variant or query.k.itemID]={empty=true,at=time()}
    end
  end
  q.at=GetTime();q.observed=time();quotes[query.key]=q;forceLookup[query.key]=nil;failures[query.key]=nil;query=nil;paint()
end
local function lookup(s,attempt)
  local k = s.k
  local broad = not s.commodity and attempt > 0 and api.SendSellSearchQuery
  if s.commodity or broad then
    k = api.MakeItemKey(s.k.itemID, nil, nil, s.k.battlePetSpeciesID)
  end
  -- A normal item search uses the same level/suffix key as a Browse row.
  -- Only use the broader sell search on retry and filter its results above.
  local send = broad and api.SendSellSearchQuery or api.SendSearchQuery
  if api.IsThrottledMessageSystemReady and not api.IsThrottledMessageSystemReady() then return end
  if not api.GetItemKeyInfo(k) then
    warming[s.key] = warming[s.key] or GetTime()
    if GetTime()-warming[s.key]>12 then
      failures[s.key]=attempt+1
      warming[s.key]=nil
    end
    return
  end
  warming[s.key]=nil
  query=s
  s.searchKey=k
  s.pageCount=nil
  lastQuery=GetTime()
  local sort={{sortOrder=s.commodity and 0 or 4,reverseSort=false}}
  report("Looking up "..s.link)
  local ok,err=pcall(send,k,sort,true)
  if not ok then failures[s.key]=attempt+1;query=nil;report("Search error: "..tostring(err)) end
  return true
end
local function tick(_,dt)
  paintDelay=paintDelay+dt
  delay=delay+dt;if delay<.1 then return end;delay=0
  if pending then
    if GetTime()-pending<15 then return end
    pending=nil;pendingStack=nil;bags();caption:SetText('Confirmation timed out. Check your auctions before posting again.')
  end
  if query and GetTime()-lastQuery>8 then report("No response for "..query.link);failures[query.key]=(failures[query.key] or 0)+1;query=nil end
  if paintDelay>=.5 then paint();paintDelay=0 end
  if query then return end
  if api.IsThrottledMessageSystemReady and not api.IsThrottledMessageSystemReady() then report("Waiting for the auction house throttle.");return end
  local first=math.floor(scroll:GetVerticalScroll()/rowHeight)+1
  for attempt=0,1 do
  for offset=0,#slots-1 do
    local s=slots[(first-1+offset)%#slots+1]
    if s and s.valid and not fresh(quotes[s.key]) and (failures[s.key] or 0)==attempt then
      if lookup(s,attempt) then return end
    end
  end
  end
end
makeRow=function(i)
  local y=-6-(i-1)*rowHeight
  local row={name=label(content,12,y,225),detail=label(content,300,y,165),price=label(content,475,y,115)}
  row.hover=ForeverMarketHover(content,y+6,590,row)
  row.hover:SetScript('OnMouseUp',function(_,mouse)
    if mouse=='RightButton' and row.slot and not managing then
      local key=row.slot.key;forceLookup[key]=true;quotes[key]=nil;failures[key]=nil;warming[key]=nil
      paused=false;paint()
    end
  end)
  row.qty=CreateFrame('EditBox',nil,content,'InputBoxTemplate')
  row.qty:SetSize(42,20);row.qty:SetPoint('TOPLEFT',245,y+4);row.qty:SetAutoFocus(false)
  row.qty:SetFrameLevel((row.hover.GetFrameLevel and row.hover:GetFrameLevel() or 1)+1)
  row.qty:SetScript('OnEditFocusGained',function(self) self:HighlightText() end)
  row.qty:SetScript('OnTextChanged',function(self,user)
    if user and row.slot and row.slot.commodity and row.editKey==row.slot.stackKey then
      quantities[row.editKey]=self:GetText();paint()
    end
  end)
  row.qty:SetScript('OnEnterPressed',function(self) self:ClearFocus() end)
  row.qty:SetScript('OnEscapePressed',function(self)
    if row.editKey then quantities[row.editKey]=nil end
    self:ClearFocus();paint()
  end)
  row.post=button(content,'Post',600,y+5,62,function()
    local pressed = row.pressed
    row.pressed = nil
    if pressed and (row.pressedManaging~=managing or not row.slot or pressed.stackKey ~= row.slot.stackKey or pressed.count ~= row.slot.count or row.pressedQuote ~= row.quote or row.pressedCheck ~= row.needsCheck or row.pressedQty~=quantity(row.slot)) then
      caption:SetText('The row changed. Review the item and click again.')
      return
    end
    if managing then
      if not row.slot then return end
      local protected=blacklist()
      local id=row.slot.k.itemID
      if protected[id] then protected[id]=nil else protected[id]=row.slot.link end
      bags();paint();return
    end
    if row.needsCheck and row.slot then
      failures[row.slot.key]=nil
      if row.quote and row.quote.timedOut then quotes[row.slot.key]=nil end
      local ok,err=pcall(lookup,row.slot,0,nil)
      if not ok then report('Search error: '..tostring(err))
      elseif not err then report('Loading item information for '..row.slot.link) end
    else post(row) end
  end)
  row.post:SetScript('OnMouseDown',function()
    row.pressedQty=row.slot and quantity(row.slot)
    row.pressedManaging=managing
    row.pressed, row.pressedQuote, row.pressedCheck = row.slot, row.quote, row.needsCheck
  end)
  row.post:SetScript('OnEnter',function(self)
    if not row.slot or not row.quote or not price(row.quote,row.slot) then return end
    local qty=quantity(row.slot);if not qty then return end
    GameTooltip:SetOwner(self,'ANCHOR_RIGHT')
    GameTooltip:AddLine('Duration: '..(({12,24,48})[duration(row.slot)])..' hours')
    GameTooltip:AddLine('Unit price: '..ForeverMarketCoins(price(row.quote,row.slot)))
    GameTooltip:AddLine('Estimated return after fees if sold: '..ForeverMarketCoins(ForeverMarketSaleNet(price(row.quote,row.slot)*qty)))
    GameTooltip:AddLine('Deposit due now: '..ForeverMarketCoins(row.slot.deposit))
    GameTooltip:Show()
  end)
  row.post:SetScript('OnLeave',function() GameTooltip:Hide() end)
  row.post:SetHeight(21);row.name:SetWordWrap(false);row.detail:SetWordWrap(false)
  return row
end
local lastScope
local function create()
  if panel or not AuctionHouseFrame then return end
  panel=CreateFrame('Frame',nil,AuctionHouseFrame);panel:SetPoint('TOPLEFT',14,-62);panel:SetPoint('BOTTOMRIGHT',-12,38);panel:Hide()
  caption=label(panel,12,-8,192);caption:SetText('Edit Qty or post the next ready stack.')
  local override=button(panel,'Post held: off',437,-6,151,function(self)
    allowHeld=not allowHeld;self:SetText(allowHeld and 'Post held: on' or 'Post held: off');paint()
  end)
  local nextRow,nextKey,nextQuote,nextQty
  local nextButton=button(panel,'Post next',210,-6,95,function()
    if nextRow and nextRow.slot and nextRow.slot.stackKey==nextKey and nextRow.quote==nextQuote and quantity(nextRow.slot)==nextQty and not nextRow.hold and not nextRow.needsCheck then post(nextRow)
    else caption:SetText('Review the first ready row and click Post next again.') end
    nextRow=nil
  end)
  nextButton:SetScript('OnMouseDown',function()
    nextRow=nil
    if not managing then for _,row in ipairs(rows) do
      if row.slot and not row.hold and not row.needsCheck and not row.slot.locked and row.quote and price(row.quote,row.slot) then
        nextRow=row;nextKey=row.slot.stackKey;nextQuote=row.quote;nextQty=quantity(row.slot);break
      end
    end end
  end)
  local manage=button(panel,'Blacklist',318,-6,110,function(self)
    managing=not managing;query=nil
    self:SetText(managing and 'Done' or 'Blacklist')
    override:SetEnabled(not managing)
    caption:SetText(managing and 'Protect items from Market Sell on this character.' or 'Edit Qty to change the stack total.')
    bags();paint()
  end)
  button(panel,'Refresh',600,-6,75,function() paused=false;failures={};warming={};for _,s in ipairs(slots) do if s.key then forceLookup[s.key]=true end end;for key in pairs(quotes) do quotes[key]=nil end;query=nil;paint() end)
  ForeverMarketResults(panel,38,{{'Name',0},{'Qty',237},{'Bulk ask × supply',292},{'Stack total',467},{'Action',592}})
  scroll=CreateFrame('ScrollFrame','ForeverMarketSellScroll',panel,'UIPanelScrollFrameTemplate')
  scroll:SetPoint('TOPLEFT',0,-64)
  scroll:SetPoint('BOTTOMRIGHT',-30,8)
  content=CreateFrame('Frame',nil,scroll)
  content:SetSize(670,1)
  scroll:SetScrollChild(content)
  scroll:EnableMouseWheel(true)
  scroll:SetScript('OnMouseWheel',function(self,delta)
    self:SetVerticalScroll(math.max(0,math.min(self:GetVerticalScrollRange(),self:GetVerticalScroll()-delta*rowHeight*3)))
  end)
  panel:SetScript('OnShow',function() local scope=table.concat({GetCurrentRegion(),GetRealmID and GetRealmID() or 0,GetRealmName(),UnitFactionGroup("player")},"|");if lastScope~=scope then ForeverMarketDB.sellPins=ForeverMarketDB.sellPins or {};ForeverMarketDB.sellPins[scope]=ForeverMarketDB.sellPins[scope] or {};quotes=ForeverMarketDB.sellPins[scope];readyRanks={};quantities={};lastScope=scope end;failures={};warming={};bags();paint() end)
  panel:SetScript('OnHide',function() query=nil;allowHeld=false;managing=false;manage:SetText('Blacklist');override:SetEnabled(true);override:SetText('Post held: off') end)
  panel:SetScript('OnUpdate',function(self,dt)
    if paused or managing then return end
    local ok,err=pcall(tick,self,dt)
    if not ok then
      if query then failures[query.key]=2;query=nil end
      paused=true
      report('Lookups paused: '..tostring(err))
    end
  end)
  ForeverMarketTab('ForeverMarketSell',panel,'Market Sell','Forever Market')
end
local events=CreateFrame('Frame')
for _,ev in ipairs({'AUCTION_HOUSE_SHOW','COMMODITY_SEARCH_RESULTS_UPDATED','ITEM_SEARCH_RESULTS_UPDATED','BAG_UPDATE_DELAYED','AUCTION_HOUSE_AUCTION_CREATED','UI_ERROR_MESSAGE','ADDON_ACTION_BLOCKED','ADDON_ACTION_FORBIDDEN'}) do events:RegisterEvent(ev) end
if api.RequestMoreItemSearchResults then pcall(events.RegisterEvent, events, 'ITEM_SEARCH_RESULTS_ADDED') end
events:SetScript('OnEvent',function(_,ev,arg,msg)
  if ev=='AUCTION_HOUSE_SHOW' then create();return end
  if (ev=='ADDON_ACTION_BLOCKED' or ev=='ADDON_ACTION_FORBIDDEN') and pending then
    pending=nil;pendingStack=nil;nativeFallback=true;report('WoW blocked the action. Use Sell… to open Blizzard Sell.');paint();return
  end
  if not panel or not panel:IsVisible() then return end
  if ev=='BAG_UPDATE_DELAYED' then bags();paint()
  elseif ev=='AUCTION_HOUSE_AUCTION_CREATED' then if pendingStack then quantities[pendingStack]=nil;pendingStack=nil end;pending=nil;caption:SetText('Auction posted.');bags();paint()
  elseif ev=='UI_ERROR_MESSAGE' then if pending then pending=nil;pendingStack=nil;caption:SetText(tostring(msg));paint() end
  elseif not paused then
    local ok,err=pcall(result,ev,arg)
    if not ok then paused=true;query=nil;report('Result error: '..tostring(err)) end
  end
end)
