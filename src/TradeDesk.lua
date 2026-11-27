local M=ForeverMarketTools
local function prefs()
  local a=M.account()
  a.desk=a.desk or {favorites={},searches={},posting={},groups={}}
  return a.desk
end
function M.postOptions(id)
  local base=prefs().posting[id] or {}
  local fields=M.operationFields and M.operationFields(id,prefs().groups[id])
  if fields then return {duration=fields.duration or base.duration,size=fields.size or base.size} end
  return base
end
function M.setPosting(id,size,duration)
  local opt=M.postOptions(id)
  opt.size=size;opt.duration=duration
  prefs().posting[id]=opt
end
function M.goldInput(s)
  s=(s or ''):lower():gsub('%s','')
  if s=='' then return 0 end
  if #s>18 then return end
  if s:match('^%d+%.?%d*$') then local value=tonumber(s)*10000;if value<=1e10 then return math.floor(value+.5) end;return end
  local n,found=0,{}
  while #s>0 do
    local digits,unit,rest=s:match('^(%d+)([gsc])(.*)$')
    if not digits or found[unit] then return end
    found[unit]=true;n=n+tonumber(digits)*({g=10000,s=100,c=1})[unit];s=rest
  end
  return n<=1e10 and n or nil
end
local function inventoryScope()
  local id=GetRealmID and GetRealmID()
  if not id or id<=0 then id=(UnitGUID('player') or ''):match('^Player%-(%d+)%-') or GetRealmName() end
  return table.concat({GetCurrentRegion(),id,UnitFactionGroup('player')},'|')
end
M.inventoryScope=inventoryScope
local function saveStock(where,items)
  local a=M.account()
  a.stockScope=inventoryScope();a.stockName=UnitName('player');a.stock=a.stock or {}
  local n,realm
  if UnitFullName then n,realm=UnitFullName('player') end
  a.stockAddress=n and realm and realm~='' and (n..'-'..realm) or a.stockName
  a.stock[where]={items=items,at=time()}
end
local function bags(first,last)
  local items={}
  for bag=first,last do
    for i=1,C_Container.GetContainerNumSlots(bag) do
      local r=C_Container.GetContainerItemInfo(bag,i)
      if r and r.itemID and not r.isBound then items[r.itemID]=(items[r.itemID] or 0)+(r.stackCount or 1) end
    end
  end
  return items
end
local bank,mail,ah=false,false,false
local function capture()
  local last=NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
  saveStock('bags',bags(0,last))
  if bank then
    local main=bags(-1,-1)
    for id,n in pairs(bags(last+1,last+(NUM_BANKBAGSLOTS or 7))) do main[id]=(main[id] or 0)+n end
    saveStock('bank',main)
  end
