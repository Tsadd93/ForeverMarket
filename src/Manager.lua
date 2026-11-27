local neutralNPC={[8661]=true,[9857]=true,[9858]=true,[15681]=true}
local function auctioneer()
  local guid=UnitGUID('npc')
  return guid and tonumber(guid:match('^Creature%-[^-]+%-[^-]+%-[^-]+%-[^-]+%-(%d+)'))
end
local M,api=ForeverMarketTools,C_AuctionHouse
local function prefs()
  local a=M.account()
  if not a.manager then a.manager={lists={Default={}},active='Default',rules={},ledger={},days={},alerts={},samples={}} end
  return a.manager
end
local function nameOf(id) return C_Item.GetItemNameByID(id) or ('Item '..id) end
local function itemID(text) return tonumber(text:match('item:(%d+)') or text:match('^%s*(%d+)%s*$')) end
local function whole(s,max)
  local n=type(s)=='string' and s:match('^%d+$') and tonumber(s)
  if n and n<=max then return n end
end
function M.restockList()
  local p=prefs()
  return p.lists[p.active]
end
function M.rule(id)
  local rules=prefs().rules
  local class=select(12,C_Item.GetItemInfo(id))
  return rules[id] or rules['class'..tostring(class)] or 'Quick'
end
local alerted={}
function M.checkAlert(key,price)
  local id=tonumber(key);if not id then return end
  local cap=prefs().alerts[id]
  if not cap then return end
  if price>cap then alerted[id]=nil;return end
  if alerted[id]==cap then return end
  alerted[id]=cap
  ForeverMarketPrintItemText('Forever Market: '..nameOf(id)..' observed at '..ForeverMarketCoins(price)..'.')
