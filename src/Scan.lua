local api=C_AuctionHouse
if not api then return end
local panel,status,query,step,last,count,opened
local refreshTable,setScanning
local function finish(msg)
  query=nil;step=nil
  if status then status:SetText(msg);setScanning(false) end
end
local function begin()
  if not opened or not panel then print('Forever Market: open the auction house first.');return end
  if not panel:IsVisible() then panel.selectTab() end
  query={searchString='',filters={},sorts={},itemClassFilters={}}
  step=ForeverMarketReadySnapshot and ForeverMarketReadySnapshot() and 'start' or 'snapshot'
  count=0;last=GetTime()
  setScanning(true)
  status:SetText('Waiting for the auction house...')
end
ForeverMarketScan=begin
local function create()
  if panel then return end
  panel=CreateFrame('Frame',nil,AuctionHouseFrame)
  panel:SetPoint('TOPLEFT',18,-65);panel:SetPoint('BOTTOMRIGHT',-25,45);panel:Hide()
  if ForeverMarketPanelArt then ForeverMarketPanelArt(panel) end
  local function label(x,y,width,font)
    local t=panel:CreateFontString(nil,'OVERLAY',font or 'GameFontHighlightSmall')
    t:SetPoint('TOPLEFT',x,y);t:SetWidth(width);t:SetJustifyH('LEFT');t:SetWordWrap(false)
    return t
  end
  local function button(text,x,y,w,fn)
    local b=CreateFrame('Button',nil,panel,'UIPanelButtonTemplate');b:SetSize(w,22)
    b:SetPoint('TOPLEFT',x,y);b:SetText(text);b:SetScript('OnClick',fn);return b
  end
  label(10,-9,340,'GameFontNormalLarge'):SetText('Realm market prices')
  status=label(10,-35,680)
  status:SetText('Scan the auction house to update your local prices.')
  local scan=button('Scan market',390,-5,98,begin)
  local stop=button('Stop',492,-5,58,function()finish('Scan stopped.')end)
  button('Market home',555,-5,90,function()ForeverMarketTools.openTools('Home')end)
  button('Results',648,-5,68,function()ForeverMarketTools.openTools('Results')end)
  setScanning=function(active)scan:SetEnabled(not active);stop:SetEnabled(active)end
  setScanning(false)
  local heading=label(10,-69,432,'GameFontNormal')
  local records,page,rows={},1,{}
  local capacity=10
  local pageLabel=label(506,-69,103)
  local columns={{'Item',0},{'Supply',245},{'Lowest / item',310},{'Bulk / item',462},{'Observed',616}}
  local keys={'name','qty','low','bulk','seen'}
  local key,descending='qty',true
  local sourceLabel='Saved observations'
  local model,marketHistory
  local function relative(r)
    if not model or not r.low or r.pet then return end
    if r.stats==nil then r.stats=ForeverMarketTools.priceStatistics(r.historyKey or r.id,30,marketHistory) or false end
    if r.stats then return r.low/r.stats[model] end
  end
  local function sortRows()
    if key=='name' then
      for _,r in ipairs(records) do r.name=r.pet and ('Battle pet #'..r.pet) or C_Item.GetItemNameByID(r.id) or ('Item '..r.id) end
    end
    if key=='relative' then for _,r in ipairs(records) do r.relative=relative(r) end end
    table.sort(records,function(a,b)
      local x,y=a[key],b[key]
      if x~=y then
        if x==nil then return false elseif y==nil then return true end
        if descending then return x>y end
        return x<y
      end
      if (a.id or 0)~=(b.id or 0) then return (a.id or 0)<(b.id or 0) end
      return tostring(a.level or a.pet or '')<tostring(b.level or b.pet or '')
    end)
    heading:SetText(#records==0 and 'Your first scan will fill this price list.' or
      ('%s  /  %d items by %s'):format(sourceLabel,#records,key=='qty' and 'supply' or key))
  end
  local previous,nextPage
  local function paint()
    local pages=math.max(1,math.ceil(#records/capacity))
    page=math.max(1,math.min(page,pages));pageLabel:SetText(('Page %d / %d'):format(page,pages))
    previous:SetEnabled(page>1);nextPage:SetEnabled(page<pages)
    for i,r in ipairs(rows) do
      local e=records[(page-1)*capacity+i]
      local name=e and (e.pet and ('Battle pet #'..e.pet) or C_Item.GetItemNameByID(e.id) or ('Item #'..e.id))
      if e and e.level then name=name..' ('..e.level..')' end
      ForeverMarketSetItemText(r[1],e and (ForeverMarketRowIcon and ForeverMarketRowIcon(e.id,name) or name) or '')
      r[2]:SetText(e and tostring(e.qty or '-') or '')
      r[3]:SetText(e and ForeverMarketCoins(e.low) or '')
      r[4]:SetText(e and (e.bulk and ForeverMarketCoins(e.bulk) or '-') or '')
      local ratio=e and relative(e)
      r[5]:SetText(e and (model and (ratio and ('%.0f%%'):format(ratio*100) or 'No history') or e.seen and date('%b %d',e.seen)) or '')
      if r[5].SetTextColor then
        if ratio and ratio<.9 then r[5]:SetTextColor(.4,1,.55)
        elseif ratio and ratio>1.1 then r[5]:SetTextColor(1,.66,.45)
        else r[5]:SetTextColor(1,1,1) end
      end
      r.item=e and e.id
    end
  end
  previous=button('Previous',433,-62,68,function()page=page-1;paint()end)
  nextPage=button('Next',612,-62,65,function()page=page+1;paint()end)
  local headers=ForeverMarketResults(panel,91,columns)
  button('Compare asks',285,-63,114,function(self)
    local nextModel={median='ema',ema='filtered',filtered=false}
    if model then model=nextModel[model] else model='median' end
    keys[5]=model and 'relative' or 'seen'
    if key=='relative' or key=='seen' then key=keys[5] end
    if headers then headers[5].fmTitle:SetText(model and '% of model' or 'Observed') end
    self:SetText(model and ('vs '..model) or 'Compare asks')
    page=1;sortRows();paint()
  end)
  heading:SetWidth(262)
  for i=1,capacity do
    local y=-117-(i-1)*26
    ForeverMarketRowArt(panel,y+3,700,i)
    local row={label(10,y,229),label(253,y,52),label(318,y,138),label(470,y,138),label(624,y,77)}
    rows[i]=row
    local item=CreateFrame('Button',nil,panel)
    item:SetPoint('TOPLEFT',6,y+4);item:SetSize(230,23)
    item:SetScript('OnClick',function()if row.item then ForeverMarketTools.openTools('History',row.item) end end)
    item:SetScript('OnEnter',function(self)
      if row.item then GameTooltip:SetOwner(self,'ANCHOR_RIGHT');GameTooltip:SetHyperlink('item:'..row.item);GameTooltip:AddLine('Click for price history');GameTooltip:Show() end
    end)
    item:SetScript('OnLeave',function()GameTooltip:Hide()end);row.hit=item
  end
  if headers then
    local edges={0,245,310,462,616}
    local prefs=ForeverMarketDB.scanColumns or {};ForeverMarketDB.scanColumns=prefs
    local function layout()
      local right=math.max(690,panel:GetWidth()-4)
      for i=2,5 do
        edges[i]=math.max(edges[i-1]+60,math.min(tonumber(prefs[i]) or columns[i][2],right-(6-i)*60))
      end
      for i,h in ipairs(headers) do
        local w=(edges[i+1] or right)-edges[i]
        h:ClearAllPoints();h:SetPoint('TOPLEFT',edges[i],-91);h:SetWidth(w)
        for j,row in ipairs(rows) do
          row[i]:ClearAllPoints();row[i]:SetPoint('TOPLEFT',edges[i]+8,-117-(j-1)*26);row[i]:SetWidth(w-14)
          if i==1 then row.hit:SetWidth(w-14) end
        end
      end
    end
    for i,h in ipairs(headers) do
      h:EnableMouse(true)
      h:SetScript('OnMouseDown',function(self,button)
        if button=='RightButton' and i<5 then self.dragStart=GetCursorPosition();self.startEdge=edges[i+1] end
      end)
      h:SetScript('OnMouseUp',function(self,button)
        if button=='RightButton' and self.dragStart then
          prefs[i+1]=math.max(edges[i]+60,math.min((edges[i+2] or math.max(690,panel:GetWidth()-4))-60,self.startEdge+(GetCursorPosition()-self.dragStart)/panel:GetEffectiveScale()))
          self.dragStart=nil;layout()
        elseif button=='LeftButton' then
          if key==keys[i] then descending=not descending else key=keys[i];descending=i~=1 end
          page=1;sortRows();paint()
        end
      end)
      h:SetScript('OnEnter',function(self)GameTooltip:SetOwner(self,'ANCHOR_TOP');GameTooltip:AddLine('Click to sort. Right-drag to resize.');GameTooltip:Show()end)
      h:SetScript('OnLeave',function()GameTooltip:Hide()end)
    end
    layout();panel:HookScript('OnSizeChanged',layout)
  end
  refreshTable=function(snapshot)
    records={};page=1
    local history=ForeverMarketHistory();marketHistory=history
    if snapshot then
      local observedAt=time()-math.floor(GetTime()-snapshot.at)
      for id,book in pairs(snapshot.books) do
        records[#records+1]={id=id,seen=observedAt,qty=book.quantity,low=book.low,bulk=book.floorPrice}
      end
    else
      for key,h in pairs(history) do
        local raw=tostring(key)
        local id,level=raw:match('^gr?:(%d+):(%d+)')
        local pet=raw:match('^p:(%d+)$')
        id=tonumber(id or raw)
        if (id or pet) and h.m and h.m>0 then
          records[#records+1]={id=id,historyKey=key,pet=pet,level=level,low=h.m,qty=h.a and h.a[h.day],
            bulk=h.bulk and h.bulk.at and math.floor(h.bulk.at/86400)==h.day and h.bulk.price,seen=h.day and h.day*86400+43200}
        end
      end
    end
    sourceLabel=snapshot and 'Market snapshot' or 'Saved observations'
    sortRows()
    paint()
  end
  panel:SetScript('OnShow',function()refreshTable()end)
  panel:SetScript('OnHide',function() if query then finish('Scan stopped.') end end)
  panel:SetScript('OnUpdate',function()
    if not query then return end
    if step=='snapshot' then
      local data,state
      if ForeverMarketSnapshot then data,state=ForeverMarketSnapshot() end
      if data and data.at>=last then if ForeverMarketScanCompleted then ForeverMarketScanCompleted() end;refreshTable(data);finish(('Snapshot ready / %d auction rows / %ds old'):format(data.rows,GetTime()-data.at));return end
      if state=='pending' or state=='throttled' and GetTime()-last<20 then
        local done,total
        if ForeverMarketSnapshotProgress then done,total=ForeverMarketSnapshotProgress() end
        status:SetText(total and ('Reading auctions  /  %d of %d rows'):format(done,total) or 'Waiting for the realm snapshot...');return
      end
      step='start';last=GetTime();status:SetText('Requesting fresh auction listings...')
    end
    if GetTime()-last>20 then finish('Auction house timed out. Click Scan market to retry.');return end
    if step and not api.IsThrottledMessageSystemReady() then
      status:SetText('Waiting for the auction house to accept the next request...');return
    end
    if step then
      local action=step;step=nil;last=GetTime()
      if action=='start' then api.SendBrowseQuery(query) else api.RequestMoreBrowseResults() end
    end
  end)
  ForeverMarketTab('ForeverMarketScanTab',panel,'Market Scan','Market Scan')
end
if hooksecurefunc and api.SendBrowseQuery then
  hooksecurefunc(api,'SendBrowseQuery',function(other)
    if query and other~=query then finish('Scan interrupted by another auction search.') end
  end)
end
local f=CreateFrame('Frame')
for _,ev in ipairs({'AUCTION_HOUSE_SHOW','AUCTION_HOUSE_CLOSED','AUCTION_HOUSE_BROWSE_RESULTS_UPDATED','AUCTION_HOUSE_BROWSE_RESULTS_ADDED'}) do f:RegisterEvent(ev) end
f:SetScript('OnEvent',function(_,ev)
  if ev=='AUCTION_HOUSE_SHOW' then opened=true;create();return end
  if ev=='AUCTION_HOUSE_CLOSED' then opened=false;if query then finish('Scan stopped.') end;return end
  if not query or step=='start' or step=='snapshot' then return end
  local rows=api.GetBrowseResults()
  if not api.HasFullBrowseResults() then
    if #rows>count or count==0 and step==nil then
      count=#rows;step='more';last=GetTime();status:SetText(('Scanning / %d listings found'):format(count))
    end
    return
  end
  local combined={}
  for _,row in ipairs(rows) do
    if row.itemKey and row.minPrice and row.minPrice>0 and row.totalQuantity and row.totalQuantity>0 then
      local k=ForeverMarketHistoryKey(row.itemKey)
      local r=combined[k] or {price=row.minPrice,n=0};combined[k]=r
      r.price=math.min(r.price,row.minPrice);r.n=r.n+row.totalQuantity
    end
  end
  local n=0
  for k,r in pairs(combined) do ForeverMarketObserve(k,r.price,r.n);n=n+1 end
  if ForeverMarketScanCompleted then ForeverMarketScanCompleted() end
  refreshTable();finish(('Scan complete / %d item prices saved.'):format(n))
end)