end
local events=CreateFrame('Frame')
for _,e in ipairs({'GET_ITEM_INFO_RECEIVED','PLAYER_ENTERING_WORLD','BAG_UPDATE_DELAYED','BANKFRAME_OPENED','BANKFRAME_CLOSED','MAIL_SHOW','MAIL_CLOSED','MAIL_INBOX_UPDATE','AUCTION_HOUSE_SHOW','AUCTION_HOUSE_CLOSED','OWNED_AUCTIONS_UPDATED'}) do pcall(events.RegisterEvent,events,e) end
events:SetScript('OnEvent',function(_,e)
  if e=='GET_ITEM_INFO_RECEIVED' then M.refreshItems=true;return end
  if e=='BANKFRAME_CLOSED' then bank=false;return end
  if e=='MAIL_CLOSED' then mail=false;return end
  if e=='AUCTION_HOUSE_CLOSED' then ah=false;return end
  if e=='MAIL_SHOW' then mail=true;return end
  if e=='AUCTION_HOUSE_SHOW' then ah=true;return end
  if e=='MAIL_INBOX_UPDATE' and mail then
    local stock={}
    for i=1,GetInboxNumItems() do
      for j=1,(ATTACHMENTS_MAX_RECEIVE or 16) do
        local _,id,_,n=GetInboxItem(i,j)
        if id and n then stock[id]=(stock[id] or 0)+n end
      end
    end
    saveStock('mail',stock)
  elseif e=='OWNED_AUCTIONS_UPDATED' and ah then
    local stock={}
    for i=1,C_AuctionHouse.GetNumOwnedAuctions() do
      local r=C_AuctionHouse.GetOwnedAuctionInfo(i)
      if r and r.status==0 and r.itemKey then local id=r.itemKey.itemID;stock[id]=(stock[id] or 0)+r.quantity end
    end
    saveStock('auctions',stock)
  elseif e=='BAG_UPDATE_DELAYED' or e=='PLAYER_ENTERING_WORLD' or e=='BANKFRAME_OPENED' then
    if e=='BANKFRAME_OPENED' then bank=true end
    capture()
  end
end)
function M.sources(id)
  local list={}
  local scope=inventoryScope()
  for guid,a in pairs(ForeverMarketDB.characters or {}) do
    if scope==a.stockScope then
      for place,s in pairs(a.stock or {}) do
        local n=s.items[id]
        if n and n>0 then list[#list+1]={who=a.stockName,place=place,n=n,at=s.at,own=guid==UnitGUID('player')} end
      end
    end
  end
  table.sort(list,function(a,b)if a.who~=b.who then return a.who<b.who end return a.place<b.place end)
  return list
end
function M.transferPlan(id,need)
  local steps={}
  for _,s in ipairs(M.sources(id)) do
    if need>0 and (s.place=='bank' or (s.place=='bags' and not s.own)) and time()-s.at<=7*86400 then
      local take=math.min(need,s.n);need=need-take
      steps[#steps+1]=(s.own and 'Withdraw ' or 'Transfer ')..take..' from '..s.who..' ('..s.place..')'
    end
  end
  if need>0 then steps[#steps+1]='Buy '..need end
  return table.concat(steps,'; '),need
end
function M.favorite(id)
  return prefs().favorites[id]
end
function M.findOffers(filter,snap,results,startKey,batch)
  results=results or {}
  local visited=0
  local raw=(filter.term or ''):match('^%s*(.-)%s*$')
  local exact=tonumber(raw:match('item:(%d+)') or raw)
  local term=raw:lower()
  for id,b in next,snap and snap.books or {},startKey do
    local price=b.low
    if price and (not exact or id==exact) and (filter.max==0 or price<=filter.max) and (not filter.watch or M.favorite(id)) then
      local name,_,quality,ilvl,req,kind,sub,_,equip,_,vendor,classID,subClassID=C_Item.GetItemInfo(id)
      local categoryMatch=not filter.categories
      for _,f in ipairs(filter.categories or {}) do
        if classID==f.classID and (not f.subClassID or subClassID==f.subClassID) and (not f.inventoryType or C_Item.GetItemInventoryTypeByID(id)==f.inventoryType) then categoryMatch=true;break end
      end
      local slot=equip and _G[equip] or ''
      local text=((name or '')..' '..(kind or '')..' '..(sub or '')..' '..(slot or '')):lower()
      local matches=true
      for word in term:gmatch('%S+') do if not text:find(word,1,true) then matches=false;break end end
      if categoryMatch and (not filter.exactName or name and name:lower()==term)
        and (not filter.minLevel or req and req>=filter.minLevel)
        and (not filter.minItemLevel or ilvl and ilvl>=filter.minItemLevel)
        and (not filter.maxItemLevel or ilvl and ilvl<=filter.maxItemLevel)
        and (not filter.minPrice or price>=filter.minPrice)
        and (not filter.usable or equip and equip~="" and C_Item.IsEquippableItem and C_Item.IsEquippableItem(id) and C_Item.IsUsableItem and C_Item.IsUsableItem(id)) and (exact or matches) and (not filter.level or (req and req<=filter.level))
        and (not filter.quality or quality==filter.quality) and (not filter.vendor or vendor and vendor>price) then
        results[#results+1]={id=id,name=name or ('Item '..id),price=price,qty=b.lowQty,vendor=vendor}
      end
    end
    visited=visited+1
    if batch and visited>=batch then return results,id end
  end
  table.sort(results,function(a,b) if a.price~=b.price then return a.price<b.price end return a.id<b.id end)
  return results
end
function M.explain(tip,id,reason)
  if reason then tip:AddLine(reason,1,.85,.35,true) end
  local snap=ForeverMarketReadySnapshot and ForeverMarketReadySnapshot()
  local b=snap and snap.books[id]
  if b then
    tip:AddLine('Last scan: '..ForeverMarketCoins(b.low)..' x '..b.lowQty..' / bulk '..ForeverMarketCoins(b.floorPrice)..' x '..b.floorQty,1,1,1,true)
    tip:AddLine('Scan age: '..math.max(0,math.floor((GetTime()-snap.at)/60))..' min')
  end
  local avg=M.history(tostring(id));if avg then tip:AddLine('Average daily low: '..ForeverMarketCoins(avg)) end
  local name=C_Item.GetItemNameByID(id)
  if name and M.marketOutcomes then
    local sale=M.marketOutcomes(name)
    tip:AddLine(sale and sale.lastUnit and ('Last paid / unit '..ForeverMarketCoins(sale.lastUnit)..' / '..date('%b %d %H:%M',sale.lastPaid)) or 'No paid sale recorded here in 14 days.')
  end
  if name and M.saleLabel then tip:AddLine(M.saleLabel(name)) end
  for _,s in ipairs(M.sources(id)) do tip:AddLine(s.who..' / '..s.place..': '..s.n..' ('..date('%b %d %H:%M',s.at)..')') end
end
-- Item groups carry the same trading and posting policy across all members.
local function integer(n,max) return n and n>=0 and n<=max and n==math.floor(n) end
function M.applyGroup(spec)
  local craftPct,realmPct,reserve,postCap=0,0,0,0
  if spec:sub(1,5)=='FMG2;' then
    local base,c,r,k,p=spec:match('^FMG2;([^;]+;%d+;%d+;%d+;%d+;%d+;[123]);(%d+);(%d+);(%d+);(%d+)$')
    if not base then return end
    craftPct,realmPct,reserve,postCap=tonumber(c),tonumber(r),tonumber(k),tonumber(p)
    if not integer(craftPct,1000) or not integer(realmPct,1000) or not integer(reserve,9999) or not integer(postCap,9999) then return end
    spec='FMG1;'..base
  end
  local ids,keep,cap,margin,maxStock,size,duration=spec:match('^FMG1;([%d,]+);(%d+);(%d+);(%d+);(%d+);(%d+);([123])$')
  if not ids or #ids>8000 then return end
  keep,cap,margin,maxStock,size,duration=tonumber(keep),tonumber(cap),tonumber(margin),tonumber(maxStock),tonumber(size),tonumber(duration)
  if not integer(keep,9999) or not integer(cap,1e10) or not integer(margin,1000) or not integer(maxStock,9999) or not integer(size,9999) then return end
  local checked={}
  for token in (ids..','):gmatch('([^,]*),') do
    local id=tonumber(token);if not integer(id,2147483647) or id==0 then return end
    checked[id]=true
  end
  for id in pairs(checked) do
    prefs().groups[id]={margin=margin,stock=maxStock,cap=cap,craftPct=craftPct,realmPct=realmPct,reserve=reserve,postCap=postCap}
    M.setPosting(id,size>0 and size or nil,duration)
    if keep>0 then M.restockList()[id]={keep=keep,cap=cap} else M.restockList()[id]=nil end
    prefs().favorites[id]=true
  end
  M.invalidate();return true
end
function M.group(id) return prefs().groups[id] end

local panel,fields,rows,status,pager
local page,results,watch,vendor,searchIndex=1,{},false,false,0
local current,previousSnap,usable,scanKey,working,retryInfo
local function label(parent,x,y,w,caption)
  local t=parent:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
  t:SetWidth(w);t:SetPoint('TOPLEFT',x,y);t:SetJustifyH('LEFT');t:SetWordWrap(false);t:SetText(caption or '');return t
end
local function button(parent,x,y,w,caption,fn)
  local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate');b:SetSize(w,22);b:SetPoint('TOPLEFT',x,y);b:SetText(caption);b:SetScript('OnClick',fn);return b
end
local function input(x,y,w,caption)
  label(panel,x,y,w,caption)
  local e=CreateFrame('EditBox',nil,panel,'InputBoxTemplate');e:SetSize(w,21);e:SetPoint('TOPLEFT',x,y-17);e:SetAutoFocus(false);e:SetText('')
  return e
end
local function showResults()
  local pages=math.max(1,math.ceil(#results/#rows));page=math.max(1,math.min(page,pages))
  for i,row in ipairs(rows) do
    local r=results[(page-1)*#rows+i];row.data=r
    ForeverMarketSetItemText(row.name,r and r.name or '');row.price:SetText(r and ForeverMarketCoins(r.price)..' x '..r.qty or '')
    row.star:SetShown(r~=nil);row.shop:SetShown(r~=nil);row.star:SetText(r and M.favorite(r.id) and 'Unwatch' or 'Watch')
  end
  for _,row in ipairs(rows) do
    local q=M.quote;local active=q and q.direct and row.data and q.id==row.data.id
    row.shop:SetText(active and (q.total and 'Confirm' or 'Quoting') or 'Get quote')
    row.reviewed=active and q.total and q or nil;row.reviewedTotal=active and q.total or nil
    if active and q.total then
      ForeverMarketSetItemText(status,'Live offer: '..(q.link or row.data.name)..' x '..(q.key and 1 or q.n)..' / '..ForeverMarketCoins(q.total)..' total')
    end
  end
  pager:SetText(page..' / '..pages)
end
local function search()
  if M.quote and M.quote.direct then M.cancelMaterial() end
  local max=M.goldInput(fields.max:GetText())
  local lv,quality=fields.level:GetText(),fields.quality:GetText():lower()
  quality=({poor="0",common="1",uncommon="2",rare="3",epic="4",legendary="5"})[quality] or quality
  if not max or (lv~='' and not integer(tonumber(lv),100)) or (quality~='' and not integer(tonumber(quality),8)) then current=nil;scanKey=nil;results={};showResults();status:SetText('Check level, quality (0–8) and maximum price (e.g. 3g 20s).');return end
  current={term=fields.term:GetText(),max=max,level=tonumber(lv),quality=tonumber(quality),watch=watch,vendor=vendor,usable=usable}
  previousSnap=ForeverMarketSnapshot and ForeverMarketSnapshot()
  working,scanKey=M.findOffers(current,previousSnap,{},nil,120)
  results=scanKey and {} or working;retryInfo=GetTime()+5;M.refreshItems=nil;page=1;showResults()
  status:SetText(scanKey and 'Searching market snapshot...' or previousSnap and (#results..' matches / snapshot '..math.floor((GetTime()-previousSnap.at)/60)..' min old. Quote checks live supply.') or 'Waiting for market snapshot. Run Market Scan if replication is unavailable.')
end
function M.openDesk()
  if not panel then
    panel=CreateFrame('Frame',nil,AuctionHouseFrame,'BackdropTemplate');panel:SetPoint('TOPLEFT',14,-58);panel:SetPoint('BOTTOMRIGHT',-12,39)
    panel:SetFrameLevel(AuctionHouseFrame:GetFrameLevel()+50);panel:EnableMouse(true);panel:SetBackdrop({bgFile='Interface\\DialogFrame\\UI-DialogBox-Background-Dark'});panel:SetBackdropColor(.1,.09,.08,1)
    ForeverMarketPanelArt(panel)
    fields={qty=input(505,-48,54,'Buy qty'),term=input(12,-8,177,'Item, link or category'),level=input(202,-8,49,'Max lvl'),quality=input(259,-8,55,'Quality'),max=input(326,-8,94,'Max each')}
    fields.qty:SetText('1')
    fields.qty:SetScript('OnTextChanged',function(_,user)
      if user and M.quote and M.quote.direct then M.cancelMaterial();showResults();status:SetText('Quantity changed. Get a new quote.') end
    end)
    button(panel,253,-318,146,'Add filter to basket',function()
      search();if current and M.addBasketFilter then status:SetText(M.addBasketFilter(current,tonumber(fields.qty:GetText()))) end
    end)
    button(panel,430,-24,68,'Search',search)
    button(panel,502,-24,82,'Save search',function()
      search();if not current then return end
      local t=prefs().searches;t[#t+1]={fields.term:GetText(),fields.level:GetText(),fields.quality:GetText(),fields.max:GetText(),watch,vendor,usable}
      if #t>30 then table.remove(t,1) end;status:SetText('Search saved. Use Saved to cycle through your searches.')
    end)
    button(panel,588,-24,62,'Saved',function()
      local t=prefs().searches;if #t==0 then status:SetText('No saved searches yet.');return end
      searchIndex=searchIndex%#t+1;local v=t[searchIndex]
      for i,key in ipairs({'term','level','quality','max'}) do fields[key]:SetText(v[i]) end
      watch,vendor,usable=v[5],v[6],v[7];search()
    end)
    button(panel,10,-55,105,'Watchlist',function()watch=not watch;search();status:SetText(watch and 'Showing watched items' or 'Showing all items')end)
    button(panel,119,-55,125,'Below vendor',function()vendor=not vendor;search();status:SetText(vendor and 'Vendor deals / confirm the live price before buying.' or 'Vendor filter cleared')end)
    button(panel,248,-55,108,'Trade groups',function() M.openGroups() end)
    button(panel,361,-55,136,'Usable equipment',function()usable=not usable;search();status:SetText(usable and 'Only equipment the client marks usable.' or 'All equipment.')end)
    button(panel,580,-55,70,'Close',function()panel:Hide()end)
    rows={};for i=1,8 do
      local y=-114-(i-1)*25
      ForeverMarketRowArt(panel,y+5,626,i)
      local r={name=label(panel,12,y,235),price=label(panel,252,y,158)}
      r.star=button(panel,417,y+4,85,'Watch',function()local id=r.data.id;prefs().favorites[id]=not M.favorite(id) or nil;search()end)
      r.shop=button(panel,512,y+4,110,'Shop',function()
        local v=r.data;local q=M.quote
        if q and q.direct and q.id==v.id then
          if not q.total then status:SetText('Waiting for the live offer.');return end
          if tonumber(fields.qty:GetText())~=q.n then M.cancelMaterial();status:SetText('Quantity changed. Get a new quote.');return end
          if r.reviewed~=q or r.reviewedTotal~=q.total then showResults();return end
          local ok,why=M.confirmMaterial();status:SetText(ok and 'Purchase submitted.' or why);showResults();return
        end
        local n=tonumber(fields.qty:GetText())
        if not integer(n,9999) or n<1 then status:SetText('Enter a whole purchase quantity.');return end
        local info=C_AuctionHouse.GetItemKeyInfo(C_AuctionHouse.MakeItemKey(v.id))
        if info and not info.isCommodity and n~=1 then status:SetText('Select one individually listed item at a time.');return end
        local ok,why=M.startMaterial(v.id,{n=n,cap=v.price})
        status:SetText(ok and 'Checking live offer. Review the total, then confirm.' or why);showResults()
      end)
      local hit=CreateFrame('Frame',nil,panel);hit:SetPoint('TOPLEFT',10,y+4);hit:SetSize(395,23);hit:EnableMouse(true)
      hit:SetScript('OnEnter',function(self)if r.data then GameTooltip:SetOwner(self,'ANCHOR_RIGHT');GameTooltip:SetHyperlink('item:'..r.data.id);M.explain(GameTooltip,r.data.id);GameTooltip:AddLine("Right-click to set a price alert.")
        local n=tonumber(fields.qty:GetText())
        if n and n>=1 and n==math.floor(n) then
          local tiers={};local cost=M.cost(r.data.id,n,tiers)
          if cost then GameTooltip:AddLine('Observed purchase tiers: '..table.concat(tiers,' + '),1,.85,.35,true) end
        end
        GameTooltip:Show() end end)
      hit:SetScript('OnMouseUp',function(_,key)
        if key=='RightButton' and r.data then M.openTools('Watches',r.data.id) end
      end)
      hit:SetScript('OnLeave',function()GameTooltip:Hide()end);rows[i]=r
    end
    status=label(panel,12,-90,635);pager=label(panel,92,-323,72)
    button(panel,10,-318,75,'Previous',function()page=page-1;showResults()end);button(panel,164,-318,70,'Next',function()page=page+1;showResults()end)
    for _,e in pairs(fields) do e:SetScript('OnEnterPressed',function(self)self:ClearFocus();search()end) end
    local elapsed=0
    panel:SetScript('OnUpdate',function(_,dt)
      if scanKey and current then
        working,scanKey=M.findOffers(current,previousSnap,working,scanKey,120)
        if not scanKey then results=working;showResults();status:SetText(#results..' matches / quote checks live supply.') end
        return
      end
      elapsed=elapsed+dt;if elapsed<1 then return end;elapsed=0
      local snap=ForeverMarketReadySnapshot and ForeverMarketReadySnapshot()
      if snap and snap~=previousSnap and not M.quote then search()
      elseif snap and current and retryInfo and GetTime()>=retryInfo and M.refreshItems and not M.quote then
        retryInfo=nil;M.refreshItems=nil;working,scanKey=M.findOffers(current,snap,{},nil,120)
        if not scanKey then results=working;showResults() end
      else showResults() end
    end)
    hooksecurefunc(AuctionHouseFrame,'SetDisplayMode',function()panel:Hide()end)
    panel:HookScript('OnHide',function()if M.quote and M.quote.direct then M.cancelMaterial() end;if M.groupsPanel then M.groupsPanel:Hide() end end)
  end
  panel:Show();search()
end
function M.openOffer(id,cap)
  M.openDesk()
  fields.term:SetText(tostring(id));fields.max:SetText(cap..'c');fields.level:SetText('');fields.quality:SetText('');fields.qty:SetText('1')
  vendor=false;usable=false;watch=false;search()
end
function M.openVendorDeals()
  M.openDesk()
  fields.term:SetText('');fields.level:SetText('');fields.quality:SetText('');fields.max:SetText('')
  watch=false;usable=false;vendor=true;search()
end
function M.openGroups()
  if not M.groupsPanel then
    local p=CreateFrame('Frame',nil,panel,'BackdropTemplate');M.groupsPanel=p
    p:SetPoint('TOPLEFT',1,-4);p:SetPoint('BOTTOMRIGHT',-1,1);p:SetFrameLevel(panel:GetFrameLevel()+10);p:EnableMouse(true)
    p:SetBackdrop({bgFile='Interface\\DialogFrame\\UI-DialogBox-Background-Dark'});p:SetBackdropColor(.1,.09,.08,1)
    ForeverMarketPanelArt(p)
    local function field(x,y,w,title,default)
      label(p,x,y,w,title);local e=CreateFrame('EditBox',nil,p,'InputBoxTemplate')
      e:SetSize(w,21);e:SetPoint('TOPLEFT',x,y-20);e:SetAutoFocus(false);e:SetText(default);return e
    end
    local ids=field(16,-20,350,'Item IDs separated by commas','')
    local keep=field(16,-82,90,'Restock to','0');local cap=field(116,-82,110,'Max buy each','0')
    local margin=field(248,-82,96,'Min profit %','5');local stock=field(359,-82,100,'Stock cap','20')
    local size=field(16,-145,96,'Post quantity','0');local dur=field(126,-145,95,'Hours','12')
    local policy=field(387,-20,230,'Craft % / realm % / keep / listed cap','0/0/0/0')
    local presets={{'Leveling cloth','2589,2592,4306,4338,14047'},{'Classic raid supplies','13444,13446,13457,13452'}}
    local groupName=field(458,-82,145,'Group name','My group')
    local preset=0
    button(p,254,-161,185,'Choose a starter group',function(self)
      preset=preset%#presets+1;ids:SetText(presets[preset][2]);self:SetText(presets[preset][1])
    end)
    local code=field(16,-210,575,'Shared group','');local msg=label(p,16,-298,593)
    button(p,446,-161,146,'Load named group',function()
      local saved=prefs().savedGroups and prefs().savedGroups[groupName:GetText()]
      if not saved then msg:SetText('No saved group with that name.');return end
      local base,settings=saved:match('^FMG2;([^;]+;%d+;%d+;%d+;%d+;%d+;[123]);(.+)$')
      policy:SetText(settings and settings:gsub(';','/') or '0/0/0/0')
      local a,b,c,d,e,f,g=(base and ('FMG1;'..base) or saved):match('^FMG1;([^;]+);(%d+);(%d+);(%d+);(%d+);(%d+);([123])$')
      if not a then return end
      ids:SetText(a);keep:SetText(b);cap:SetText(c..'c');margin:SetText(d);stock:SetText(e);size:SetText(f);dur:SetText(({12,24,48})[tonumber(g)]);code:SetText(saved)
      msg:SetText('Loaded. Edit and apply to update these items.')
    end)
    local function remember(spec)
      local name=groupName:GetText():match('^%s*(.-)%s*$')
      if name~='' and #name<=60 then local p=prefs();p.savedGroups=p.savedGroups or {};p.savedGroups[name]=spec end
    end
    button(p,16,-260,110,'Apply & copy',function()
      local hours=({['12']=1,['24']=2,['48']=3})[dur:GetText()];local price=M.goldInput(cap:GetText())
      if not price or not hours then msg:SetText('Enter 12, 24, or 48 hours and a valid price.');return end
      local spec=table.concat({'FMG1',ids:GetText():gsub('%s',''),keep:GetText(),price,margin:GetText(),stock:GetText(),size:GetText(),hours},';')
      local c,r,k,p=policy:GetText():match('^%s*(%d+)%s*/%s*(%d+)%s*/%s*(%d+)%s*/%s*(%d+)%s*$')
      if not c then msg:SetText('Enter four whole numbers separated by /.');return end
      spec='FMG2;'..spec:sub(6)..';'..table.concat({c,r,k,p},';')
      if not M.applyGroup(spec) then msg:SetText('Check the item IDs and whole-number limits.');return end
      remember(spec);code:SetText(spec);code:SetFocus();code:HighlightText();msg:SetText('Applied. Copy selected text to share this group.')
    end)
    button(p,139,-260,105,'Import group',function()local spec=code:GetText();if M.applyGroup(spec) then remember(spec);msg:SetText('Applied to the listed items.') else msg:SetText('Invalid group.') end end)
    button(p,512,-260,80,'Back',function()p:Hide()end)
  end
  M.groupsPanel:Show()
end

