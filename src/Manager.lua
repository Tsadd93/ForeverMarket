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
  print('Forever Market: '..nameOf(id)..' observed at '..ForeverMarketCoins(price)..'.')
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
function M.settleLot(lot,e,n,basis)
  local r=ledger(e.name)
  r.matched=r.matched+n
  r.matchedCash=(r.matchedCash or 0)+math.floor(e.amount*n/e.quantity)
  r.earned=r.earned+math.floor((e.amount-e.deposit)*n/e.quantity)-basis
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
local turnover={}
function M.salesWeight(name)
  local events=ForeverMarketActivity and ForeverMarketActivity.events
  if not events then return 1 end
  local day=math.floor(time()/86400);local scope=M.scope()
  if turnover.day~=day or turnover.scope~=scope or turnover.events~=events or turnover.index>#events then
    turnover={day=day,scope=scope,events=events,index=0,byName={},seen={}}
  end
  for i=turnover.index+1,#events do
    local e=events[i]
    if e.at>=(day-13)*86400 and e.name and (e.realm or '')..'|'..(e.faction or '')==scope then
      local sold=e.kind=='sale_notice' and e.auctionId and not turnover.seen[e.auctionId]
      if sold or e.kind=='auction_expired' then
        local r=turnover.byName[e.name] or {sales=0,returns=0};turnover.byName[e.name]=r
        if sold then turnover.seen[e.auctionId]=true;r.sales=r.sales+1 else r.returns=r.returns+1 end
      end
    end
  end
  turnover.index=#events
  local r=turnover.byName[name]
  if not r then return 1 end
  return math.max(.5,math.min(1.5,2*(r.sales+2)/(r.sales+r.returns+4)))
end
local function restoreLot(lot,r,fee)
  local h=ForeverMarketTradingFund().held[lot.holding]
  if not h then return end
  if lot.target and (lot.invested or 0)>0 then h.target=math.max(h.target or 0,lot.target);h.invested=(h.invested or 0)+math.min(lot.n,lot.invested) end
  h.n=h.n+lot.n;h.cost=(h.cost or 0)+lot.basis
  r.loss=r.loss+lot.deposit+(fee or 0)
  lot.n=0;lot.basis=0;lot.deposit=0
end
function M.recordMarket(kind,e)
  if kind=='cancel_confirmed' then
    local c=M.pendingCancel;M.pendingCancel=nil
    if c and GetTime()-c.at<10 then
      local a=M.account();a.relist=a.relist or {};a.relist[c.item]=time()
      for _,lot in ipairs(ForeverMarketTradingFund().lots) do
        if lot.auctionId==c.id and lot.n>0 and lot.basis then
          local fee=math.ceil(c.fee*lot.n/(lot.posted or lot.n))
          local f=ForeverMarketTradingFund();f.cash=f.cash-fee
          restoreLot(lot,ledger(lot.name),fee);break
        end
      end
    end
    return
  end
  if not e.name or not e.quantity or e.quantity<1 then return end
  local a=M.account()
  if kind=='purchase' and e.total then
    local r=ledger(e.name);r.bought=r.bought+e.quantity;r.paid=r.paid+e.total
  elseif kind=='proceeds_collected' and e.invoiceType=='seller' and e.amount then
    local r=ledger(e.name);r.sold=r.sold+e.quantity;r.proceeds=r.proceeds+e.amount
    local days=prefs().days;days[e.name]=days[e.name] or {}
    local day=math.floor(e.at/86400)
    local bucket=days[e.name][day] or {n=0,count=0};days[e.name][day]=bucket
    bucket.n=bucket.n+e.quantity;bucket.count=bucket.count+1
    for d in pairs(days[e.name]) do if d<=day-7 then days[e.name][d]=nil end end
  elseif kind=='posted' and e.itemId and a.relist then a.relist[e.itemId]=nil
  elseif kind=='auction_expired' and e.itemId then
    a.relist=a.relist or {};a.relist[e.itemId]=time()
    local f=ForeverMarketTradingFund()
    local match
    for _,lot in ipairs(f.lots) do
      if lot.itemID==e.itemId and lot.n>0 and not lot.sold and lot.posted==e.quantity and lot.basis then
        if match then return end
        match=lot
      end
    end
    if match then restoreLot(match,ledger(e.name)) end
  end
end
function M.valueLines(tip,id,link)
  local name=C_Item.GetItemNameByID(id)
  if name then tip:AddLine(M.saleLabel(name),.75,.8,.85) end
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
  if unit>bulk then local s=M.account().sales[r.auctionID];return 'Above bulk by '..money(unit-bulk)..' each / deposit '..(s and s.deposit and money(s.deposit) or 'unknown') end
  if b and b.low and b.low<unit then return 'Keep / thin low offer at '..money(b.low) end
  return 'Competitive / bulk '..money(bulk)