end
function M.exportList()
  local parts={}
  for id,r in pairs(M.restockList()) do parts[#parts+1]=id..','..r.keep..','..r.cap end
  table.sort(parts)
  return 'FM1;'..table.concat(parts,';')
end
function M.importList(text)
  if #text>12000 or text:sub(1,4)~='FM1;' then return false end
  local entries={}
  for record in text:sub(5):gmatch('[^;]+') do
    local id,n,cap=record:match('^(%d+),(%d+),(%d+)$')
    id=whole(id,2147483647);n=whole(n,9999);cap=whole(cap,9999999999)
    if not id or id<1 or not n or n<1 or not cap then return false end
    entries[id]={keep=n,cap=cap}
  end
  for id,r in pairs(entries) do M.restockList()[id]=r end
  M.invalidate();return true
end
local function ledger(name)
  local p=prefs()
  local r=p.ledger[name]
  if not r then r={bought=0,sold=0,paid=0,earned=0,loss=0,proceeds=0,matched=0};p.ledger[name]=r end
  return r
end
function M.trackAcquisition(name,n)
  if name then local r=ledger(name);r.tracked=(r.tracked or 0)+n end
end
function M.settleLot(lot,e,n,basis,credit,deposit)
  local r=ledger(e.name)
  r.matched=r.matched+n
  r.matchedCash=(r.matchedCash or 0)+(credit or math.floor(e.amount*n/e.quantity))
  r.earned=r.earned+(credit and credit-deposit or math.floor((e.amount-e.deposit)*n/e.quantity))-basis
end
function M.saleCount(name)
  local days=prefs().days[name]
  local n,count=0,0
  local today=math.floor(time()/86400)
  for day,d in pairs(days or {}) do if day>today-7 and day<=today then n=n+d.n;count=count+d.count end end
  return n,count
end
function M.saleLabel(name)
  local n,count=M.saleCount(name)
  return n..' sold across '..count..' collected sales in the last 7 calendar days'
end
-- Compare 14 days of listings in this market. A new listing gets time to sell
-- before an unresolved outcome weighs against it.
local turnover={}
function M.marketOutcomes(name)
  local events=ForeverMarketActivity and ForeverMarketActivity.events
  if not events then return end
  local now=time();local hour=math.floor(now/3600);local scope=M.scope()
  if turnover.hour~=hour or turnover.scope~=scope or turnover.events~=events or turnover.index>#events then
    turnover={hour=hour,scope=scope,events=events,index=0,byName={},posts={},seen={}}
  end
  for i=turnover.index+1,#events do
    local e=events[i]
    if e.name and e.at and e.at>=now-14*86400 and (not e.region or e.region==GetCurrentRegion()) and (ForeverMarketEventRealm and ForeverMarketEventRealm(e) or e.realm or '')..'|'..(e.faction or '')==scope then
      local id=e.auctionId
      local post=id and turnover.posts[id]
      local key=post and post.name or e.name
      if e.kind=='posted' or e.kind=='sale_notice' and id or e.kind=='auction_expired' or e.kind=='proceeds_collected' and e.invoiceType=='seller' then
        local r=turnover.byName[key] or {sales=0,returns=0,mature=0,linked=0,hours=0}
        turnover.byName[key]=r
        if e.kind=='proceeds_collected' and e.amount and e.deposit and e.fee and (e.quantity or 0)>0 and e.character==UnitName('player') then
          if e.at>=now-7*86400 then r.paidWeek=(r.paidWeek or 0)+e.quantity;r.receiptsWeek=(r.receiptsWeek or 0)+1 end
          r.paidUnits=(r.paidUnits or 0)+e.quantity;r.receipts=(r.receipts or 0)+1
          local gross=e.amount+e.fee-e.deposit
          r.gross=(r.gross or 0)+gross
          if not r.lastPaid or e.at>=r.lastPaid then r.lastPaid=e.at;r.lastUnit=math.floor(gross/e.quantity) end
        elseif e.kind=='posted' and id and not post then
          local mature=now-e.at>=12*3600
          turnover.posts[id]={name=key,at=e.at,mature=mature}
          if mature then r.mature=r.mature+1 end
        elseif e.kind=='sale_notice' and not turnover.seen[id] then
          turnover.seen[id]=true;r.sales=r.sales+1
          if post and e.at>=post.at then
            r.linked=r.linked+1;r.hours=r.hours+(e.at-post.at)/3600
            if post.mature then r.mature=r.mature-1 end
          end
        elseif e.kind=='auction_expired' then r.returns=r.returns+1 end
      end
    end
  end
  turnover.index=#events
  return turnover.byName[name]
end
function M.salesWeight(name)
  local r=M.marketOutcomes(name)
  if not r then return 1 end
  -- An expired listing can also appear among the unresolved postings.
  local reliability=(r.sales+2)/(r.sales+math.max(r.returns,r.mature)+4)
  local speed=(12+r.linked*6)/(12+r.hours)
  return math.max(.35,math.min(1.8,2*reliability*math.max(.65,math.min(1.3,speed))))
end

-- Attribute identical units FIFO within a fund holding. Keep unknown legacy
-- stock separate and spread invoice rounding across units exactly once.
local function moveShares(source,total,n,visit)
  local known=0
  for _,s in ipairs(source or {}) do known=known+s.n end
  local left=n-math.min(n,total-known)
  local offset=n-left
  for _,s in ipairs(source or {}) do
    if left<=0 then break end
    local take=math.min(s.n,left)
    if take>0 then visit(s.id,take,offset);s.n=s.n-take;left=left-take;offset=offset+take end
  end
end
local function addShare(owner,id,n)
  owner.shares=owner.shares or {}
  for _,s in ipairs(owner.shares) do if s.id==id then s.n=s.n+n;return end end
  owner.shares[#owner.shares+1]={id=id,n=n}
end
function M.beginFlip(f,h,p,e)
  if p.forecast==nil then return end
  f.flips=f.flips or {}
  local id=#f.flips+1
  f.flips[id]={run=p.run,name=e.name or nameOf(p.id),item=p.id,at=e.at or time(),n=p.n,cost=e.total,
    expected=p.forecast,invest=p.target~=nil,sold=0,net=0,lost=0,listed=0}
  addShare(h,id,p.n)
end
function M.listFlip(h,lot,previous)
  moveShares(h.shares,previous,lot.n,function(id,n)
    addShare(lot,id,n)
    local r=ForeverMarketTradingFund().flips[id];r.listed=r.listed+n
  end)
end
local function portion(total,offset,n,count)
  return math.floor(total*(offset+n)/count)-math.floor(total*offset/count)
end
function M.payFlip(lot,e,n,offset)
  moveShares(lot.shares,lot.n,n,function(id,take,start)
    local r=ForeverMarketTradingFund().flips[id]
    r.wallet=(r.wallet or 0)+portion(e.amount,offset+start,take,e.quantity)
    r.net=r.net+portion(e.amount-e.deposit,offset+start,take,e.quantity)
    if r.run and r.at and (e.at or time())<=r.at+7*86400 then
      r.weekNet=(r.weekNet or 0)+portion(e.amount-e.deposit,offset+start,take,e.quantity)
      r.weekPaid=(r.weekPaid or 0)+take
    end
    if r.sold==0 then r.firstPaid=e.at or time() end
    r.listed=r.listed-take;r.sold=r.sold+take;r.lastPaid=e.at or time()
  end)
end
local function returnFlip(h,lot,loss)
  moveShares(lot.shares,lot.n,lot.n,function(id,take,start)
    local r=ForeverMarketTradingFund().flips[id]
    if r.run and r.at and time()<=r.at+7*86400 then r.weekLost=(r.weekLost or 0)+portion(loss,start,take,lot.n) end
    r.lost=r.lost+portion(loss,start,take,lot.n);r.listed=r.listed-take
    addShare(h,id,take)
  end)
end
local function restoreLot(lot,r,fee)
  local h=ForeverMarketTradingFund().held[lot.holding]
  if not h then return end
  if lot.target and (lot.invested or 0)>0 then h.target=math.max(h.target or 0,lot.target);h.invested=(h.invested or 0)+math.min(lot.n,lot.invested) end
  h.n=h.n+lot.n;h.cost=(h.cost or 0)+lot.basis
  returnFlip(h,lot,lot.deposit+(fee or 0))
  r.loss=r.loss+lot.deposit+(fee or 0)
  lot.n=0;lot.basis=0;lot.deposit=0;lot.unpaid=0
end
function M.recordMarket(kind,e)
  if kind=='cancel_confirmed' then
    local c=M.pendingCancel
    if c and c.queued and (not e or e.auctionID~=c.id) then c.removalNotice=true;return end
    M.pendingCancel=nil
    if c and GetTime()-c.at<(c.queued and 13 or 10) then
      local a=M.account();a.relist=a.relist or {};a.relist[c.item]=time()
      for _,lot in ipairs(ForeverMarketTradingFund().lots) do
        if lot.auctionId==c.id and lot.n>0 and lot.basis then
          local fee=math.ceil(c.fee*lot.n/(lot.posted or lot.n))
          local f=ForeverMarketTradingFund();ForeverMarketChangeCash(f,-fee,'Cancellation fee',lot.name)
          restoreLot(lot,ledger(lot.name),fee);break
        end
      end
    end
    return
  end
  if not e.name or not e.quantity or e.quantity<1 then return end
  local a=M.account()
  if kind=="posted" and M.sellingTimer then M.sellingTimer.posts=M.sellingTimer.posts+1 end
  if kind=='purchase' and e.total then
    local r=ledger(e.name);r.bought=r.bought+e.quantity;r.paid=r.paid+e.total
  elseif kind=='proceeds_collected' and e.invoiceType=='seller' and e.amount then
    local r=ledger(e.name);r.sold=r.sold+e.quantity;r.proceeds=r.proceeds+e.amount
    local days=prefs().days;days[e.name]=days[e.name] or {}
    local day=math.floor(e.at/86400)
    local bucket=days[e.name][day] or {n=0,count=0};days[e.name][day]=bucket
    bucket.n=bucket.n+e.quantity;bucket.count=bucket.count+1
    for d in pairs(days[e.name]) do if d<=day-7 then days[e.name][d]=nil end end
  elseif kind=='posted' and e.itemId then
    if a.relist then a.relist[e.itemId]=nil end
  elseif kind=='auction_expired' and e.itemId then
    a.relist=a.relist or {};a.relist[e.itemId]=time()
    local f=ForeverMarketTradingFund()
    local match
    for _,lot in ipairs(f.lots) do
      if lot.itemID==e.itemId and lot.n>0 and (not lot.sold or (lot.unpaid or lot.posted)<lot.posted) and (lot.unpaid or lot.posted)==e.quantity and lot.basis then
        if match then return end
        match=lot
      end
    end
    if match then
      local r=ledger(e.name);r.expiredDeposits=(r.expiredDeposits or 0)+match.deposit
      restoreLot(match,r)
    end
  end
end
function M.expiryWarning(name)
  local r=M.marketOutcomes(name)
  if not r or r.returns==0 then return end
  local history=prefs().ledger[name]
  local lost=history and history.expiredDeposits
  return ('Expired %dx in 14 days'):format(r.returns),lost and ('Confirmed fund deposits lost (lifetime): '..ForeverMarketCoins(lost)) or 'Lost deposit amount unknown'
end
function M.valueLines(tip,id,link)
  local name=C_Item.GetItemNameByID(id)
  if name then
    tip:AddLine(M.saleLabel(name),.75,.8,.85)
    local evidence=M.marketOutcomes(name)
    if evidence and evidence.lastUnit then
      tip:AddDoubleLine('Last paid sale / unit',ForeverMarketCoins(evidence.lastUnit))
      tip:AddLine(date('%b %d %H:%M',evidence.lastPaid)..' / this character, by item name',.75,.8,.85)
    else tip:AddLine('No paid sale recorded for this character in 14 days.',.75,.8,.85) end
    if evidence and evidence.paidUnits then
      tip:AddDoubleLine('Your sale price / unit',ForeverMarketCoins(math.floor(evidence.gross/evidence.paidUnits)))
      tip:AddLine(('%d paid invoices / %d units / latest %s (item name)'):format(evidence.receipts,evidence.paidUnits,date('%b %d',evidence.lastPaid)),.75,.8,.85)
    end
  end
  local byItem=M.account().styleStats and M.account().styleStats[id]
  for _,style in ipairs({'Match','Undercut'}) do
    local stat=byItem and byItem[style]
    if stat then tip:AddLine(('%s: %d/%d posts saw a sale%s'):format(style,stat.sold,stat.posts,stat.sold>0 and (' / mean '..math.floor(stat.seconds/stat.sold/60)..' min') or '')) end
  end
  local best,recipe
  for _,r in pairs(M.account().recipes) do
    if (r.materials[id] or r.choices) then
      local inputs=M.inputs(r,1)
      if inputs and inputs[id] then
        local e=M.estimate(r,1)
        if not recipe or (e and (not best or e.extra>best)) then recipe=r.name;best=e and e.extra end
      end
    end
  end
  if recipe then tip:AddDoubleLine('Known craft: '..recipe,best and (ForeverMarketCoins(best)..' gain / craft') or 'Price unknown') end
  local sample=prefs().samples[id]
  if sample then
    local total=0
    for material,count in pairs(sample.outputs) do
      local post=M.prices(material)
      if not post then tip:AddLine('Disenchant: material price unknown');return end
      total=total+count*post
    end
    tip:AddDoubleLine('Disenchant average ('..sample.count..' observed)',ForeverMarketCoins(ForeverMarketSaleNet(math.floor(total/sample.count))))
  end
end

-- Match a successful disenchant to its loot and a single consumed item in the bags.
local craft,lootFrame=nil,CreateFrame('Frame')
local function bagTotals()
  local t={}
  for bag=0,(NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
    for slot=1,C_Container.GetContainerNumSlots(bag) do
      local i=C_Container.GetContainerItemInfo(bag,slot)
      if i then t[i.itemID]=(t[i.itemID] or 0)+(i.stackCount or 1) end
    end
  end
  return t
end
for _,ev in ipairs({'UNIT_SPELLCAST_START','UNIT_SPELLCAST_SUCCEEDED','LOOT_OPENED','LOOT_CLOSED','BAG_UPDATE_DELAYED'}) do lootFrame:RegisterEvent(ev) end
lootFrame:SetScript('OnEvent',function(_,ev,unit,cast,spell)
  if craft and GetTime()-craft.at>30 then craft=nil end
  if ev=='UNIT_SPELLCAST_START' and unit=='player' then
    craft=spell==13262 and {at=GetTime(),cast=cast,bags=bagTotals()} or nil
  elseif craft and ev=='UNIT_SPELLCAST_SUCCEEDED' and unit=='player' and cast==craft.cast then craft.ok=true
  elseif craft and ev=='LOOT_OPENED' then
    if craft.outputs then craft=nil;return end
    craft.outputs={}
    for i=1,GetNumLootItems() do
      local link=GetLootSlotLink(i);local id=link and itemID(link)
      local _,_,n=GetLootSlotInfo(i)
      if not id or not n or n<1 then craft=nil;return end
      craft.outputs[id]=(craft.outputs[id] or 0)+n
    end
  elseif craft and ev=='LOOT_CLOSED' then craft.closed=true end
  if not craft or not craft.ok or not craft.closed or not next(craft.outputs or {}) then return end
  local after=bagTotals();local id
  for key,n in pairs(craft.bags) do
    local lost=n-(after[key] or 0)
    if lost>0 then if lost~=1 or id then craft=nil;return end;id=key end
  end
  if not id then return end
  for key,n in pairs(craft.outputs) do if (after[key] or 0)-(craft.bags[key] or 0)~=n then return end end
  local samples=prefs().samples
  local r=samples[id] or {count=0,outputs={}};samples[id]=r;r.count=r.count+1
  for key,n in pairs(craft.outputs) do r.outputs[key]=(r.outputs[key] or 0)+n end
  craft=nil
end)

local panel,title,status,entry,target,cap,listName,pageLabel
local controls,rows,mode,page,confirm={}, {},'Auctions',1
local money=ForeverMarketCoins
local function label(p,x,y,w)
  local f=p:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
  f:SetPoint('TOPLEFT',x,y);f:SetWidth(w);f:SetJustifyH('LEFT');f:SetWordWrap(false);return f
end
local function button(p,x,y,w,caption,fn)
  local b=CreateFrame('Button',nil,p,'UIPanelButtonTemplate')
  b:SetPoint('TOPLEFT',x,y);b:SetSize(w,22);b:SetText(caption);b:SetScript('OnClick',fn);return b
end
local function field(x,y,w)
  local e=CreateFrame('EditBox',nil,panel,'InputBoxTemplate');e:SetPoint('TOPLEFT',x,y);e:SetSize(w,21);e:SetAutoFocus(false)
  e:SetScript('OnEnterPressed',function(self)self:ClearFocus() end);return e
end
local function owner(id)
  for i=1,api.GetNumOwnedAuctions() do
    local r=api.GetOwnedAuctionInfo(i)
    if r and r.auctionID==id then return r end
  end
end
local function ownedDetail(r)
  if r.status~=0 then return 'Sold / awaiting settlement' end
  if not (r.buyoutAmount or r.unitPrice) or not r.quantity or r.quantity<1 then return 'Bid auction' end
  local unit=math.ceil(M.listingGross(r)/r.quantity)
  local k=r.itemKey
  local info=k and api.GetItemKeyInfo(k)
  local variant=k and not (info and info.isCommodity) and ForeverMarketVariant(k,r.itemLink)
  local q=variant and M.quotes()[variant]
  local snap=ForeverMarketReadySnapshot and ForeverMarketReadySnapshot()
  local b=info and info.isCommodity and snap and snap.books[k.itemID]
  local bulk=q and time()-q.at<=60 and q.price or b and b.floorPrice
  if not bulk then return money(unit)..' each / market check needed' end
  if unit>bulk then
    local sale=M.account().sales[r.auctionID]
    local dep=sale and sale.deposit
    local fee=api.GetCancelCost and api.GetCancelCost(r.auctionID)
    local cheaper=0;for _,tier in ipairs(b and b.levels or {}) do if tier[1]<unit then cheaper=cheaper+tier[2] end end
    local outcomes=M.marketOutcomes(nameOf(k.itemID))
    local pace=outcomes and outcomes.paidUnits
    if pace and cheaper>0 and cheaper<=math.max(1,pace/14) then return 'Leave posted / '..cheaper..' cheaper, within a day of your paid volume' end
    if not dep or not fee then return 'Review for relist / cancellation cost unknown' end
    local net=ForeverMarketSaleNet(bulk*r.quantity)-dep-fee
    local vendor=select(11,C_Item.GetItemInfo(k.itemID))
    if vendor and net<=vendor*r.quantity then return 'Leave posted / relisting nets vendor value or less' end
    return 'Review for relist / '..(cheaper>0 and (cheaper..' cheaper / ') or '')..'forfeit '..money(dep+fee)
  end
  if b and b.low and b.low<unit then return 'Leave posted / '..(b.lowQty or '?')..' at '..money(b.low) end
  return 'Competitive / bulk '..money(bulk)
end
local function cancel(r)
  if M.pendingCancel and GetTime()-M.pendingCancel.at<12 then return "Waiting for the previous cancellation." end
  local live=owner(r.auctionID)
  if not live or live.status~=0 or live.quantity~=r.quantity or live.buyoutAmount~=r.buyoutAmount or not api.CanCancelAuction or not api.CanCancelAuction(r.auctionID) then
    confirm=nil;return 'Listing changed or cannot be cancelled.'
  end
  local fee=api.GetCancelCost and api.GetCancelCost(r.auctionID)
  if fee==nil then return 'Review the cancellation cost in Blizzard Auctions.' end
  if not confirm or confirm.id~=r.auctionID or confirm.fee~=fee or GetTime()>confirm.at+10 then
    confirm={id=r.auctionID,at=GetTime(),fee=fee}
    local sale=M.account().sales[r.auctionID];local deposit=sale and sale.deposit
    return 'Confirm cancellation / deposit '..(deposit and money(deposit) or 'unknown')..' / fee '..money(fee)..'.'
  end
  confirm=nil
  if fee>GetMoney() then return 'Not enough gold for cancellation.' end
  M.pendingCancel={id=r.auctionID,item=r.itemKey.itemID,at=GetTime(),fee=fee}
  local ok=pcall(api.CancelAuction,r.auctionID)
  if not ok then M.pendingCancel=nil;return 'Open Blizzard Auctions to cancel this listing.' end
  return 'Cancellation requested. Collect the returned item from your mail.'
end
local undercutsOnly=false
local ledgerItem,ledgerEvents,ledgerLength,flipIndex
local fundSection='cash'
function M.fundSummary(detail)
  local f=ForeverMarketTradingFund()
  local s={cash=ForeverMarketSpendable(),inventory=0,pending=0,profit=0,deposit=0,soldBasis=0,other=0,rows={}}
  local function row(section,title,amount,description)
    if detail==section then
      local r={name=title,detail=money(amount)..(description and (' / '..description) or '')}
      if section=='inventory' or section=='pending' then
        r.action='History';r.click=function()mode='Ledger';ledgerItem=title;ledgerEvents=nil;page=1 end
      end
      s.rows[#s.rows+1]=r
    end
  end
  row('cash','Allocated capital',f.seed)
  row('cash','Cash balance',f.cash)
  row('cash','Unavailable for buying',f.cash-s.cash,'reservations or wallet limit')
  row('cash','Opening journal balance',f.cashOpening or f.cash)
  if detail=='cash' then for i=#(f.cashLog or {}),1,-1 do
    local e=f.cashLog[i];row('cash',e.kind,e.delta,(e.name or '')..' '..date('%b %d %H:%M',e.at))
  end end
  for id,h in pairs(f.held or {}) do if h.n>0 then
    s.inventory=s.inventory+(h.cost or 0)
    if detail=='inventory' then row(detail,nameOf(h.itemID or tonumber(id) or 0),h.cost or 0,h.n..' held, including mail') end
  end end
  for _,lot in ipairs(f.lots or {}) do if lot.n>0 then
    local cost=lot.basis or 0;s.deposit=s.deposit+(lot.deposit or 0)
    if lot.sold then
      local due=ForeverMarketSaleNet(lot.price*lot.n)+(lot.deposit or 0)
      s.pending=s.pending+due;s.soldBasis=s.soldBasis+cost
      row('pending',lot.name or 'Sold item',due,lot.n..' units / awaiting collection')
    else s.inventory=s.inventory+cost;row('inventory',lot.name or 'Listed item',cost,lot.n..' listed') end
  end end
  for id,mat in pairs(M.account().materialCosts or {}) do if mat.n>0 then
    s.inventory=s.inventory+(mat.cost or 0)
    if detail=='inventory' then row(detail,nameOf(id),mat.cost or 0,'craft materials') end
  end end
  for name,r in pairs(prefs().ledger) do
    local value=(r.earned or 0)-(r.loss or 0);s.profit=s.profit+value
    local outside=math.max(0,(r.proceeds or 0)-(r.matchedCash or 0));s.other=s.other+outside
    if detail=='profit' and (value~=0 or outside>0) then
      s.rows[#s.rows+1]={name=name,detail='Realized '..money(value)..' / unassigned receipts '..money(outside),action='History',
        click=function()mode='Ledger';ledgerItem=name;ledgerEvents=nil;page=1 end}
    end
  end
  s.difference=f.cash+s.inventory+s.soldBasis+s.deposit-f.seed-s.profit
  row('cash','Deposits outstanding',s.deposit)
  row('cash','Sold stock at cost',s.soldBasis,'until proceeds are collected')
  row('cash','Reconciliation difference',s.difference,'cash + open costs + deposits less capital and realized profit')
  row('profit','Receipts outside matched fund sales',s.other)
  if detail=='pending' and #s.rows==0 then s.rows[1]={name='No pending fund sales',detail='Confirmed fund sales appear here until collection.'} end
  if detail=='inventory' and #s.rows==0 then s.rows[1]={name='No fund stock',detail='Confirmed purchases and open listings appear here.'} end
  return s
end
local function entries()
  local items={}
  local function add(name,detail,action,click,key)
    items[#items+1]={name=name,detail=detail,action=action,click=click,key=key or name}
  end
  if mode=='Fund' then return M.fundSummary(fundSection).rows
  elseif mode=='Auctions' then
    local current,queue=M.cancelQueueCurrent()
    if queue then
      if current then add(nameOf(current.key.itemID)..' x '..current.qty,'Your listing / '..money(current.gross)..' total') end
      add('Queue progress',queue.removed..' removed / '..queue.skipped..' skipped')
      return items
    end
    for i=1,api.GetNumOwnedAuctions() do
      local r=api.GetOwnedAuctionInfo(i)
      if r and r.itemKey and (not undercutsOnly or ownedDetail(r):match("^Review for relist")) then
        add(nameOf(r.itemKey.itemID)..' x '..r.quantity,ownedDetail(r),r.status==0 and (confirm and confirm.id==r.auctionID and 'Confirm' or 'Cancel'),function()return cancel(r)end,r.auctionID)
      end
    end
    for id in pairs(not undercutsOnly and M.account().relist or {}) do add(nameOf(id),'Returned / collect mail, then open Market Sell') end
  elseif mode=='Dip tests' then
    for _,trial in ipairs(ForeverMarketPaperResults()) do
      local p=trial.paper
      add(nameOf(trial.id),('%d hit / %d missed / %d incomplete%s'):format(p.hits,p.misses,p.gaps,p.at and not p.hit and ' / watching' or ''))
    end
    if #items==0 then add('No trials yet','Run Invest. Each displayed dip starts a three-day price test.') end
    return items
  elseif mode=='Flips' then
    local flips=ForeverMarketTradingFund().flips or {}
    local r=flips[flipIndex]
    if r then
      local basis=math.floor(r.cost*r.sold/r.n)
      add('Purchased',date('%b %d %H:%M',r.at)..' / '..r.n..' units / '..money(r.cost))
      add('Forecast at purchase',money(r.expected)..' profit for the whole purchase')
      if r.sold>0 then add('Paid units vs forecast',money(r.net-basis-r.lost)..' realized / '..money(math.floor(r.expected*r.sold/r.n))..' forecast') end
      add('Sold / paid units',r.sold..' of '..r.n..' / '..money(r.net)..' after AH fees')
      add('Realized profit',money(r.net-basis-r.lost)..' / lost deposits and fees '..money(r.lost))
      add('Open stock',(r.n-r.sold-r.listed)..' unlisted / '..r.listed..' listed or awaiting payout')
      add('Open purchase cost',money(r.cost-basis))
      add('Gold collected',money(r.wallet or 0)..' including returned deposits')
      if r.lastPaid then add('Latest payout',date('%b %d %H:%M',r.lastPaid)..' / '..math.floor((r.lastPaid-r.at)/60)..' min since purchase') end
    else
      local spent,wallet,lost,basis,net=0,0,0,0,0
      for i=#flips,1,-1 do
        local id=i;local flip=flips[id]
        spent=spent+flip.cost;wallet=wallet+(flip.wallet or 0);net=net+flip.net;lost=lost+flip.lost;basis=basis+math.floor(flip.cost*flip.sold/flip.n)
        add(flip.name,(flip.invest and 'Invest' or 'Flip')..' / '..flip.sold..' of '..flip.n..' paid / '..date('%b %d %H:%M',flip.at),'Details',function()flipIndex=id;page=1 end)
      end
      table.insert(items,1,{name='Fund performance',detail='Realized '..money(net-basis-lost)..' / open cost '..money(spent-basis)})
      table.insert(items,2,{name='Cash flow',detail='Spent '..money(spent)..' / collected '..money(wallet)})
    end
    return items
  elseif mode=='Ledger' and ledgerItem then
    local db=ForeverMarketActivity
    local events=db and db.events or {}
    if not ledgerEvents or ledgerLength~=#events then
      ledgerEvents={};ledgerLength=#events
      for i=#events,1,-1 do
        local e=events[i]
        local sale=e.auctionId and M.account().sales[e.auctionId]
        if e.character==UnitName('player') and (ForeverMarketEventRealm and ForeverMarketEventRealm(e) or e.realm)==ForeverMarketVenueRealm() and e.faction==UnitFactionGroup('player') and
           (e.name==ledgerItem or sale and sale.name==ledgerItem) then
          ledgerEvents[#ledgerEvents+1]={name=date('%b %d %H:%M',e.at)..'  '..e.kind:gsub('_',' '),
            detail=(e.quantity and 'x '..e.quantity..'   ' or '')..(e.amount and money(e.amount) or e.total and money(e.total) or '')..(e.deposit and '   deposit '..money(e.deposit) or ''),key=i}
        end
      end
    end
    return ledgerEvents
  elseif mode=='Ledger' then
    for name,r in pairs(prefs().ledger) do
      local detail='Bought '..r.bought..' / sold '..r.sold..' / open '..math.max(0,(r.tracked or 0)-r.matched)..' / realized '..money(r.earned-r.loss)
      add(name,detail,'History',function()ledgerItem=name;ledgerEvents=nil;page=1;return 'Spent '..money(r.paid)..' / collected '..money(r.proceeds)..' / unmatched receipts '..money(math.max(0,r.proceeds-(r.matchedCash or 0)))..' / lost deposits '..money(r.loss)..' / '..M.saleLabel(name) end)
    end
  elseif mode=='Shopping' then
    for id,r in pairs(M.restockList()) do
      add(nameOf(id),'Keep '..r.keep..' / missing '..M.missing(id,r.keep)..' / '..(r.cap>0 and money(r.cap)..' max each' or 'Market price'),'Remove',function()M.restockList()[id]=nil;M.invalidate();return 'Removed from list.' end)
    end
  else
    for key,v in pairs(prefs().rules) do
      local class=tostring(key):match('^class(%d+)$')
      add(class and (GetItemClassInfo and GetItemClassInfo(tonumber(class)) or 'Class '..class) or nameOf(key),v,'Remove',function()prefs().rules[key]=nil;return 'Rule removed.' end)
    end
    for id,limit in pairs(prefs().alerts) do add(nameOf(id),'Alert at '..money(limit)..' or lower','Remove',function()prefs().alerts[id]=nil;alerted[id]=nil;return 'Alert removed.' end) end
  end
  table.sort(items,function(a,b)if a.name==b.name then return tostring(a.key)<tostring(b.key) end return a.name<b.name end)
  return items
end
local function render()
  if not panel or not panel:IsVisible() then return end
  local list=entries()
  local pages=math.max(1,math.ceil(#list/#rows));page=math.min(page,pages);pageLabel:SetText(page..' / '..pages)
  title:SetText(mode=='Fund' and ('Trading fund / '..fundSection) or mode=='Dip tests' and 'Forward tests / did a later bulk quote reach the original exit?' or mode=='Flips' and (flipIndex and 'Purchase details / click Fund flips to return' or 'Confirmed Market Buy purchases since 0.12.0') or mode=='Shopping' and ('Active shopping list: '..prefs().active) or mode=='Rules' and 'Item rules override category rules.' or mode=='Ledger' and ledgerItem and (ledgerItem..' / click Ledger to return') or mode=='Ledger' and 'Realized profit uses fund purchases matched to collected sales.' or ('My auctions / '..ForeverMarketVenueRealm()))
  for i,row in ipairs(rows) do
    local r=list[(page-1)*#rows+i];row.data=r
    ForeverMarketSetItemText(row.name,r and r.name or '');ForeverMarketSetItemText(row.detail,r and r.detail or '')
    row.action:SetShown(r and r.action~=nil or false);row.action:SetText(r and r.action or '')
  end
  for _,c in ipairs(controls) do c.frame:SetShown(c.mode==mode) end
end
local function refresh()
  if mode=='Auctions' then
    if api.QueryOwnedAuctions then api.QueryOwnedAuctions({}) end
    if ForeverMarketSnapshot then ForeverMarketSnapshot() end
  end
  render()
end
local function addRule(kind)
  local id=itemID(entry:GetText())
  if not id then return 'Enter an item ID or paste an item link.' end
  local key=id
  if M.classScope then
    local class=select(12,C_Item.GetItemInfo(id));if not class then return 'Item class still loading.' end
    key='class'..class
  end
  prefs().rules[key]=kind;return 'Saved '..kind..' posting rule.'
end
local function create()
  if panel then return end
  panel=CreateFrame('Frame',nil,AuctionHouseFrame,'BackdropTemplate');panel:SetPoint('TOPLEFT',14,-58);panel:SetPoint('BOTTOMRIGHT',-12,39)
  panel:SetFrameLevel(AuctionHouseFrame:GetFrameLevel()+40);panel:EnableMouse(true)
  panel:SetBackdrop({bgFile='Interface\\DialogFrame\\UI-DialogBox-Background-Dark',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=12});panel:SetBackdropColor(.12,.10,.08,1);panel:Hide()
  ForeverMarketPanelArt(panel)
  for i,m in ipairs({'Auctions','Shopping','Ledger','Rules'}) do button(panel,8+(i-1)*94,-6,91,m,function()mode=m;page=1;confirm=nil;ledgerItem=nil;status:SetText('');refresh() end) end
  button(panel,388,-6,65,'Refresh',refresh);button(panel,455,-6,76,'Browse',function()panel:Hide();M.openDesk()end);button(panel,532,-6,78,'Close',function()panel:Hide()end)
  button(panel,611,-6,58,'Home',function()panel:Hide();M.openTools('Home')end)
  title=label(panel,12,-36,655);status=label(panel,12,-124,650)
  entry=field(15,-74,166);target=field(190,-74,62);cap=field(266,-74,94);listName=field(375,-74,115)
  local function control(m,f) controls[#controls+1]={mode=m,frame=f};return f end
  local function showFlips() mode='Flips';flipIndex=nil;page=1;status:SetText('');render() end
  for _,m in ipairs({'Ledger','Flips','Dip tests'}) do
    control(m,button(panel,314,-72,110,'Results',function()M.openTools('Results')end))
    control(m,button(panel,12,-72,135,'Fund flips',showFlips))
    control(m,button(panel,152,-72,150,'Investment tests',function()mode='Dip tests';page=1;status:SetText('');render() end))
  end
  local function command(m,x,w,text,fn)
    control(m,button(panel,x,-98,w,text,function()local result=fn();if result then status:SetText(result) end;render()end))
  end
  local displayedCancel,pressedCancel
  command('Auctions',12,140,'Scan cancels',function()return M.startCancelQueue() end)
  local cancelNext=control('Auctions',button(panel,159,-98,138,'Cancel shown',function()
    local why=M.cancelQueueOne(pressedCancel or displayedCancel)
    pressedCancel=nil
    if why then status:SetText(why) end
  end))
  cancelNext:SetScript('OnMouseDown',function()pressedCancel=displayedCancel end)
  command('Auctions',304,100,'Stop queue',function()M.stopCancelQueue();return 'Queue stopped.' end)
  command('Shopping',8,90,'Save item',function()
    local id=itemID(entry:GetText());local n=whole(target:GetText(),9999);local limit=whole(cap:GetText(),9999999999)
    if not id or not n or n<1 or not limit then return 'Enter item, quantity (1–9999), and maximum copper per item (0 for market).' end
    M.restockList()[id]={keep=n,cap=limit};M.invalidate();return 'Restock target saved.'
  end)
  command('Shopping',101,97,'Use list',function()
    local name=listName:GetText():match('^%s*(.-)%s*$')
    if name=='' or #name>48 then return 'Enter a list name (1–48 characters).' end
    local p=prefs();p.lists[name]=p.lists[name] or {};p.active=name;M.invalidate();return 'List selected.'
  end)
  command('Shopping',201,90,'Copy list',function()entry:SetText(M.exportList());entry:SetFocus();entry:HighlightText();return 'Copy the selected list text.' end)
  command('Shopping',294,90,'Import',function()return M.importList(entry:GetText()) and 'Imported into active list.' or 'Invalid shared list.' end)
  command('Shopping',388,130,'Buy missing',function()panel:Hide();if M.openTools then M.openTools('Basket') else M.openMaterials() end end)
  command('Rules',8,120,'Sell quickly',function()return addRule('Quick')end)
  command('Rules',130,122,'Protect margin',function()return addRule('Margin')end)
  command('Rules',254,123,'Keep for craft',function()return addRule('Keep')end)
  command('Rules',379,105,'Price alert',function()
    local id=itemID(entry:GetText());local n=whole(cap:GetText(),9999999999)
    if not id or not n or n==0 then return 'Enter an item and a positive alert price in copper.' end
    prefs().alerts[id]=n;alerted[id]=nil;return 'Alert saved for the next scan.'
  end)
  control('Auctions',button(panel,12,-70,185,'Set auctioneer market',function()
    local npc=auctioneer();if not npc then status:SetText('Auctioneer identity unavailable.');return end
    local p=prefs();p.venue=p.venue or {};local current=p.venue[npc]
    if current==nil then current=neutralNPC[npc] end
    p.venue[npc]=not current
    status:SetText('Close and reopen AH to use '..(p.venue[npc] and 'separate neutral' or 'faction')..' prices here.')
  end))
  control('Auctions',button(panel,214,-70,155,'Review undercuts',function(self)undercutsOnly=not undercutsOnly;self:SetText(undercutsOnly and 'Show all auctions' or 'Review undercuts');page=1;refresh()end))
  local sync=control('Auctions',button(panel,378,-70,194,'Live desktop sync',function(self)
    self:SetText('Live desktop sync: '..(ForeverMarketLiveSync(not ForeverMarketLiveSync()) and 'on' or 'off'))
  end))
  control('Rules',button(panel,495,-98,108,'Scope: item',function(self)M.classScope=not M.classScope;self:SetText(M.classScope and 'Scope: category' or 'Scope: item')end))
  local labels={label(panel,15,-56,165),label(panel,190,-56,74),label(panel,266,-56,110),label(panel,375,-56,120)}
  for i,t in ipairs({'Item ID / link / list','Keep qty','Max copper each','List name'}) do labels[i]:SetText(t) end
  cap:SetText('0');target:SetText('1');listName:SetText(prefs().active)
  panel.inputs=function()
    if ForeverMarketLiveSync then sync:SetText('Live desktop sync: '..(ForeverMarketDB.liveDesktopSync and 'on' or 'off')) end
    local show=mode=='Shopping' or mode=='Rules'
    entry:SetShown(show);cap:SetShown(show);labels[1]:SetShown(show);labels[3]:SetShown(show)
    target:SetShown(mode=='Shopping');listName:SetShown(mode=='Shopping');labels[2]:SetShown(mode=='Shopping');labels[4]:SetShown(mode=='Shopping')
  end
  for i=1,8 do
    local y=-148-(i-1)*24
    ForeverMarketRowArt(panel,y+5,635,i)
    local r={name=label(panel,12,y,174),detail=label(panel,190,y,365)}
    ForeverMarketTextHint(panel,r.name);ForeverMarketTextHint(panel,r.detail)
    r.action=button(panel,558,y+4,74,'',function()if r.data and r.data.click then status:SetText(r.data.click() or '');render() end end);rows[i]=r
  end
  pageLabel=label(panel,96,-346,70)
  button(panel,10,-341,72,'Previous',function()page=math.max(1,page-1);render()end)
  button(panel,162,-341,72,'Next',function()page=page+1;render()end)
  local elapsed=0
  panel:SetScript('OnUpdate',function(_,dt)elapsed=elapsed+dt;if elapsed>.5 then elapsed=0;panel.inputs();render()
    if mode=='Auctions' then
      local why=M.cancelQueueTick();local line=M.cancelQueueText()
      if why or line then status:SetText(why or line) end
      displayedCancel=M.cancelQueueReady();cancelNext:SetEnabled(displayedCancel~=nil and displayedCancel~=false)
    else M.stopCancelQueue() end end end)
  panel:SetScript('OnHide',function()confirm=nil;M.stopCancelQueue() end)
  hooksecurefunc(AuctionHouseFrame,'SetDisplayMode',function()panel:Hide()end)
end
function M.openFundSection(section)
  fundSection=section;mode='Fund';page=1;M.openManager()
end
function M.openAuctionReview()
  mode='Auctions';page=1;undercutsOnly=false;M.openManager()
end
function M.openManager()
  create();panel:Show();panel.inputs();refresh()
end
local events=CreateFrame('Frame')
events:RegisterEvent('AUCTION_HOUSE_SHOW');events:RegisterEvent('OWNED_AUCTIONS_UPDATED');events:RegisterEvent('AUCTION_HOUSE_CLOSED')
events:SetScript('OnEvent',function(_,ev)
  if ev=='AUCTION_HOUSE_SHOW' then
    local npc=auctioneer()
    if npc then
      local overrides=prefs().venue or {}
      local neutral=overrides[npc]
      if neutral==nil then neutral=neutralNPC[npc] end
      ForeverMarketSetVenue(neutral==true)
    else ForeverMarketSetVenue(false) end
    local parent=AuctionHouseFrame and AuctionHouseFrame.AuctionsFrame
    if parent and not parent.foreverManager then
      parent.foreverManager=button(parent,225,-4,110,'Manage auctions',M.openManager)
    end
  elseif ev=='AUCTION_HOUSE_CLOSED' then if panel then panel:Hide() end
  else render() end
end)
