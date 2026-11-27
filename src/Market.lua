local GetRealmName=ForeverMarketVenueRealm or function() return _G.GetRealmName and _G.GetRealmName() or '' end
-- Conservative resale assumptions shared by both auction tabs.
function ForeverMarketPostPrice(bulkAsk)
  return math.max(1,bulkAsk-2)
end
function ForeverMarketMarginBP()
  return ForeverMarketDB and ForeverMarketDB.buyTargetBP or ForeverMarketRisk and ForeverMarketRisk.marginBP or 2000
end
function ForeverMarketKeepBP()
  return 10000-(ForeverMarketDB and ForeverMarketDB.pricing and ForeverMarketDB.pricing.cutBP or ForeverMarketRisk and ForeverMarketRisk.cutBP or 500)
end
function ForeverMarketSaleNet(gross)
  return math.floor(gross*ForeverMarketKeepBP()/10000)
end
-- The successful-sale invoice returns the posting deposit. Budget for it
-- upfront; expense only the configured allowance for failed listings.
function ForeverMarketDepositLoss(quantity)
  return quantity*math.ceil(ForeverMarketDB and ForeverMarketDB.pricing and ForeverMarketDB.pricing.lostDepositPerUnit or ForeverMarketRisk and ForeverMarketRisk.lostDepositPerUnit or 0)
end
function ForeverMarketFundMinimum(cost,quantity,deposit,stack)
  if quantity<=0 then return 0 end
  return math.ceil((math.ceil(cost*stack/quantity)+ForeverMarketDepositLoss(stack))*10000/(ForeverMarketKeepBP()*stack))
end
-- Ignore instance GUID and viewer level; keep the sale-relevant variant fields.
function ForeverMarketVariant(k,link)
  if not k or not link then return end
  local pet=link:match('battlepet:([^|]+)')
  if pet then
    local species,level,quality,health,power,speed=pet:match('^(%d+):(%d+):(%d+):(%d+):(%d+):(%d+)')
    if species then return table.concat({'pet',species,level,quality,health,power,speed},':') end
    return
  end
  local raw=link:match('item:([^|]+)')
  if not raw then return end
  local parts={}
  for part in (raw..':'):gmatch('(.-):') do parts[#parts+1]=part end
  for i=#parts+1,10 do parts[i]='' end
  parts[8]='';parts[9]='';parts[10]=''
  while #parts>1 and parts[#parts]=='' do table.remove(parts) end
  return table.concat({k.itemID,k.itemLevel or 0,k.itemSuffix or 0,table.concat(parts,':')},'/')
end
-- Use the client's auction art and fonts on each market surface.
function ForeverMarketTextHint(owner,region)
  if not region or not region.IsTruncated then return end
  local hit=CreateFrame('Frame',nil,owner)
  hit:SetAllPoints(region)
  if hit.SetMouseMotionEnabled and hit.SetMouseClickEnabled then
    hit:SetMouseMotionEnabled(true);hit:SetMouseClickEnabled(false)
  elseif hit.SetPropagateMouseClicks then
    hit:EnableMouse(true);hit:SetPropagateMouseClicks(true)
  end
  hit:SetScript('OnEnter',function(self)
    if region:IsTruncated() then
      GameTooltip:SetOwner(self,'ANCHOR_RIGHT');GameTooltip:AddLine(region:GetText(),1,.93,.78,true);GameTooltip:Show()
    end
  end)
  hit:SetScript('OnLeave',function(self)if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
end
function ForeverMarketPanelArt(panel)
  if panel.fmArt or not panel.CreateTexture then return end
  local bg=panel:CreateTexture(nil,'BACKGROUND',nil,1)
  bg:SetPoint('TOPLEFT',5,-4);bg:SetPoint('BOTTOMRIGHT',-5,4)
  if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo('auctionhouse-background-index') then
    bg:SetAtlas('auctionhouse-background-index')
  else bg:SetTexture('Interface\\FrameGeneral\\UI-Background-Marble') end
  if bg.SetVertexColor then bg:SetVertexColor(.65,.60,.51,.94) end
  panel.fmArt=bg
end
function ForeverMarketRowArt(parent,y,w,index)
  if not parent.CreateTexture then return end
  local t=parent:CreateTexture(nil,'BACKGROUND',nil,3)
  if not t.SetColorTexture then return end
  t:SetPoint('TOPLEFT',5,y);t:SetSize(w,22)
  if index%2==0 then t:SetColorTexture(.64,.49,.24,.10) else t:SetColorTexture(.08,.055,.03,.18) end
  return t
end
function ForeverMarketResults(panel,top,columns)
  local inset=CreateFrame('Frame',nil,panel,'InsetFrameTemplate')
  inset:SetPoint('TOPLEFT',0,-top);inset:SetPoint('BOTTOMRIGHT',0,2)
  inset:SetFrameLevel(panel:GetFrameLevel());inset:EnableMouse(false)
  local bg=inset:CreateTexture(nil,'BACKGROUND',nil,1)
  bg:SetPoint('TOPLEFT',4,-4);bg:SetPoint('BOTTOMRIGHT',-4,4)
  if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo('auctionhouse-background-index') then
    bg:SetAtlas('auctionhouse-background-index')
  else bg:SetTexture('Interface\\FrameGeneral\\UI-Background-Marble') end
  for i,c in ipairs(columns) do
    local h=CreateFrame('Frame',nil,panel,'BackdropTemplate')
    h:SetPoint('TOPLEFT',c[2],-top)
    if columns[i+1] then h:SetWidth(columns[i+1][2]-c[2]) else h:SetPoint('RIGHT',panel,'RIGHT',-4,0) end
    h:SetHeight(22)
    h:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=8,insets={left=2,right=2,top=2,bottom=2}})
    h:SetBackdropColor(.15,.13,.11,.96);h:SetBackdropBorderColor(.58,.55,.49,.85)
    local title=h:CreateFontString(nil,'OVERLAY','GameFontNormalSmall')
    title:SetPoint('LEFT',8,0);title:SetPoint('RIGHT',-5,0);title:SetJustifyH('LEFT');title:SetWordWrap(false);title:SetTextColor(1,.97,.87);title:SetText(c[1])
  end
