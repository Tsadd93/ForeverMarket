local M=ForeverMarketTools
local f,field,second,hint,summary,message,pager
local rows,actions,chart={}, {}, {}
local mode,page,days='Basket',1,7
local preview,chain,lastQuote
local content={}
local function coins(n) return n and ForeverMarketCoins(math.floor(n)) or 'unknown' end
local function itemName(id) return C_Item.GetItemNameByID(id) or ('Item '..id) end
local function itemID(text)
  return tonumber(text:match('item:(%d+)') or text:match('^(%d+)$')) or tonumber((select(2,C_Item.GetItemInfo(text)) or ''):match('item:(%d+)'))
end
local function font(x,y,w)
  local t=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');t:SetPoint('TOPLEFT',x,y);t:SetWidth(w);t:SetJustifyH('LEFT');t:SetWordWrap(false);return t
end
local function button(x,y,w,text,fn)
  local b=CreateFrame('Button',nil,f,'UIPanelButtonTemplate');b:SetSize(w,22);b:SetPoint('TOPLEFT',x,y);b:SetText(text);b:SetScript('OnClick',fn);return b
end
local function input(x,y,w)
  local b=CreateFrame('EditBox',nil,f,'InputBoxTemplate');b:SetSize(w,22);b:SetPoint('TOPLEFT',x,y);b:SetAutoFocus(false);return b
