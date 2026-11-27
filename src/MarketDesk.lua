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
function M.policyFloor(id,force)
  local group=M.group(id)
  if not group or (group.craftPct or 0)+(group.realmPct or 0)==0 then return 0 end
  local cached=floors[id]
  if not force and cached and cached.group==group and GetTime()-cached.at<3 then return cached.floor,cached.why end
  local floor,why=0,nil
  if (group.realmPct or 0)>0 then
    local history=ForeverMarketHistory()[tostring(id)]
    local total,days,today=0,0,math.floor(time()/86400)
    for day,value in pairs(history and history.floors or {}) do
      day=tonumber(day)
      if day and day<=today and day>today-15 then total=total+value;days=days+1 end
    end
    if days>0 then floor=math.ceil(total/days*group.realmPct/100) else why='Need realm bulk-price history' end
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
  floors[id]={group=group,at=GetTime(),floor=floor,why=why}
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