end
function ForeverMarketHover(parent,y,width,row)
  local hit=CreateFrame('Button',nil,parent)
  hit:SetPoint('TOPLEFT',3,y);hit:SetSize(width,24)
  hit:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight','ADD')
  hit:SetFrameLevel(parent:GetFrameLevel())
  hit:SetScript('OnEnter',function(self)
    if row.itemRef then GameTooltip:SetOwner(self,'ANCHOR_RIGHT');GameTooltip:SetHyperlink(row.itemRef);if row.marketId and ForeverMarketTools and ForeverMarketTools.explain then ForeverMarketTools.explain(GameTooltip,row.marketId,row.priceReason) elseif row.saleText then GameTooltip:AddLine(row.saleText) end;GameTooltip:Show() end
  end)
  hit:SetScript('OnClick',function()
    if row.marketId and IsShiftKeyDown and IsShiftKeyDown() and ForeverMarketTools.openTools then ForeverMarketTools.openTools('History',row.marketId);return end
    if row.itemRef and SetItemRef then
      local link=row.itemRef:match('|H([^|]+)|h') or row.itemRef
      SetItemRef(link,row.itemRef,'LeftButton')
    end
  end)
  hit:SetScript('OnLeave',function()GameTooltip:Hide()end)
  return hit
end
function ForeverMarketRowIcon(id,text)
  local icon=id and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
  return (icon and ('|T'..icon..':17:17|t  ') or '')..(text or ''):gsub('%[([^%]]+)%]','%1')
end
local coinFormat='%s%d|TInterface\\MoneyFrame\\UI-GoldIcon:12:12|t  %d|TInterface\\MoneyFrame\\UI-SilverIcon:12:12|t  %d|TInterface\\MoneyFrame\\UI-CopperIcon:12:12|t'
function ForeverMarketCoins(value)
  local copper=math.floor(math.abs(value or 0))
  return string.format(coinFormat,(value or 0)<0 and '-' or '',math.floor(copper/10000),math.floor(copper/100)%100,copper%100)
end
local function quote(s)
  return '"' .. tostring(s):gsub('[%z\1-\31\\"]', function(c)
    if c == '\\' then return '\\\\' end
    if c == '"' then return '\\"' end
    return string.format('\\u%04x', string.byte(c))
  end) .. '"'
