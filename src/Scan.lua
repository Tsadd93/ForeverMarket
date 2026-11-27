local api=C_AuctionHouse
if not api then return end
local panel,status,query,step,last,count,opened
local function finish(msg)
  query=nil;step=nil
  if status then status:SetText(msg) end
end
local function begin()
  if not opened or not panel then print('Forever Market: open the auction house first.');return end
  if not panel:IsVisible() then panel.selectTab() end
  query={searchString='',filters={},sorts={},itemClassFilters={}}
  step='snapshot';count=0;last=GetTime()
  status:SetText('Waiting for the auction house…')
end
ForeverMarketScan=begin
local function create()
  if panel then return end
  panel=CreateFrame('Frame',nil,AuctionHouseFrame)
  panel:SetPoint('TOPLEFT',18,-65);panel:SetPoint('BOTTOMRIGHT',-25,45);panel:Hide()
  if ForeverMarketPanelArt then ForeverMarketPanelArt(panel) end
  status=panel:CreateFontString(nil,'OVERLAY','GameFontHighlight')
  status:SetPoint('TOPLEFT',4,-42);status:SetPoint('RIGHT',-8,0);status:SetJustifyH('LEFT')
  status:SetText('Scan current listings to build local market history.')
  local function button(text,x,fn)
    local b=CreateFrame('Button',nil,panel,'UIPanelButtonTemplate');b:SetSize(120,24)
    b:SetPoint('TOPLEFT',x,0);b:SetText(text);b:SetScript('OnClick',fn)
  end
  button('Scan market',4,begin)
  button('Market home',262,function()if ForeverMarketTools and ForeverMarketTools.openTools then ForeverMarketTools.openTools('Home') end end)
  button('Results',390,function()if ForeverMarketTools and ForeverMarketTools.openTools then ForeverMarketTools.openTools('Results') end end)
  button('Stop',132,function() finish('Scan stopped.') end)
  panel:SetScript('OnHide',function() if query then finish('Scan stopped.') end end)
  panel:SetScript('OnUpdate',function()
    if not query then return end
    if step=='snapshot' then
      local data,state
      if ForeverMarketSnapshot then data,state=ForeverMarketSnapshot() end
      if data then finish(('Snapshot ready · %d auction rows · %ds old'):format(data.rows,GetTime()-data.at));return end
      if state=='pending' or state=='throttled' and GetTime()-last<20 then status:SetText('Receiving market snapshot…');return end
      step='start';last=GetTime()
    end
    if GetTime()-last>20 then finish('Auction house timed out. Click Scan market to retry.');return end
    if step and api.IsThrottledMessageSystemReady() then
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
  if ev=='AUCTION_HOUSE_CLOSED' then opened=false;query=nil;return end
  if not query or step=='start' or step=='snapshot' then return end
  local rows=api.GetBrowseResults()
  if not api.HasFullBrowseResults() then
    if #rows>count or count==0 and step==nil then
      count=#rows;step='more';last=GetTime();status:SetText(('Scanning �· %d listings found'):format(count))
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
  finish(('Scan complete �· %d item prices saved.'):format(n))
end)