end
local refresh
local function add(a,b,label,fn) content[#content+1]={a=a,b=b,label=label,fn=fn} end
local function action(i,label,fn)
  actions[i]:SetText(label);actions[i]:Show();actions[i]:SetScript('OnClick',function()
    local msg=fn();refresh();if msg then message:SetText(msg) end
  end)
end
local function plot(id)
  local series=M.historySeries(id,days);local peak,supply=1,1
  local first,last,sold
  for _,v in ipairs(series) do
    peak=math.max(peak,v.high or 0,v.ask or 0,v.sale or 0);supply=math.max(supply,v.units or 0)
    if v.ask then first=first or v;last=v end;sold=(sold or 0)+(v.sold or 0)
  end
  summary:SetText(itemName(id)..' / green: bulk ask range   gold: paid sales   blue: units (separate scale)')
  for i,v in ipairs(series) do
    local x=27+(i-1)*560/#series
    local function bar(index,value,cap,y,height,r,g,b,base)
      if not value then return end
      local t=chart[index]
      if not t then t=f:CreateTexture(nil,'ARTWORK');chart[index]=t end
      t:ClearAllPoints();t:SetPoint('TOPLEFT',f,'TOPLEFT',x,y-height*value/cap)
      t:SetSize(math.max(3,490/#series),math.max(3,height*(value-(base or value))/cap))
      t:SetColorTexture(r,g,b,1);t:Show()
    end
    bar(i,v.high or v.ask,peak,-292,64,.15,.8,.5,v.ask)
    bar(30+i,v.sale,peak,-292,64,1,.8,.1)
    bar(60+i,v.units,supply,-334,42,.3,.55,.9,0)
    add(date('%b %d',v.day*86400+43200),'Bulk '..coins(v.ask)..' / paid '..coins(v.sale)..' / '..(v.units or '?')..' listed')
  end
  local change=first and last and first~=last and first.ask>0 and math.floor((last.ask/first.ask-1)*100+.5)
  local depth=first and last and first.units and last.units and first.units>0 and last.units/first.units
  message:SetText((change and ('Price '..(change>=0 and '+' or '')..change..'% / ') or '')..(depth and ('supply '..string.format('%.1fx',depth)..' / ') or '')..(first and ('First ask '..coins(first.ask)..' / latest '..coins(last.ask)) or 'No bulk quotes observed')..' / '..(sold or 0)..' units with paid invoices.')
end
local function basket()
  hint:SetText('List name at left. At right, enter an item ID and keep quantity, e.g. 2589 20.')
  M.restockList();local m=M.account().manager
  action(1,'Use list',function()
    local list=field:GetText();if list=='' or #list>48 then return 'Enter a list name.' end
    m.lists[list]=m.lists[list] or {};m.active=list;M.cancelMaterial();M.invalidate();page=1
  end)
  action(2,'Save target',function()
    local id,n=second:GetText():match('^(%d+)%s+(%d+)$');id,n=tonumber(id),tonumber(n)
    if not id or id<1 or not n or n>9999 then return 'Enter item ID and quantity (0 removes).' end
    local list=M.restockList();list[id]=n>0 and {keep=n,cap=list[id] and list[id].cap or 0} or nil;M.cancelMaterial();M.invalidate()
  end)
  action(3,'Run shopping list',function() if M.runBasket then return M.runBasket() end end)
  action(4,'Vendor deals',function() if AuctionHouseFrame and AuctionHouseFrame:IsShown() then f:Hide();M.openVendorDeals() else return 'Open the auction house.' end end)
  local trip,total,unknown=M.shoppingTrip()
  summary:SetText(m.active..' / '..coins(total)..(unknown>0 and (' priced subtotal / '..unknown..' incomplete') or ' total for missing quantities'))
  for i,rule in ipairs(M.basketFilters and M.basketFilters() or {}) do
    add('Search: '..(rule.term~='' and rule.term or rule.category or 'All items'),'Target '..rule.units..' each / max '..(rule.max>0 and coins(rule.max) or 'any price'),'Remove',function()return M.removeBasketFilter(i)end)
  end
  for _,r in ipairs(trip) do
    local q=M.quote;local active=q and q.trip and q.id==r.id
    local displayed=active and q.total
    local detail=r.missing==0 and 'Covered' or ('Need '..r.missing..' / buy '..r.n..' / '..coins(displayed or r.subtotal))
    add(r.name,detail,r.n>0 and (displayed and 'Confirm' or active and 'Quoting' or 'Quote'),function()
      if displayed and (M.quote~=q or q.total~=displayed) then return 'Quote changed. Review it again.' end
      if not displayed and active then return 'Waiting for live quote.' end
      return M.buyTrip(r.id)
    end)
  end
end
local function imports()
  hint:SetText('Paste list or item group at left. Enter destination at right. Preview before applying.')
  action(1,'Preview',function()preview=M.importPreview(field:GetText(),second:GetText());preview.raw=field:GetText();page=1 end)
  action(2,'Apply',function()
    if not preview or preview.raw~=field:GetText() or preview.list~=second:GetText() then return 'Preview the current input first.' end
    local result=M.applyPreview(preview);preview=nil;return result
  end)
  action(3,'Read addon list',function()
    local raw,err=M.readAuctionatorList(second:GetText())
    if not raw then return err end
    field:SetText(raw);preview=M.importPreview(raw,second:GetText());preview.raw=raw;page=1
  end)
  if preview then
    summary:SetText(preview.kind..' into '..preview.list..' / '..#preview.skipped..' skipped')
    for _,r in ipairs(preview.filters or {}) do add('Search: '..r.term,'Qty '..r.units..' each / maximum '..coins(r.max)) end
    for id,n in pairs(preview.items) do add(itemName(id),'Keep '..n) end
    for _,s in ipairs(preview.skipped) do add('Skipped',s) end
  else summary:SetText('Supports item-only TSM groups and Auctionator exact item names or IDs.') end
end
local function logistics()
  hint:SetText('Destination character at left. Optional item ID and personal keep quantity at right.')
  action(1,'Set seller',function()return M.setRoute(nil,field:GetText(),0) end)
  action(2,'Assign item',function()
    local id,n=second:GetText():match('^(%d+)%s+(%d+)$')
    if not id then return 'Enter item ID and amount to keep.' end
    return M.setRoute(tonumber(id),field:GetText(),tonumber(n))
  end)
  action(3,'Clear route',function()return M.clearRoute(tonumber(second:GetText():match('^%d+'))) end)
  action(4,'Next character',function()
    local chars=M.destinations()
    for i,to in ipairs(chars) do if to==field:GetText() then field:SetText(chars[i%#chars+1]);return end end
    field:SetText(chars[1] or '')
  end)
  local seller=M.routeSeller()
  summary:SetText('Default seller: '..(seller or 'none')..' / attach at mailbox, inspect draft, then Send.')
  for _,r in ipairs(M.shipments()) do add(itemName(r.id),r.n..' to '..r.to,'Attach',function()return M.attachShipment(r) end) end
  if M.bankQueue then
    for _,r in ipairs(M.bankQueue()) do
      add(itemName(r.id),r.label..' / '..r.n,'Withdraw',function()return M.withdraw(r)end)
    end
  end
  for id,n in pairs(M.materials()) do
    local need=math.max(0,n-M.bagCount(id))
    for _,s in ipairs(M.sources(id)) do if not M.bankOpen and not M.guildOpen and need>0 and s.own and s.place=='bank' then add(itemName(id),'Withdraw '..math.min(s.n,need)..' from bank');break end end
  end
  for id,n in pairs(M.protectedStock()) do add(itemName(id),'Keep '..n..' in bags') end
end
local function chains()
  hint:SetText('Enter finished item ID at left and quantity at right. Prices use observed market depth.')
  action(1,'Compare',function()
    local id,n=itemID(field:GetText()),tonumber(second:GetText())
    if not id or not n or n<1 or n>999 or n~=math.floor(n) then return 'Enter an item and 1–999 units.' end
    local cost,steps,limited=M.supplyPlan(id,n)
    chain={id=id,n=n,cost=cost,steps=steps};page=1
    if limited then return 'Search limit reached. Displaying the available plan.' end
    if not cost then return 'Incomplete prices for this plan.' end
  end)
  action(2,'Save plan',function()
    if not chain or not chain.cost then return 'Compare a priced plan first.' end
    return M.saveSupplyPlan(chain)
  end)
  chain=chain or M.savedSupplyPlan()
  summary:SetText(chain and (itemName(chain.id)..' x '..chain.n..' / planned cash '..coins(chain.cost)..' / buy finished '..coins(M.cost(chain.id,chain.n))) or 'Visit each crafter’s profession window to record learned recipes.')
  for i,s in ipairs(chain and chain.steps or {}) do add(i..'. '..s.action..' '..itemName(s.id),s.n..' / '..(s.detail or '')..(s.cost and (' '..coins(s.cost)) or '')) end
end
local function farming()
  hint:SetText('Enter a farm or route name at left. Start when you begin looting; stop when done.')
  action(1,M.account().farmActive and 'Stop session' or 'Start session',function()
    return M.account().farmActive and M.farmStop() or M.farmStart(field:GetText())
  end)
  local list=M.account().farming or {}
  summary:SetText('Hourly rates / unpriced loot excluded from estimates / mixed items attributed in loot order')
  local routes={}
  for i,s in ipairs(list) do
    local r=routes[s.label] or {elapsed=0,vendor=0,market=0,returned=0,n=0};routes[s.label]=r
    r.elapsed=r.elapsed+(s.elapsed or math.max(1,time()-s.at));r.n=r.n+1
    for _,k in ipairs({'vendor','market','returned'}) do r[k]=r[k]+(s[k] or 0) end
  end
  for k,r in pairs(routes) do add(k..' ('..r.n..')','Vendor '..coins(r.vendor*3600/r.elapsed)..' / AH est. '..coins(r.market*3600/r.elapsed)..' / paid '..coins(r.returned*3600/r.elapsed)) end
end
refresh=function()
  if not f or not f:IsShown() then return end
  content={};for _,t in pairs(chart) do t:Hide() end;for _,b in ipairs(actions) do b:Hide() end
  if mode=='Basket' then basket() elseif mode=='Import' then imports() elseif mode=='Mail & bank' then logistics()
  elseif mode=='Supply plan' then chains() elseif mode=='Farming' then farming()
  else
    hint:SetText('Item ID or name at left. Daily price and supply use separate scales; empty days have no observation.')
    action(1,'7 days',function()days=7;page=1 end);action(2,'30 days',function()days=30;page=1 end)
    local id=itemID(field:GetText());if id then plot(id) else summary:SetText('Enter an item to view its market history.') end
  end
  local history=mode=='History'
  local per=history and 3 or 8
  local pages=math.max(1,math.ceil(#content/per));page=math.max(1,math.min(page,pages));pager:SetText(page..' / '..pages)
  for i,row in ipairs(rows) do
    local d=i<=per and content[(page-1)*per+i]
    row.left:SetText(d and d.a or '');row.right:SetText(d and d.b or '')
    row.btn:SetShown(d and d.label and true or false)
    if d and d.label then row.btn:SetText(d.label);row.btn:SetScript('OnClick',function()local msg=d.fn();refresh();if msg then message:SetText(msg) end end) end
  end
end
local function selectTab(tab,value)
  M.cancelMaterial();mode=tab;page=1;preview=nil;chain=nil;field:SetText(value and tostring(value) or '');second:SetText(tab=='Supply plan' and '1' or '')
  if tab=='Basket' then M.restockList();field:SetText(M.account().manager.active) end
  if tab=='Import' then second:SetText('Imported') end
  field:SetMultiLine(tab=='Import');field:ClearFocus();second:ClearFocus()
  message:SetText('');refresh()
  if tab=='Import' and value then field:SetFocus();field:HighlightText() end
end
function M.openTools(tab,value)
  if not f then
    f=CreateFrame('Frame','ForeverMarketToolsWindow',UIParent,'BasicFrameTemplateWithInset')
    f:SetSize(695,398);f:SetPoint('CENTER');f:SetFrameStrata('DIALOG');f:SetClampedToScreen(true);f:EnableMouse(true);f:SetMovable(true);f:RegisterForDrag('LeftButton')
    f:SetScript('OnDragStart',f.StartMoving);f:SetScript('OnDragStop',f.StopMovingOrSizing)
    if f.TitleText then f.TitleText:SetText('Forever Market') end
    for i,tabName in ipairs({'Basket','Mail & bank','Supply plan','History','Farming','Import'}) do button(12+(i-1)*111,-29,106,tabName,function()selectTab(tabName)end) end
    hint=font(16,-57,665);field=input(18,-77,334);second=input(367,-77,286)
    for i=1,4 do actions[i]=button(12+(i-1)*164,-111,156,'',function()end) end
    summary=font(16,-138,662);message=font(16,-361,664)
    for i=1,8 do local y=-161-(i-1)*24
      rows[i]={left=font(16,y,190),right=font(210,y,388),btn=button(599,y+5,78,'',function()end)}
    end
    button(18,-373,74,'Previous',function()page=page-1;refresh()end);pager=font(99,-378,55)
    button(154,-373,75,'Next',function()page=page+1;refresh()end)
    button(563,-372,100,'Refresh',refresh);field:SetScript('OnEnterPressed',function(self)self:ClearFocus();refresh()end)
    f:SetScript('OnHide',function()if M.quote and M.quote.trip then M.cancelMaterial() end end)
    local t=0
    f:SetScript('OnUpdate',function(_,dt)
      if mode=='Basket' and M.stepBasket then M.stepBasket() end
      t=t+dt;if t<.4 then return end;t=0
      if mode=='Mail & bank' and M.logisticsDirty then M.logisticsDirty=false;refresh() end
      local q=M.quote;local key=q and q.trip and (q.total or 'pending')
      if mode=='Basket' and (key~=lastQuote or M.tripDirty) then lastQuote=key;M.tripDirty=nil;refresh() end
    end)
    if UISpecialFrames then table.insert(UISpecialFrames,'ForeverMarketToolsWindow') end
  end
  f:Show();f:Raise();selectTab(tab or 'Basket',value)
end