end
local function json(v)
  if type(v) == 'string' then return quote(v) end
  if type(v) == 'number' then return tostring(v) end
  if type(v) == 'boolean' then return v and 'true' or 'false' end
  if type(v) ~= 'table' then return 'null' end
  local a = {}
  if #v > 0 then
    for _, x in ipairs(v) do a[#a+1] = json(x) end
    return '[' .. table.concat(a, ',') .. ']'
  end
  for k,x in pairs(v) do a[#a+1] = quote(k) .. ':' .. json(x) end
  return '{' .. table.concat(a, ',') .. '}'
end
ForeverMarketJSON=json
local function market()
  return GetRealmName() .. '|' .. UnitFactionGroup('player')
end
local function info(key)
  local species=tonumber(key:match('^p:(%d+)$'))
  if species then
    local name=C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID(species)
    return 82800,name or ('Pet '..species),17
  end
  local id = tonumber(key) or tonumber(key:match('^gr:(%d+):')) or tonumber(key:match('^g:(%d+):'))
  if not id then return nil end
  local get = C_Item and C_Item.GetItemInfo or GetItemInfo
  local name,link,quality,level,req,typ,sub,stack,slot,texture,vendor,class = get(id)
  if not class then
    local instant=C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if instant then class=select(6,instant(id)) end
  end
  return id, name or ('Item ' .. id), class
end
-- Keep the published export intact until a complete replacement is ready.
local worker,wanted,announce
local cache,cacheScope={}
local function assemble(sliced)
  if not ForeverMarketMigrate() then return end
  local history=ForeverMarketHistory()
  local scope=market()
  local live=ForeverMarketDB[scope] or {}
  if cacheScope~=history then cache={};cacheScope=history end
  local start=time()
  local parts,count={},0
  local since=debugprofilestop and debugprofilestop() or 0
  for key,d in pairs(history) do
    if type(d)=='table' and type(d.h)=='table' then
      local record=cache[key]
      if not record or record.data~=d or record.live~=live[key] or record.untilAt<=start then
        local id,name,class=info(tostring(key))
        if id then
          local days,expires={},start+86400
          for day,high in pairs(d.h) do
            local stamp=(d.stamp and d.stamp[day]) or tonumber(day)*86400
            if stamp>start-30*86400 then
              days[#days+1]={at=stamp,low=(d.l and d.l[day]) or high,high=high,quantity=d.a and d.a[day]}
              expires=math.min(expires,stamp+30*86400)
            end
          end
          record={data=d,live=live[key],untilAt=expires,text=json({key=tostring(key),id=id,name=name,class=class,history=days,live=live[key]})}
          cache[key]=record
        else record=nil end
      end
      if record then parts[#parts+1]=record.text end
    end
    count=count+1
    if sliced and (count%48==0 or debugprofilestop and debugprofilestop()-since>=1.5) then
      coroutine.yield()
      if scope~=market() then wanted=true;return end
      since=debugprofilestop and debugprofilestop() or 0
    end
  end
  local events=ForeverMarketActivity and ForeverMarketActivity.events or {}
  local activity={}
  for i=1,#events do
    local e=ForeverMarketDesktopEvent and ForeverMarketDesktopEvent(events[i])
    if e then activity[#activity+1]=json(e) end
    if sliced and (i%32==0 or debugprofilestop and debugprofilestop()-since>=1.5) then
      coroutine.yield()
      if scope~=market() then wanted=true;return end
      since=debugprofilestop and debugprofilestop() or 0
    end
  end
  local meta=json({version=1,realm=ForeverMarketDesktopRealm and ForeverMarketDesktopRealm(GetRealmName(),GetCurrentRegion(),UnitFactionGroup('player')) or GetRealmName(),faction=UnitFactionGroup('player'),region=GetCurrentRegion(),exportedAt=time(),gold=GetMoney()})
  ForeverMarketExport=table.concat({meta:sub(1,-2),',"activity":[',table.concat(activity,','),'],"rows":[',table.concat(parts,','),']}'})
  if announce then print('Forever Market: export ready. Type /reload to save it for the desktop app.');announce=nil end
end
local f=CreateFrame('Frame')
local function pump()
  if not worker then
    if not wanted then return end
    wanted=nil;worker=coroutine.create(function()assemble(true)end)
  end
  local ok,why=coroutine.resume(worker)
  if not ok then print('Forever Market export: '..tostring(why)) end
  if not ok or coroutine.status(worker)=='dead' then worker=nil end
  if not worker and not wanted then f:SetScript('OnUpdate',nil) end
end
local function export(quiet)
  wanted=true;if not quiet then announce=true end
  f:SetScript('OnUpdate',pump)
end
f:RegisterEvent('PLAYER_LOGIN');f:RegisterEvent('AUCTION_HOUSE_CLOSED');f:RegisterEvent('PLAYER_LOGOUT')
f:SetScript('OnEvent',function(_,event)
  if event=='PLAYER_LOGIN' then ForeverMarketMigrate()
  elseif event=='AUCTION_HOUSE_CLOSED' then export(true)
  elseif event=='PLAYER_LOGOUT' then assemble(false) end
end)
SLASH_FOREVERMARKET1='/fm'
local commandHelp={
  {'/fm, /fm dash, /fm dashboard','Open your dashboard and settings.'},
  {'/fm help, /fm commands','Show this command list.'},
  {'/fm tools, /fm home','Open the market tools hub.'},
  {'/fm analytics','View your market analytics.'},
  {'/fm farm','Track a farming route and compare its hourly returns.'},
  {'/fm scan','Start a market price scan at the auction house.'},
  {'/fm scanstatus','Print progress and filtering details for the latest Buy scan.'},
  {'/fm results','Open market results.'},
  {'/fm trials','Review scan trials.'},
  {'/fm watch','Manage watched items.'},
  {'/fm watchreport','Print recent Watch, Radar and benchmark results.'},
  {'/fm manage','Manage your auctions while the auction house is open.'},
  {'/fm preview','Preview your posting plan.'},
  {'/fm session','Open your selling session.'},
  {'/fm bags, /fm bags on, /fm bags off','Enable bag markers, or use off to disable them.'},
  {'/fm benchmark [gold]','Run a benchmark in Market Buy with your fund or a test budget of 1, 5 or 50 gold.'},
  {'/fm benchlist','Open the saved benchmark item list for import.'},
  {'/fm export','Prepare market data for the desktop app.'},
  {'/fm sync, /fm sync on, /fm sync off','Show live desktop sync status, or turn sync on or off.'},
  {'/fm status','Show auction activity tracking status.'},
  {'/fm version','Show addon version information.'},
}
SlashCmdList.FOREVERMARKET=function(msg)
  msg=(msg or ''):lower():match('^%s*(.-)%s*$')
  if msg=='' or msg=='dash' or msg=='dashboard' then ForeverMarketTools.openDashboard()
  elseif msg=='help' or msg=='commands' then
    print('|cffffd100Forever Market commands|r')
    for _,entry in ipairs(commandHelp) do
      print('|cffffd100'..entry[1]..'|r - '..entry[2])
    end
  elseif msg=='analytics' then ForeverMarketTools.openAnalytics()
  elseif msg=='preview' and ForeverMarketTools.openTools then ForeverMarketTools.openTools('Preview')
  elseif msg=='version' and ForeverMarketVersionStatus then ForeverMarketVersionStatus()
  elseif msg=='manage' and ForeverMarketTools and ForeverMarketTools.openManager and AuctionHouseFrame and AuctionHouseFrame:IsShown() then ForeverMarketTools.openManager()
  elseif msg=='watch' then ForeverMarketTools.openTools('Watches')
  elseif msg=='session' then ForeverMarketTools.openTools('Sell session')
  elseif msg=='trials' then ForeverMarketTools.openTools('Scan results')
  elseif msg=='results' and ForeverMarketTools.openTools then ForeverMarketTools.openTools('Results')
  elseif (msg=='tools' or msg=='home') and ForeverMarketTools.openTools then ForeverMarketTools.openTools('Home')
  elseif msg=='farm' and ForeverMarketTools.openTools then ForeverMarketTools.openTools('Farming')
  elseif msg=='scan' and ForeverMarketScan then ForeverMarketScan()
  elseif msg=='export' then export(false)
  elseif msg:match('^benchmark %d+$') then
    local g=tonumber(msg:match('%d+'))
    if ForeverMarketBenchmark and (g==1 or g==5 or g==50) then ForeverMarketBenchmark(g) else print('Open Market Buy, then use /fm benchmark 1, 5 or 50.') end
  elseif msg=='benchmark' then
    if ForeverMarketBenchmark then ForeverMarketBenchmark() else print('Open Market Buy to run the live benchmark.') end
  elseif msg=='benchlist' and ForeverMarketTools.openTools then
    local sets=ForeverMarketDB and ForeverMarketDB.benchSets or {}
    local ids=sets[ForeverMarketVenueRealm()..'|'..UnitFactionGroup('player')]
    if ids then
      local terms={}
      for _,id in ipairs(ids) do local name=C_Item.GetItemNameByID(id)
        if not name then print('Item names are still loading. Try again.');return end
        terms[#terms+1]='"'..name..'"'
      end
      ForeverMarketTools.openTools('Import',table.concat(terms,'\n'))
    else print('Run /fm benchmark with 50 eligible items first.') end
  elseif msg=='watchreport' then
    local runs=ForeverMarketDB and ForeverMarketDB.watchRuns or {}
    if #runs==0 then print('Forever Market: no completed Watch or Radar passes yet.') end
    for i=math.max(1,#runs-4),#runs do local r=runs[i]
      print(('%s / %s / %ds / first deal %s / %d checked / %d unanswered'):format(r.mode,r.scope,r.elapsed,r.first and ('%.1fs'):format(r.first) or 'none',r.checked,r.unanswered))
      if r.mode=='Benchmark' then
        local found=0;for _ in pairs(r.hits or {}) do found=found+1 end
        print(('Sample %d / verified deal IDs %d / %d detail requests'):format(r.size or 0,found,r.requests or 0))
      end
    end
  elseif msg=='scanstatus' then
    local r=ForeverMarketDB and ForeverMarketDB.lastBuyScan
    if not r then print('Forever Market: no Buy scan recorded yet.');return end
    print(('Forever Market: %s · %s · %ds · %g%% target'):format(r.source,r.state or 'starting',r.elapsed or 0,r.target/100))
    print(('%d eligible · %d screened · %d detail requests · %d checked · %d unanswered'):format(r.candidates or 0,r.screened or 0,r.detailRequests or 0,r.checked or 0,r.unanswered or 0))
    print('Market: '..ForeverMarketVenueRealm()..' / '..UnitFactionGroup('player')..' / '..(r.firstBuy and ('first deal '..math.floor(r.firstBuy)..'s') or 'no verified deal recorded'))
    print(('Short history %d / no supply %d / over budget %d / spread %d'):format(r.thinHistory or 0,r.noSupply or 0,r.overBudget or 0,r.weakSpread or 0))
    if r.repostExample then local e=r.repostExample;print('Resale check: '..(C_Item.GetItemNameByID(e.id) or tostring(e.id))..' / '..e.reason) end
    for _,miss in ipairs(r.misses or {}) do print('Near miss: '..(C_Item.GetItemNameByID(math.abs(miss.id)) or tostring(miss.id))..' / '..miss.reason) end
    if r.snapshotStatus then print('Snapshot: '..r.snapshotStatus) end
    if r.state=='closed' then print('Window closed before completion. Resume in Market Buy during this session.')
    elseif r.state=='complete' and not r.firstBuy then print('Completed with no qualifying purchase. Unanswered checks are excluded.') end
    if r.item then print('Current item ID: '..r.item) end
  elseif (msg=='sync' or msg=='sync on' or msg=='sync off') and ForeverMarketLiveSync then
    local enabled
    if msg~='sync' then enabled=msg=='sync on' end
    print('Forever Market: live desktop sync '..(ForeverMarketLiveSync(enabled) and 'on' or 'off')..'. Use /fm sync on or /fm sync off.')
  elseif msg=='status' and ForeverMarketActivityStatus then ForeverMarketActivityStatus()
  elseif msg=='bags' or msg=='bags on' or msg=='bags off' then
    if ForeverMarketBagToggle then ForeverMarketBagToggle(msg~='bags off')
    else print('Forever Market: bag module unavailable. Check startup messages.') end
  else print('Forever Market: command unavailable. Type /fm help for the command list.') end
end
