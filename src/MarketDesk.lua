local M=ForeverMarketTools
local trip,job
function M.basketFilters()
  local a=M.account()
  M.restockList()
  a.filtersByList=a.filtersByList or {}
  local key=a.manager.active
  a.filtersByList[key]=a.filtersByList[key] or {}
  return a.filtersByList[key]
end
function M.categoryFilters(path)
  local function visit(categories,prefix)
    for _,c in ipairs(categories or {}) do
      local key=prefix..(c.name or '')
      if key==path then
        local out={}
        for _,row in ipairs(c.filters or {}) do
          if type(row.classID)~='number' or row.inventoryType and not (C_Item and C_Item.GetItemInventoryTypeByID) then return end
          out[#out+1]={classID=row.classID,subClassID=row.subClassID,inventoryType=row.inventoryType}
        end
        if #out>0 then return out end
      elseif c.subCategories and path:sub(1,#key+1)==key..'/' then return visit(c.subCategories,key..'/') end
    end
  end
  return visit(AuctionCategories,'')
end
function M.addBasketFilter(filter,n)
  if not n or n<1 or n>9999 or n~=math.floor(n) then return 'Enter a whole target quantity from 1 to 9999.' end
  local list=M.basketFilters()
  for _,r in ipairs(list) do
    local same=true
    for _,key in ipairs({'term','max','level','minLevel','quality','minItemLevel','maxItemLevel','minPrice','category','exactName','watch','vendor','usable'}) do
      if (filter[key] or false)~=(r[key] or false) then same=false;break end
    end
    if same then r.units=n;trip=nil;job=nil;return 'Updated existing basket filter.' end
  end
  if #list>=30 then return 'This list already has 30 filters.' end
  local copy={units=n}
  for k,v in pairs(filter) do copy[k]=v end
  list[#list+1]=copy;trip=nil;job=nil
  return 'Filter saved in '..M.account().manager.active..'. Open Basket and run the list.'
end
function M.removeBasketFilter(i)
  table.remove(M.basketFilters(),i);trip=nil;job=nil;return 'Filter removed.'
end
function M.tripTargets()
  local exact=M.restockList()
  if trip and trip.list==exact and ForeverMarketReadySnapshot and ForeverMarketReadySnapshot()==trip.snap then
    local merged={}
    for id,row in pairs(trip.items) do merged[id]=row end
    for id,row in pairs(exact) do merged[id]=row end
    return merged
  end
  return exact
end
function M.runBasket()
  if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then return 'Open the auction house first.' end
  M.cancelMaterial();trip=nil
  job={list=M.restockList(),filters=M.basketFilters(),index=1,items={},started=GetTime()}
  return 'Checking shopping list against the market.'
end
function M.stepBasket()
  if not job then return end
  if job.list~=M.restockList() or not AuctionHouseFrame:IsShown() then job=nil;return end
  if not job.snap then
    if job.retry and GetTime()<job.retry then return end
    job.retry=GetTime()+.5
    job.snap=ForeverMarketSnapshot and ForeverMarketSnapshot()
    if not job.snap then
      if GetTime()-job.started>20 then job=nil;print('Forever Market: snapshot unavailable. Run Market Scan and retry the basket.') end
      return
    end
  end
  local rule=job.filters[job.index]
  if rule then
    job.matches,job.cursor=M.findOffers(rule,job.snap,job.matches,job.cursor,400)
    if job.cursor then return end
    for _,offer in ipairs(job.matches) do
      local row=job.items[offer.id]
      if not row then job.items[offer.id]={keep=rule.units,cap=rule.max}
      else
        row.keep=math.max(row.keep,rule.units)
        if rule.max>0 and (row.cap==0 or rule.max<row.cap) then row.cap=rule.max end
      end
    end
    job.matches=nil;job.index=job.index+1;return
  end
  trip=job;job=nil;M.tripDirty=true
end

local function missingStock()
  local needs={}
  for id,n in pairs(M.materials()) do needs[id]=n end
  for id,r in pairs(M.restockList()) do needs[id]=math.max(needs[id] or 0,r.keep) end
  local desk=M.account().desk
  for id,group in pairs(desk and desk.groups or {}) do
    if group.bankTarget then needs[id]=math.max(needs[id] or 0,group.bankTarget) end
  end
  for id,n in pairs(needs) do needs[id]=math.max(0,n-M.bagCount(id)) end
  return needs
end
local events=CreateFrame('Frame')
for _,ev in ipairs({'BANKFRAME_OPENED','BANKFRAME_CLOSED','GUILDBANKFRAME_OPENED','GUILDBANKFRAME_CLOSED','GUILDBANKBAGSLOTS_CHANGED','BAG_UPDATE_DELAYED','MAIL_SEND_INFO_UPDATE','MAIL_SEND_SUCCESS'}) do
  pcall(events.RegisterEvent,events,ev)
end
events:SetScript('OnEvent',function(_,ev)
  if ev=='BANKFRAME_OPENED' then M.bankOpen=true elseif ev=='BANKFRAME_CLOSED' then M.bankOpen=false
  elseif ev=='GUILDBANKFRAME_OPENED' then M.guildOpen=true elseif ev=='GUILDBANKFRAME_CLOSED' then M.guildOpen=false end
  M.logisticsDirty=true
end)
function M.bankQueue()
  local rows={}
  if not M.bankOpen and not M.guildOpen then return rows end
  local need=missingStock()
  local function add(id,n,locked,bag,slot,guild)
    if not id or locked then return end
    local required=need[id] or 0
    local destination=not guild and M.bankDispatchTo(id)
    if required<=0 and not destination then return end
    local take=required>0 and math.min(required,n) or n
    need[id]=math.max(0,required-take)
    local label=guild and 'From guild bank tab '..bag or 'From personal bank'
    if destination and required==0 then label=label..' for '..destination end
    rows[#rows+1]={id=id,n=take,count=n,bag=bag,slot=slot,guild=guild,label=label}
  end
  if M.bankOpen then
    local last=NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    local function read(b)
      for i=1,C_Container.GetContainerNumSlots(b) do local r=C_Container.GetContainerItemInfo(b,i)
        if r then add(r.itemID,r.stackCount,r.isLocked,b,i,false) end
      end
    end
    read(-1);for b=last+1,last+(NUM_BANKBAGSLOTS or 7) do read(b) end
  elseif GetCurrentGuildBankTab and GetGuildBankTabInfo and GetGuildBankItemLink and GetGuildBankItemInfo then
    local tab=GetCurrentGuildBankTab()
    if not tab or tab<1 then return rows end
    local _,_,view,_,_,remaining=GetGuildBankTabInfo(tab)
    if view and remaining and remaining~=0 then
      for i=1,MAX_GUILDBANK_SLOTS_PER_TAB or 98 do
        local link=GetGuildBankItemLink(tab,i)
        if link then local _,n,locked=GetGuildBankItemInfo(tab,i);if n and n>0 then add(tonumber(link:match('item:(%d+)')),n,locked,tab,i,true) end end
      end
    end
  end
  return rows
end
function M.withdraw(row)
  if CursorHasItem() then return 'Clear your cursor.' end
  for _,r in ipairs(M.bankQueue()) do
    if r.id==row.id and r.bag==row.bag and r.slot==row.slot and r.guild==row.guild and r.n==row.n then
      local bag,slot
      for b=0,NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
        local free,family=C_Container.GetContainerNumFreeSlots(b)
        if free and free>0 and family==0 then
          for i=1,C_Container.GetContainerNumSlots(b) do if not C_Container.GetContainerItemInfo(b,i) then bag,slot=b,i;break end end
        end
        if slot then break end
      end
      if not slot then return 'Free a slot in a general-purpose bag.' end
      local full=r.n==r.count
      local pickup
      if r.guild then
        if full then pickup=PickupGuildBankItem else pickup=SplitGuildBankItem end
      elseif full then pickup=C_Container.PickupContainerItem else pickup=C_Container.SplitContainerItem end
      if not pickup then return 'This client does not support this withdrawal.' end
      if full then pickup(r.bag,r.slot) else pickup(r.bag,r.slot,r.n) end
      if CursorHasItem() then C_Container.PickupContainerItem(bag,slot) end
      if CursorHasItem() then ClearCursor();return 'Transfer declined. Check bag space and permissions.' end
      M.logisticsDirty=true;return 'Withdrawal requested.'
    end
  end
  return 'Stock or permissions changed. Refresh the queue.'
end

local floors={}
function M.policyFloor(id,force,preview)
  local group=preview or M.group(id)
  if not group or (group.craftPct or 0)+(group.realmPct or 0)==0 then return group and group.fixedFloor or 0 end
  local cached=floors[id]
  if not force and cached and cached.group==group and GetTime()-cached.at<3 then return cached.floor,cached.why end
  local floor,why=0,nil
  if (group.realmPct or 0)>0 then
    local history=ForeverMarketHistory()[tostring(id)]
    local asks,today={},math.floor(time()/86400)
    for day,value in pairs(history and history.floors or {}) do
      day=tonumber(day)
      if day and day<=today and day>today-15 then asks[#asks+1]=value end
    end
    if #asks>0 then
      table.sort(asks);local n=#asks
      floor=math.ceil((asks[math.ceil(n/2)]+asks[math.floor(n/2)+1])*group.realmPct/200) else why='Need realm bulk-price history' end
  end
  if (group.craftPct or 0)>0 then
    local cheapest
    for guid,a in pairs(ForeverMarketDB.characters or {}) do
      if guid==UnitGUID('player') or a.stockScope==M.inventoryScope() then
        for _,recipe in pairs(a.recipes or {}) do
          if recipe.output==id and (recipe.yield or 0)>0 then
            local inputs=M.inputs(recipe,1)
            local cost=0
            if inputs and next(inputs) then
              for mat,n in pairs(inputs) do
                local price=M.cost(mat,n);if not price then cost=nil;break end
                cost=cost+price
              end
              if cost then cheapest=math.min(cheapest or math.huge,cost/recipe.yield) end
            end
          end
        end
      end
    end
    if cheapest then floor=math.max(floor,math.ceil(cheapest*group.craftPct/100)) else why='Need priced recipe for posting rule' end
  end
  floor=math.max(floor,group.fixedFloor or 0)
  if not preview then floors[id]={group=group,at=GetTime(),floor=floor,why=why} end
  return floor,why
end
function M.stockPostRestriction(id,qty,unit,force,incoming)
  local blocked=ForeverMarketDB.__sellBlacklist
  local personal=blocked and blocked[UnitGUID('player')]
  if personal and personal[id] or not personal and (id==2901 or id==5956) then return 'Protected item' end
  if M.rule(id)=='Keep' then return 'Keep for profession' end
  local required=M.materials()[id] or 0
  if required>0 and M.bagCount(id)+(incoming or 0)-qty<required then return 'Reserved for crafting or restocking' end
  return M.checkPostPolicy(id,qty,unit,force,incoming)
end
function M.checkPostPolicy(id,qty,unit,force,incoming)
  local g=M.group(id)
  if not g then return end
  local floor,why=M.policyFloor(id,force)
  if why then return why end
  if unit and unit<floor then return 'Posting floor changed. Review the price.' end
  if (g.reserve or 0)>0 and M.bagCount(id)+(incoming or 0)-qty<g.reserve then return 'Group bag reserve' end
  if (g.postCap or 0)>0 then
    local api=C_AuctionHouse
    if not api.GetNumOwnedAuctions or not api.GetOwnedAuctionInfo or api.HasFullOwnedAuctionResults and not api.HasFullOwnedAuctionResults() then return 'Waiting for owned listings' end
    local posted=0
    for i=1,api.GetNumOwnedAuctions() do local r=api.GetOwnedAuctionInfo(i)
      if r and r.status==0 and r.itemKey and r.itemKey.itemID==id then posted=posted+(r.quantity or 1) end
    end
    if posted+qty>g.postCap then return 'Group listed-unit cap' end
  end
end

local function median(values)
  local n=#values
  if n==0 then return end
  table.sort(values)
  return math.floor((values[math.ceil(n/2)]+values[math.floor(n/2)+1])/2+.5)
end
function M.tradeResults(days,invest)
  local s={spent=0,open=0,profit=0,forecast=0,paid=0,count=0,items={}}
  local delays={}
  for _,r in ipairs(ForeverMarketTradingFund().flips or {}) do
    if r.at and r.at>=time()-days*86400 and r.n>0 and (r.invest==true)==invest then
      local paid=r.sold or 0
      local basis=math.floor(r.cost*paid/r.n)
      local profit=(r.net or 0)-basis-(r.lost or 0)
      local name=r.name or ('Item '..tostring(r.item));local item=s.items[name] or {profit=0,open=0,paid=0}
      s.items[name]=item;item.profit=item.profit+profit;item.open=item.open+r.cost-basis;item.paid=item.paid+paid
      s.spent=s.spent+r.cost;s.open=s.open+r.cost-basis;s.profit=s.profit+profit
      s.forecast=s.forecast+math.floor((r.expected or 0)*paid/r.n);s.paid=s.paid+paid;s.count=s.count+1
      if r.firstPaid then delays[#delays+1]=math.max(0,r.firstPaid-r.at) end
    end
  end
  s.timed=#delays;s.delay=median(delays)
  return s
end

local function suffix(key,link)
  local raw=link and link:match('item:%d+:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:(%-?%d+)')
  local suffix=tonumber(raw)
  return tostring(suffix and suffix~=0 and suffix or key.itemSuffix or 0)
end
local function gearStore()
  ForeverMarketDB.gearEvidence=ForeverMarketDB.gearEvidence or {}
  local scope=GetCurrentRegion()..'|'..M.scope()
  local t=ForeverMarketDB.gearEvidence
  t[scope]=t[scope] or {};return t[scope]
end
function M.recordGearBook(key,count)
  if not C_Item.GetItemInfoInstant then return end
  local slot=select(4,C_Item.GetItemInfoInstant(key.itemID))
  if not slot or slot=='' or (key.battlePetSpeciesID or 0)>0 then return end
  local api=C_AuctionHouse
  if api.HasFullItemSearchResults and not api.HasFullItemSearchResults(key) then return end
  local buckets={}
  for i=1,count do
    local r=api.GetItemSearchResultInfo(key,i)
    if r and r.itemKey and r.itemKey.itemID==key.itemID and r.buyoutAmount and r.buyoutAmount>0 then
      local link=r.itemLink or (api.GetItemSearchResultItemLink and api.GetItemSearchResultItemLink(key,i))
      if link then
        local k=(r.itemKey.itemLevel or 0)..'/'..suffix(r.itemKey,link)
        buckets[k]=buckets[k] or {};table.insert(buckets[k],math.floor(r.buyoutAmount/math.max(1,r.quantity or 1)))
      end
    end
  end
  local store=gearStore();local day=math.floor(time()/86400)
  local series=store[key.itemID] or {}
  for k,prices in pairs(buckets) do
    series[k]=series[k] or {};series[k][day]={ask=median(prices),rows=#prices,at=time()}
  end
  for k,t in pairs(series) do for d in pairs(t) do if d<day-29 then t[d]=nil end end;if not next(t) then series[k]=nil end end
  store[key.itemID]=next(series) and series or nil
end
function M.gearEvidence(key,link)
  local set=gearStore()[key.itemID];if not set then return end
  local level=tostring(key.itemLevel or 0);local exact=level..'/'..suffix(key,link)
  local first,other={},{};local latest
  for k,t in pairs(set) do
    if k:match('^(%d+)/')==level then for day,sample in pairs(t) do
      if day>=math.floor(time()/86400)-29 then
        if k==exact then first[#first+1]=sample.ask;if not latest or sample.at>latest.at then latest=sample end
        else other[day]=other[day] or {};table.insert(other[day],sample.ask) end
      end
    end end
  end
  local compared={};for _,prices in pairs(other) do compared[#compared+1]=median(prices) end
  local typical=median(first);local comp=median(compared)
  return {exact=typical,days=#first,last=latest,other=comp,otherDays=#compared,low=compared[math.max(1,math.ceil(#compared*.25))],high=compared[math.max(1,math.ceil(#compared*.75))]}
end
