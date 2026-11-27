local M=ForeverMarketTools
local hub,book,reader
local sections={'Overview','Sales & profit','Item history','Watchlist','Research'}
local coins=ForeverMarketCoins
local function name(id)
  return C_Item.GetItemNameByID(id) or ('Item '..id)
end
local function dated(at) return date('%b %d %H:%M',at) end
local function data(view)
  local entries={}
  local function add(title,detail,click)
    entries[#entries+1]={title=tostring(title),detail=detail or '',click=click}
  end
  local function selectPage(page,item)
    view.section=page;view.page=1;view.detail=nil
    if item then view.item=item end
    view.refresh()
  end
  local function tool(page)
    return function()view.frame:Hide();M.openTools(page)end
  end
  local function lookup(id)
    if id then return function()selectPage('Item history',id)end end
  end
  local section=view.section
  local cutoff=time()-view.days*86400
  if section=='Overview' then
    local fund=M.fundSummary(view.detail)
    if view.detail then
      add('Return to overview','All fund balances',function()selectPage('Overview')end)
      for _,row in ipairs(fund.rows) do add(row.name,row.detail) end
    else
      for _,v in ipairs({{'Spendable trading cash','cash'},{'Inventory at cost','inventory'},{'Estimated fund proceeds','pending'},{'Realized fund profit','profit'}}) do
        local key=v[2]
        add(v[1],coins(fund[key]),function()view.detail=key;view.page=1;view.refresh()end)
      end
      local a=M.account()
      local seen=a.dashboardListings and a.dashboardListings[M.scope()]
      add('Active auctions at asking price',seen and coins(seen.value)..'  /  '..dated(seen.at) or 'Visit My Auctions to record your listings.')
      local mail=0;for _,m in ipairs(a.mail or {}) do mail=mail+(m.amount or 0) end
      add('Sale money observed in mail',a.mailAsOf and coins(mail)..'  /  '..dated(a.mailAsOf) or 'Open your mailbox to check.')
      add('Receipts outside matched fund sales',coins(fund.other))
    end
  elseif section=='Sales & profit' then
    for _,invest in ipairs({false,true}) do
      local r=M.tradeResults(view.days,invest)
      add(invest and 'Investment purchases' or 'Flip purchases',r.count..' buys  /  '..coins(r.spent)..' spent  /  '..coins(r.profit)..' realized')
    end
    local labels={purchase='Purchased',posted='Posted',sale_notice='Sale reported',proceeds_collected='Collected',auction_expired='Expired',purchased_item_received='Received purchase'}
    local events=ForeverMarketActivity and ForeverMarketActivity.events or {}
    for i=#events,1,-1 do
      local e=events[i]
      if labels[e.kind] and e.at and e.at>=cutoff and e.region==GetCurrentRegion() and e.character==UnitName('player') and e.faction==UnitFactionGroup('player') and ForeverMarketEventRealm(e)==ForeverMarketVenueRealm() then
        local amount=e.amount or e.total
        add(labels[e.kind]..'  '..(e.name or ''),dated(e.at)..(e.quantity and '  /  x'..e.quantity or '')..(amount and '  /  '..coins(amount) or ''),lookup(e.itemId))
      end
    end
  elseif section=='Item history' then
    local id=view.item
    if id then
      local series=M.historySeries(id,view.days);view.series=series
      local flips=ForeverMarketTradingFund().flips or {}
      local cost,n=0,0
      for _,r in ipairs(flips) do
        if r.item==id and r.at and r.at>=cutoff then cost=cost+r.cost;n=n+r.n end
      end
      add(name(id),n>0 and (n..' bought / average '..coins(math.floor(cost/n))) or 'No tracked fund buys in this period.')
      for i=#series,1,-1 do
        local b=series[i]
        if b.ask or b.sale or b.units then
          add(date('!%b %d',b.day*86400),'Bulk '..(b.ask and coins(b.ask) or '—')..'  /  sold '..(b.sale and coins(math.floor(b.sale)) or '—')..'  /  supply '..(b.units or '—'))
        end
      end
    else add('Find an item','Enter a name, item ID or link above. You can also select an item in Watchlist.') end
  elseif section=='Watchlist' then
    local rows={}
    local hist=ForeverMarketHistory()
    for id,rule in pairs(M.session().watches) do
      local h=hist[tostring(id)] or {};local days={}
      for day in pairs(h.floors or {}) do if day>=math.floor(cutoff/86400) then days[#days+1]=day end end
      table.sort(days)
      local trend=#days>=2 and ('%+.0f%%'):format(100*(h.floors[days[#days]]/h.floors[days[1]]-1)) or '—'
      rows[#rows+1]={id=id,title=name(id),detail='Cap '..coins(rule.cap)..'  /  '..trend..' ('..#days..' days)  /  '..(rule.at and dated(rule.at) or 'Unchecked')}
    end
    table.sort(rows,function(a,b)return a.title<b.title end)
    for _,r in ipairs(rows) do add(r.title,r.detail,lookup(r.id)) end
    local sellers={}
    for _,invest in ipairs({false,true}) do
      for title,r in pairs(M.tradeResults(view.days,invest).items) do if r.paid>0 then sellers[title]=(sellers[title] or 0)+r.paid end end
    end
    local ranked={};for title,units in pairs(sellers) do ranked[#ranked+1]={title=title,units=units} end
    table.sort(ranked,function(a,b)if a.units==b.units then return a.title<b.title end return a.units>b.units end)
    for _,r in ipairs(ranked) do add(r.title,'Paid fund sales  /  '..r.units..' units') end
  elseif section=='Research' then
    local f=ForeverMarketTradingFund();local runs={}
    for id,r in pairs(f.sessions or {}) do if r.at and r.at>=cutoff then runs[#runs+1]={id=id,r=r} end end
    table.sort(runs,function(a,b)return a.r.at>b.r.at end)
    local outcomes=M.runOutcomes(f)
    for _,v in ipairs(runs) do local o=outcomes[v.id] or {}
      add('Scan  /  '..dated(v.r.at),(v.r.hits or 0)..' deals  /  7-day realized '..coins(o.profit or 0))
    end
    for _,v in ipairs(ForeverMarketPaperResults()) do
      local p=v.paper
      if v.id then add(name(v.id),'Forward tests, lifetime  /  '..p.hits..' hit  /  '..p.misses..' missed  /  '..p.gaps..' incomplete',lookup(v.id)) end
    end
    local research=ForeverMarketResearch
    local realm=ForeverMarketVenueRealm();local faction=UnitFactionGroup('player')
    if research and research.region==GetCurrentRegion() and research.faction==faction and research.at and research.at>=cutoff and (research.realm==realm or ForeverMarketDesktopRealm and research.realm==ForeverMarketDesktopRealm(realm,research.region,faction)) then
      local picks={}
      for id,r in pairs(research.items or {}) do picks[#picks+1]={id=id,rank=r.rank,ceiling=r.ceiling} end
      table.sort(picks,function(a,b)return a.rank<b.rank end)
      local sim=research.simulation
      if sim and sim.at and sim.at>=cutoff then
        add('Desktop simulation  /  '..dated(sim.at),sim.paths..' modeled paths  /  starting cash '..coins(sim.budget))
        for _,result in ipairs(sim.results or {}) do
          add(result.scenario,result.policy..'  /  modeled median profit '..coins(result.medianProfit))
        end
      end
      add('Desktop research',dated(research.at)..'  /  '..#picks..' ranked items')
      for _,r in ipairs(picks) do add('#'..r.rank..'  '..name(r.id),'Research ceiling  '..coins(r.ceiling),lookup(r.id)) end
    end
  elseif view.full and section=='Tools' then
    for _,v in ipairs({{'Selling session','Posting and relisting','Sell session'},{'Shopping basket','Plan restocks','Basket'},{'Supply plan','Crafting and materials','Supply plan'},{'Mail & bank','Inventory and transfers','Mail & bank'},{'Price watches','Set item ceilings','Watches'},{'Scan outcomes','Benchmarks and comparisons','Scan results'},{'Farming','Review farming sessions','Farming'}}) do add(v[1],v[2],tool(v[3])) end
  elseif view.full and section=='Settings' then
    local function numeric(title,value,save)
      add(title,tostring(value)..'  /  Edit',function()
        view.edit={title=title,save=save};view.field:SetText(tostring(value));view.refresh();view.field:SetFocus()
      end)
    end
    numeric('Fund cash (gold)',ForeverMarketTradingFund().cash/10000,ForeverMarketSetFundGold)
    numeric('Minimum flip profit (%)',ForeverMarketMarginBP()/100,function(n)
      if n<0 or n>1000 then return nil,'Enter 0 to 1000%.' end
      ForeverMarketDB.buyTargetBP=math.floor(n*100+.5);return true
    end)
    numeric('Auction cut (%)',M.settings().cutBP/100,function(n)
      if n<0 or math.floor(n*100+.5)>=10000 then return nil,'Enter 0 to under 100%.' end
      M.settings().cutBP=math.floor(n*100+.5);M.invalidate();return true
    end)
    numeric('Lost deposit (copper per unit)',M.settings().lostDepositPerUnit,function(n)
      if n<0 or n>100000000 or n~=math.floor(n) then return nil,'Enter a whole copper amount.' end
      M.settings().lostDepositPerUnit=n;M.invalidate();return true
    end)
    local function toggle(fn) return function()fn();view.refresh()end end
    add('Posting price',ForeverMarketDB.matchBulk and 'Match bulk ask' or 'Undercut bulk ask',toggle(function()ForeverMarketDB.matchBulk=not ForeverMarketDB.matchBulk end))
    add('Stored stock for crafting',M.account().useTransfers and 'Include transferable stock' or 'Use bag stock only',toggle(function()M.account().useTransfers=not M.account().useTransfers;M.invalidate()end))
    add('Live desktop activity strip',ForeverMarketLiveSync() and 'Enabled' or 'Disabled',toggle(function()ForeverMarketLiveSync(not ForeverMarketLiveSync())end))
    add('Group rules','Pricing and stocking presets',tool('Rule presets'))
    add('Import profiles','Review groups and operations',tool('Import'))
    add('Desktop export','Prepare an updated export for the next save',function()SlashCmdList.FOREVERMARKET('export')end)
  end
  if #entries==0 then add('No observations yet','Collected records for this view will appear here.') end
  return entries
end
M.dashboardRows=data
local function label(parent,x,y,width,font)
  local s=parent:CreateFontString(nil,'OVERLAY',font or 'GameFontHighlightSmall')
  s:SetPoint('TOPLEFT',x,y);s:SetWidth(width);s:SetJustifyH('LEFT');s:SetWordWrap(false);return s
end
local function button(parent,x,y,w,title,click)
  local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate')
  b:SetPoint('TOPLEFT',x,y);b:SetSize(w,23);b:SetText(title);b:SetScript('OnClick',click);return b
end
local function panelStyle(p)
  p:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=12})
  p:SetBackdropColor(.095,.077,.061,.98);p:SetBackdropBorderColor(.62,.47,.26,1)
end
local function create(full,detached)
  local window=full or detached
  local p=CreateFrame('Frame',full and 'ForeverMarketDashboard' or detached and 'ForeverMarketReport' or nil,window and UIParent or AuctionHouseFrame,'BackdropTemplate')
  p:Hide();panelStyle(p);p:EnableMouse(true)
  if window then
    p:SetSize(718,415);p:SetPoint('CENTER');p:SetFrameStrata('DIALOG');p:SetClampedToScreen(true);p:SetMovable(true)
    p:RegisterForDrag('LeftButton');p:SetScript('OnDragStart',p.StartMoving);p:SetScript('OnDragStop',p.StopMovingOrSizing)
    table.insert(UISpecialFrames,p:GetName())
  else p:SetPoint('TOPLEFT',15,-60);p:SetPoint('BOTTOMRIGHT',-18,36) end
  local v={frame=p,full=full,page=1,section='Overview',days=14}
  local title=label(p,16,-14,445,'GameFontNormalLarge')
  title:SetText(full and 'Forever Market  /  Dashboard' or 'Market analytics')
  if window then button(p,638,-10,61,'Close',function()p:Hide()end) end
  local context=label(p,16,-41,684)
  local nav={}
  local views={unpack(sections)}
  if full then views[#views+1]='Tools';views[#views+1]='Settings' end
  for i,section in ipairs(views) do
    local b=button(p,12,-69-(i-1)*31,115,section,function()
      v.section=section;v.page=1;v.detail=nil;v.edit=nil;v.refresh()
    end)
    local mark=b:CreateTexture(nil,'OVERLAY');mark:SetPoint('LEFT',4,0);mark:SetSize(3,16);mark:SetColorTexture(1,.77,.28,1)
    nav[section]={b,mark}
  end
  local header=label(p,142,-73,211,'GameFontNormalLarge')
  local ranges={}
  for i,d in ipairs({7,14,30}) do
    ranges[d]=button(p,389+i*57,-66,54,d..' days',function()v.days=d;v.page=1;v.refresh()end)
  end
  button(p,622,-66,75,'Refresh',function()v.refresh()end)
  local field=CreateFrame('EditBox',nil,p,'InputBoxTemplate');field:SetPoint('TOPLEFT',150,-100);field:SetSize(255,22);field:SetAutoFocus(false)
  local function findItem()
    local input=field:GetText():match('^%s*(.-)%s*$')
    if v.edit then
      local n=tonumber(input)
      if not n or n~=n then header:SetText('Enter a number');return end
      local ok,why=v.edit.save(n)
      if not ok then context:SetText(why);return end
      v.edit=nil;field:SetText('');field:ClearFocus();v.refresh();return
    end
    local id=tonumber(input) or tonumber(input:match('item:(%d+)')) or C_Item.GetItemInfoInstant(input)
    if not id or id<=0 or id~=math.floor(id) then header:SetText('Enter item name or ID');return end
    v.item=id;v.page=1;field:ClearFocus();v.refresh()
  end
  field:SetScript('OnEnterPressed',findItem)
  local find=button(p,412,-99,64,'Find item',findItem)
  local bars={}
  for i=1,30 do local bar=p:CreateTexture(nil,'ARTWORK');bar:SetColorTexture(.84,.65,.25,.92);bars[i]=bar end
  local chartLabel=label(p,484,-104,212)
  local rows={}
  local pageLabel=label(p,242,-364,120)
  local prev,nextButton
  local function paint()
    local n=math.max(1,math.ceil(#v.entries/#rows));v.page=math.max(1,math.min(v.page,n))
    pageLabel:SetText(('Page %d of %d'):format(v.page,n));prev:SetEnabled(v.page>1);nextButton:SetEnabled(v.page<n)
    local withChart=v.section=='Item history' or v.edit
    for i,r in ipairs(rows) do
      local entry=v.entries[(v.page-1)*#rows+i];r.entry=entry
      r.frame:ClearAllPoints();r.frame:SetPoint('TOPLEFT',p,'TOPLEFT',141,-(withChart and 161 or 105)-(i-1)*24)
      r.frame:SetShown(entry~=nil)
      if entry then
        r.title:SetText(entry.title);r.detail:SetText(entry.detail)
        r.title:SetTextColor(entry.click and 1 or .88,entry.click and .82 or .88,entry.click and .44 or .88)
      end
    end
  end
  for i=1,8 do
    local b=CreateFrame('Button',nil,p);b:SetSize(556,23)
    local bg=b:CreateTexture(nil,'BACKGROUND');bg:SetAllPoints();bg:SetColorTexture(.55,.44,.26,i%2==0 and .14 or .06)
    local r={frame=b,title=label(b,5,-5,198),detail=label(b,209,-5,340)};rows[i]=r
    b:SetScript('OnClick',function()if r.entry and r.entry.click then r.entry.click()end end)
    b:SetScript('OnEnter',function(self)
      if r.entry then GameTooltip:SetOwner(self,'ANCHOR_RIGHT');GameTooltip:AddLine(r.entry.title);GameTooltip:AddLine(r.entry.detail,1,1,1,true);GameTooltip:Show()end
    end);b:SetScript('OnLeave',function()GameTooltip:Hide()end)
  end
  prev=button(p,141,-358,84,'Previous',function()v.page=v.page-1;paint()end)
  nextButton=button(p,356,-358,84,'Next',function()v.page=v.page+1;paint()end)
  v.refresh=function()
    v.series=nil;v.entries=data(v)
    context:SetText(UnitName('player')..'  /  '..M.scope())
    header:SetText(v.section)
    for section,n in pairs(nav) do n[1]:SetEnabled(section~=v.section);n[2]:SetShown(section==v.section) end
    local historical=v.section~='Overview' and v.section~='Tools' and v.section~='Settings'
    for d,b in pairs(ranges) do b:SetShown(historical);b:SetEnabled(d~=v.days) end
    local history=v.section=='Item history';field:SetShown(history or v.edit~=nil);find:SetShown(history or v.edit~=nil);find:SetText(v.edit and 'Save' or 'Find item')
    chartLabel:SetShown(history or v.edit~=nil);chartLabel:SetText(v.edit and v.edit.title or 'Daily bulk ask')
    local peak=0
    for _,r in ipairs(v.series or {}) do peak=math.max(peak,r.ask or 0) end
    for i,b in ipairs(bars) do
      local r=v.series and v.series[i]
      if r and r.ask and peak>0 then
        local w=math.floor(546/v.days);b:ClearAllPoints();b:SetPoint('BOTTOMLEFT',p,'TOPLEFT',146+(i-1)*w,-156)
        b:SetSize(w-2,math.max(1,math.floor(28*r.ask/peak)));b:Show()
      else b:Hide() end
    end
    paint()
  end
  v.field=field
  p:SetScript('OnShow',function()v.refresh()end)
  if not window then ForeverMarketTab('ForeverMarketAnalytics',p,'Analytics','Market Analytics') end
  return v
end
function M.openDashboard()
  hub=hub or create(true)
  if hub.frame:IsShown() then hub.refresh() else hub.frame:Show() end
  hub.frame:Raise()
end
function M.openAnalytics()
  if book and AuctionHouseFrame:IsShown() then book.frame.selectTab();return end
  reader=reader or create(false,true);reader.frame:Show();reader.frame:Raise()
end
local events=CreateFrame('Frame')
for _,e in ipairs({'AUCTION_HOUSE_SHOW','OWNED_AUCTIONS_UPDATED','MAIL_CLOSED','BAG_UPDATE_DELAYED','PLAYER_MONEY'}) do events:RegisterEvent(e) end
events:SetScript('OnEvent',function(_,event)
  if event=='AUCTION_HOUSE_SHOW' and not book then book=create(false) end
  if event=='OWNED_AUCTIONS_UPDATED' and AuctionHouseFrame and AuctionHouseFrame:IsShown() and C_AuctionHouse.HasFullOwnedAuctionResults and C_AuctionHouse.HasFullOwnedAuctionResults() then
    local a=M.account();a.dashboardListings=a.dashboardListings or {}
    a.dashboardListings[M.scope()]={value=M.saleTotals(),at=time()}
  end
  for _,v in pairs({hub=hub,book=book,reader=reader}) do
    if v.frame:IsVisible() and not v.pending then
      v.pending=true
      C_Timer.After(.5,function()v.pending=nil;if v.frame:IsVisible() then v.refresh() end end)
    end
  end
end)
if hooksecurefunc and ChatEdit_InsertLink then
  hooksecurefunc('ChatEdit_InsertLink',function(link)
    for _,v in pairs({hub=hub,book=book,reader=reader}) do
      if v.frame:IsVisible() and v.section=='Item history' and v.field:HasFocus() then
        local id=tonumber(link:match('item:(%d+)'))
        if id then v.field:SetText(tostring(id));v.item=id;v.page=1;v.field:ClearFocus();v.refresh() end
      end
    end
  end)
end