end
local function cancel(r)
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
local ledgerItem,ledgerEvents,ledgerLength
local function entries()
  local items={}
  local function add(name,detail,action,click,key)
    items[#items+1]={name=name,detail=detail,action=action,click=click,key=key or name}
  end
  if mode=='Auctions' then
    for i=1,api.GetNumOwnedAuctions() do
      local r=api.GetOwnedAuctionInfo(i)
      if r and r.itemKey and (not undercutsOnly or ownedDetail(r):match("^Above bulk")) then
        add(nameOf(r.itemKey.itemID)..' x '..r.quantity,ownedDetail(r),r.status==0 and (confirm and confirm.id==r.auctionID and 'Confirm' or 'Cancel'),function()return cancel(r)end,r.auctionID)
      end
    end
    for id in pairs(not undercutsOnly and M.account().relist or {}) do add(nameOf(id),'Returned / collect mail, then open Market Sell') end
  elseif mode=='Ledger' and ledgerItem then
    local db=ForeverMarketActivity
    local events=db and db.events or {}
    if not ledgerEvents or ledgerLength~=#events then
      ledgerEvents={};ledgerLength=#events
      for i=#events,1,-1 do
        local e=events[i]
        local sale=e.auctionId and M.account().sales[e.auctionId]
        if e.character==UnitName('player') and e.realm==ForeverMarketVenueRealm() and e.faction==UnitFactionGroup('player') and
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
  title:SetText(mode=='Shopping' and ('Active shopping list: '..prefs().active) or mode=='Rules' and 'Item rules override category rules.' or mode=='Ledger' and ledgerItem and (ledgerItem..' / click Ledger to return') or mode=='Ledger' and 'Realized profit uses fund purchases matched to collected sales.' or ('My auctions / '..ForeverMarketVenueRealm()))
  for i,row in ipairs(rows) do
    local r=list[(page-1)*#rows+i];row.data=r
    row.name:SetText(r and r.name or '');row.detail:SetText(r and r.detail or '')
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
  for i,m in ipairs({'Auctions','Shopping','Ledger','Rules'}) do button(panel,8+(i-1)*94,-6,91,m,function()mode=m;page=1;confirm=nil;ledgerItem=nil;status:SetText('');refresh() end) end
  button(panel,388,-6,65,'Refresh',refresh);button(panel,455,-6,76,'Browse',function()panel:Hide();M.openDesk()end);button(panel,532,-6,78,'Close',function()panel:Hide()end)
  title=label(panel,12,-36,655);status=label(panel,12,-124,650)
  entry=field(15,-74,166);target=field(190,-74,62);cap=field(266,-74,94);listName=field(375,-74,115)
  local function control(m,f) controls[#controls+1]={mode=m,frame=f};return f end
  local function command(m,x,w,text,fn)
    control(m,button(panel,x,-98,w,text,function()local result=fn();if result then status:SetText(result) end;render()end))
  end
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
  command('Shopping',388,130,'Buy missing',function()panel:Hide();M.openMaterials() end)
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
  local scope
  scope=control('Rules',button(panel,495,-98,108,'Scope: item',function(self)M.classScope=not M.classScope;self:SetText(M.classScope and 'Scope: category' or 'Scope: item')end))
  local labels={label(panel,15,-56,165),label(panel,190,-56,74),label(panel,266,-56,110),label(panel,375,-56,120)}
  for i,t in ipairs({'Item ID / link / list','Keep qty','Max copper each','List name'}) do labels[i]:SetText(t) end
  cap:SetText('0');target:SetText('1');listName:SetText(prefs().active)
  panel.inputs=function()
    local show=mode=='Shopping' or mode=='Rules'
    entry:SetShown(show);cap:SetShown(show);labels[1]:SetShown(show);labels[3]:SetShown(show)
    target:SetShown(mode=='Shopping');listName:SetShown(mode=='Shopping');labels[2]:SetShown(mode=='Shopping');labels[4]:SetShown(mode=='Shopping')
  end
  for i=1,8 do
    local y=-148-(i-1)*24
    local r={name=label(panel,12,y,174),detail=label(panel,190,y,365)}
    r.action=button(panel,558,y+4,74,'',function()if r.data and r.data.click then status:SetText(r.data.click() or '');render() end end);rows[i]=r
  end
  pageLabel=label(panel,96,-346,70)
  button(panel,10,-341,72,'Previous',function()page=math.max(1,page-1);render()end)
  button(panel,162,-341,72,'Next',function()page=page+1;render()end)
  local elapsed=0
  panel:SetScript('OnUpdate',function(_,dt)elapsed=elapsed+dt;if elapsed>.5 then elapsed=0;panel.inputs();render() end end)
  panel:SetScript('OnHide',function()confirm=nil end)
  hooksecurefunc(AuctionHouseFrame,'SetDisplayMode',function()panel:Hide()end)
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
      parent.foreverManager=button(parent,8,-5,115,'Manage auctions',M.openManager)
    end
  elseif ev=='AUCTION_HOUSE_CLOSED' then if panel then panel:Hide() end
  else render() end
end)
