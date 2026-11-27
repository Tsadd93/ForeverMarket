local M=ForeverMarketTools
local panel,summary,notice,qty,fee,loss,settings,mode,page
local rows={}
local list={}
local function money(n)
  if n==nil then return 'Unknown' end
  return (n<0 and '-' or '')..ForeverMarketCoins(math.abs(n))
end
local function text(p,x,y,w)
  local f=p:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
  f:SetPoint('TOPLEFT',x,y);f:SetWidth(w);f:SetJustifyH('LEFT');f:SetWordWrap(false);return f
end
local function button(p,x,y,w,label,fn)
  local b=CreateFrame('Button',nil,p,'UIPanelButtonTemplate');b:SetSize(w,22)
  b:SetPoint('TOPLEFT',x,y);b:SetText(label);b:SetScript('OnClick',fn);return b
end
local function input(p,x,y,w)
  local e=CreateFrame('EditBox',nil,p,'InputBoxTemplate');e:SetAutoFocus(false);e:SetSize(w,20);e:SetPoint('TOPLEFT',x,y);return e
end
local function quantity()
  local n=tonumber(qty:GetText())
  if n and n>=1 and n<=999 and n==math.floor(n) then return n end
end
local function render()
  if not panel or not panel:IsVisible() then return end
  local a=M.account();list={}
  local restock=mode=='Restock' and M.restockContext()
  if mode=='Materials' or mode=='Build list' then
    for id,n in pairs(M.materials()) do
      local need=M.missing(id,n)
      list[#list+1]={id=id,name=C_Item.GetItemNameByID(id) or ('Item '..id),info=need..' missing / '..n..' reserved',
        value=need==0 and 'Covered' or money(M.cost(id,need)),score=need}
    end
  end
  if mode~='Materials' then
    local n=quantity() or 1
    for key,r in pairs(a.recipes) do
      if mode~='Build list' or a.build[key] then
        local batches=mode=='Build list' and a.build[key] or n
        local explanation
        if restock then batches,explanation=M.restockCraft(r,restock) end
        local e,why
        if batches>0 then e,why=M.estimate(r,batches) end
        list[#list+1]={key=key,name=r.name,info=explanation or (e and money(e.cash) or why),
          value=e and money(e.profit) or '',score=e and e.profit*(M.salesWeight and M.salesWeight(r.name) or 1) or -math.huge,estimate=e,n=batches}
      end
    end
  end
  table.sort(list,function(a,b)
    if mode=='Build list' then
      if (a.id~=nil)~=(b.id~=nil) then return a.id~=nil end
      if a.id and b.id then return a.id<b.id end
    end
    if a.score~=b.score then return a.score>b.score end return a.name<b.name end)
  page=math.min(page,math.max(1,math.ceil(#list/#rows)))
  panel.page:SetText(page..' / '..math.max(1,math.ceil(#list/#rows)))
  for i,row in ipairs(rows) do
    local d=list[(page-1)*#rows+i];row.data=d;row.action:SetShown(d~=nil)
    row.name:SetText(d and ((d.key and (mode=='Build list' or mode=='Restock') and d.n..' x ' or '')..d.name) or '')
    row.info:SetText(d and d.info or '');row.value:SetText(d and d.value or '')
    if d then
      local q=M.quote
      local active=d.id and q and q.id==d.id and not q.direct
      row.offer=active and q or nil
      row.total=active and q.total or nil
      if active and q.total then
        row.value:SetText(money(q.total));row.info:SetText(('Buy %d / %d needed'):format(q.key and 1 or q.n,d.score))
      end
      if d.id then
        row.action:SetText(d.score==0 and 'Covered' or active and (q.total and 'Buy' or 'Checking') or 'Check')
        row.action:SetEnabled(d.score>0 and (not active or q.total~=nil) or false)
      else
        row.action:SetText(mode=='Build list' and 'Remove' or 'Add')
        row.action:SetEnabled(mode=='Build list' or d.estimate and d.estimate.extra>0 and d.estimate.profit>0 or false)
      end
    end
  end
  return #list
end
local function switch(nextMode)
  M.cancelMaterial();mode=nextMode;page=1
  local n=render()
  notice:SetText(n==0 and (mode=='Recipes' and 'Open a learned profession window to capture its recipes.' or 'Your build list is empty.') or mode=='Build list' and 'Check a missing reagent for a live total, then click Buy.' or '')
end
local function create()
  local ah=AuctionHouseFrame
  if panel or not ah then return end
  panel=CreateFrame('Frame',nil,ah);panel:SetPoint('TOPLEFT',20,-60);panel:SetPoint('BOTTOMRIGHT',-30,45);panel:Hide()
  mode='Recipes';page=1
  for i,m in ipairs({'Recipes','Build list','Materials'}) do button(panel,(i-1)*85,0,82,m,function() switch(m) end) end
  text(panel,263,-5,50):SetText('Crafts');qty=input(panel,307,0,38);qty:SetText('1');qty:SetScript('OnEnterPressed',function(self)self:ClearFocus();render()end)
  button(panel,352,0,70,'Refresh',function()
    if ForeverMarketSnapshot then ForeverMarketSnapshot() end
    qty:ClearFocus();render()
  end)
  text(panel,4,-34,78):SetText('AH cut %');fee=input(panel,75,-30,40)
  text(panel,130,-34,155):SetText('Lost deposit (c per item)');loss=input(panel,284,-30,48)
  button(panel,342,-30,80,'Save fees',function()
    local f,l=tonumber(fee:GetText()),tonumber(loss:GetText())
    if not f or f<0 or math.floor(f*100+.5)>=10000 or not l or l<0 or l~=math.floor(l) or l>100000000 then notice:SetText('Enter a fee below 100% and a whole copper allowance.');return end
    local s=M.settings();s.cutBP=math.floor(f*100+.5);s.lostDepositPerUnit=l
    fee:ClearFocus();loss:ClearFocus();render();notice:SetText('Pricing settings saved.')
  end)
  button(panel,433,-30,160,'Use stored stock',function(self)
    local a=M.account();a.useTransfers=not a.useTransfers
    self:SetText(a.useTransfers and 'Use bag stock only' or 'Use stored stock');M.cancelMaterial();M.invalidate();render()
    notice:SetText(a.useTransfers and 'Shopping accounts for recently observed transferable stock. Collect it before crafting.' or 'Shop using current bag quantities.')
  end):SetText(M.account().useTransfers and 'Use bag stock only' or 'Use stored stock')
  button(panel,424,0,55,'Manage',function() if M.openManager then M.openManager() end end)
  button(panel,487,0,105,'Restock',function()switch('Restock')end)
  button(panel,599,0,58,'Plan',function()M.openTools('Supply plan')end)
  notice=text(panel,4,-58,650)
  ForeverMarketResults(panel,80,{{'Recipe / material',0},{'Missing materials',202},{'Profit / cost',447},{'Action',566}})
  for i=1,9 do
    local y=-108-(i-1)*23
    ForeverMarketRowArt(panel,y+5,657,i)
    local row={name=text(panel,6,y,192),info=text(panel,206,y,236),value=text(panel,451,y,109)}
    row.action=button(panel,568,y+4,83,'Add',function()
      local d=row.data;if not d then return end
      local pressed=row.pressed;row.pressed=nil
      if pressed and (pressed.id~=(d.id or d.key) or pressed.offer~=row.offer or pressed.total~=row.total) then
        notice:SetText('The row changed. Review the current offer.');return
      end
      if mode=='Recipes' or mode=='Restock' then
        local n=quantity()
        if mode=='Restock' then
          n=M.restockCraft(M.account().recipes[d.key],M.restockContext())
          if n~=d.n or n<=0 then render();notice:SetText('Stock or cost changed. Review the new quantity.');return end
        end
        if not n then notice:SetText('Enter 1 to 999 crafts.');return end
        local total=(M.account().build[d.key] or 0)+n
        local e,why=M.estimate(M.account().recipes[d.key],total)
        if not e or e.extra<=0 or e.profit<=0 or not M.queue(d.key,total) then notice:SetText(why or 'Batch exceeds supply, profit or quantity limit.');return end
        notice:SetText('Added to build list.')
      elseif d.key and mode=='Build list' then M.queue(d.key,0)
      else
        local ok,why
        if row.offer then
          if M.quote~=row.offer or not row.total or row.offer.total~=row.total then notice:SetText('Offer changed. Check again.');render();return end
          ok,why=M.confirmMaterial()
        else ok,why=M.startMaterial(d.id) end
        notice:SetText(why or 'Waiting for the auction house.')
      end
      render()
    end)
    row.action:SetScript('OnMouseDown',function()
      local d=row.data;row.pressed=d and {id=d.id or d.key,offer=row.offer,total=row.total}
    end)
    row.hover=CreateFrame('Frame',nil,panel)
    row.hover:SetPoint('TOPLEFT',3,y+3);row.hover:SetSize(554,21);row.hover:EnableMouse(true)
    row.hover:SetScript('OnEnter',function(frame)
      local d=row.data;if not d then return end
      GameTooltip:SetOwner(frame,'ANCHOR_RIGHT');GameTooltip:AddLine(d.name)
      if d.key then
        local r=M.account().recipes[d.key]
        GameTooltip:AddLine("Right-click to watch all reagent prices.")
        if d.estimate then
          local e=d.estimate
          if M.saleLabel then GameTooltip:AddLine(M.saleLabel(r.name)) end
          GameTooltip:AddDoubleLine('Post per unit',money(e.post))
          GameTooltip:AddDoubleLine('Minimum output',tostring(e.units))
          GameTooltip:AddDoubleLine('Buy every material',money(e.all))
          GameTooltip:AddDoubleLine('Buy finished output',money(M.cost(r.output,e.units)))
          GameTooltip:AddDoubleLine('Cash needed now',money(e.cash))
          GameTooltip:AddDoubleLine('Net proceeds if sold',money(e.net))
          GameTooltip:AddDoubleLine('Gain over selling materials',money(e.extra))
          GameTooltip:AddLine('Output price observed '..math.floor((time()-e.at)/60)..' min ago')
        else GameTooltip:AddLine(d.info) end
        for id,n in pairs(M.inputs(r,d.n) or r.materials) do
          GameTooltip:AddDoubleLine(C_Item.GetItemNameByID(id) or ('Item '..id),tostring(n*d.n))
        end
      else GameTooltip:AddLine(d.info);GameTooltip:AddLine(d.value)
        if M.explain then M.explain(GameTooltip,d.id) end
        if M.transferPlan then local plan=M.transferPlan(d.id,math.max(0,(M.materials()[d.id] or 0)-M.bagCount(d.id)-(M.account().transit[d.id] or 0)));GameTooltip:AddLine(plan,1,.85,.35,true) end
      end
      GameTooltip:Show()
    end)
    row.hover:SetScript('OnMouseUp',function(_,key)
      if key=='RightButton' and row.data and row.data.key then
        local recipe=M.account().recipes[row.data.key]
        if recipe and M.watchRecipe then notice:SetText(M.watchRecipe(recipe));M.openTools('Watches') end
      end
    end)
    row.hover:SetScript('OnLeave',function() GameTooltip:Hide() end)
    rows[i]=row
  end
  button(panel,8,-321,86,'Previous',function()page=math.max(1,page-1);render()end)
  panel.page=text(panel,101,-326,65)
  button(panel,170,-321,75,'Next',function()page=page+1;render()end)
  panel:SetScript('OnShow',function()
    local s=M.settings();fee:SetText(s.cutBP/100);loss:SetText(s.lostDepositPerUnit)
    if ForeverMarketSnapshot then ForeverMarketSnapshot() end
    switch(mode)
  end)
  panel:SetScript('OnHide',M.cancelMaterial)
  ForeverMarketTab('ForeverMarketCraft',panel,'Craft','Market Craft')
end
function M.openMaterials() create();mode='Materials';page=1;panel.selectTab();switch(mode) end
local function totals()
  local parent=AuctionHouseFrame and AuctionHouseFrame.AuctionsFrame
  if not parent or not parent:IsVisible() then return end
  if not summary then
    summary=parent:CreateFontString(nil,'OVERLAY','GameFontNormalSmall')
    summary:SetPoint('BOTTOMLEFT',AuctionHouseFrame,'BOTTOMLEFT',181,7);summary:SetPoint('BOTTOMRIGHT',AuctionHouseFrame,'BOTTOMRIGHT',-178,7);summary:SetJustifyH('CENTER');summary:SetWordWrap(false)
    if summary.SetMaxLines then summary:SetMaxLines(2) end;ForeverMarketTextHint(parent,summary)
  end
  local l,i,c,unknown,sold,estimate=M.saleTotals()
  local full=not C_AuctionHouse.HasFullOwnedAuctionResults or C_AuctionHouse.HasFullOwnedAuctionResults()
  local asOf=M.account().mailAsOf
  summary:SetText(('Listed %s   Sold (gross) %s%s\nSale mail %s%s   Collected today %s'):format(money(l),money(sold),full and '' or ' (partial)',asOf and (money(i)..' at '..date('%m/%d %H:%M',asOf)) or 'unknown',(M.account().mailPartial and ' (partial)' or '')..(estimate>0 and (' + est. '..money(estimate)..' pending') or '')..(unknown>0 and (' + '..unknown..' unpriced') or ''),money(c)))
end
local function readable(value)
  return not issecretvalue or not issecretvalue(value)
end
local function itemValues(tip,id,link,n,bound,k,variant)
  local key=k and ForeverMarketHistoryKey(k)
  local post,at,source,bulk=M.prices(id,key,variant)
  if not post and key and key~=tostring(id) then
    post,at,source,bulk=M.prices(id);source='Base item estimate'
  end
  local gear=variant and k and M.gearEvidence and M.gearEvidence(k,link)
  if gear and gear.exact and not bulk then
    post,at,source=gear.exact,gear.last.at,'Historical ask / matching suffix and level'
  end
  local _,_,_,_,_,_,_,_,_,_,vendor=C_Item.GetItemInfo(link or id)
  tip:AddDoubleLine('Forever Market',n and ('Each   /   Stack of '..n) or 'Per item',.4,1,.75,.85,.85,.85)
  local function line(label,each)
    tip:AddDoubleLine(label,money(each)..(n and ('   /   '..money(each*n)) or ''),1,1,1,1,1,1)
  end
  if post and not bound then
    if bulk then line('Observed bulk ask',bulk) end
    line(n and 'Post at' or 'AH estimate',post)
    tip:AddDoubleLine('After AH cut',money(ForeverMarketSaleNet(post))..(n and ('   /   '..money(ForeverMarketSaleNet(post*n))) or ''))
    tip:AddLine(source..'  |  '..math.floor((time()-at)/60)..' min ago',.7,.8,.8)
  else tip:AddLine(bound and 'Bound' or 'No auction price recorded for this item. Scan at the auction house.',.75,.75,.75,true) end
  if variant and k and M.gearEvidence then
    local g=gear
    if g and (g.exact or g.other) then
      if g.exact then
        line('Same suffix / median ask',g.exact)
        tip:AddLine(('%d observed days / %d listings last observed %s'):format(g.days,g.last.rows,date('%b %d',g.last.at)),.76,.72,.62,true)
      else tip:AddLine('No recent ask for this suffix and item level.',.76,.72,.62,true) end
      if g.other then tip:AddLine(('Other suffixes, middle range: %s to %s over %d days'):format(money(g.low),money(g.high),g.otherDays),.82,.78,.68,true) end
    end
  end
  if vendor then line('Vendor',vendor) end
  if (M.materials()[id] or 0)>0 then tip:AddLine('Reserved for crafting',1,.8,.2) end
  if M.valueLines then M.valueLines(tip,id,link) end
end
function M.tooltip(tip,bag,slot)
  local item=C_Container.GetContainerItemInfo(bag,slot)
  if not item or not readable(item.itemID) or not item.itemID or not readable(item.hyperlink) or not readable(item.stackCount) or not readable(item.isBound) then return end
  local loc=ItemLocation:CreateFromBagAndSlot(bag,slot)
  local k=C_AuctionHouse.GetItemKeyFromItem(loc)
  local variant=k and C_AuctionHouse.GetItemCommodityStatus(loc)==Enum.ItemCommodityStatus.Item and ForeverMarketVariant(k,item.hyperlink)
  local bound=item.isBound or C_Item.IsBound and C_Item.IsBound(loc)
  if not readable(bound) then return end
  itemValues(tip,item.itemID,item.hyperlink,item.stackCount or 1,bound,k,variant)
end
local function linkedValues(tip,data)
  if not tip or not tip.AddDoubleLine or tip.IsForbidden and tip:IsForbidden() then return end
  if data and issecrettable and issecrettable(data) then return end
  local info=tip.GetProcessingTooltipInfo and tip:GetProcessingTooltipInfo()
  if info and info.getterName=='GetBagItem' and info.getterArgs then
    local bag,slot=unpack(info.getterArgs)
    if readable(bag) and readable(slot) and type(bag)=='number' and type(slot)=='number' then M.tooltip(tip,bag,slot);return end
  end
  local link=data and data.hyperlink
  if not readable(link) then return end
  if not link and data and readable(data.guid) and data.guid and C_Item.GetItemLinkByGUID then link=C_Item.GetItemLinkByGUID(data.guid) end
  if not readable(link) then return end
  if not link and tip.GetItem then local _,v=tip:GetItem();link=v end
  if not readable(link) then return end
  local id=type(link)=='string' and tonumber(link:match('item:(%d+)')) or data and data.id
  if not readable(id) or type(id)~='number' or id<=0 then return end
  local bound,n
  if data and readable(data.guid) and data.guid and C_Item.GetItemLocationByGUID then
    local loc=C_Item.GetItemLocationByGUID(data.guid)
    if loc and (not loc.IsValid or loc:IsValid()) then
      bound=C_Item.IsBound and C_Item.IsBound(loc)
      n=C_Item.GetStackCount and C_Item.GetStackCount(loc)
      if not readable(n) or not readable(bound) then return end
    end
  end
  local _,_,_,_,_,_,_,_,equip=C_Item.GetItemInfo(link or id)
  local k,variant
  if link and equip and equip~='' and C_Item.GetDetailedItemLevelInfo then
    local lvl=C_Item.GetDetailedItemLevelInfo(link)
    if lvl then
      k={itemID=id,itemLevel=lvl,itemSuffix=tonumber(link:match('item:%d+:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:(%-?%d+)')) or 0}
      variant=ForeverMarketVariant(k,link)
    end
  end
  itemValues(tip,id,link,n,bound,k,variant)
end
function M.installItemTooltips()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item,linkedValues)
    return
  end
  for _,name in ipairs({'GameTooltip','ItemRefTooltip','ShoppingTooltip1','ShoppingTooltip2','ItemRefShoppingTooltip1','ItemRefShoppingTooltip2'}) do
    local tip=_G[name]
    if tip then
      if tip.HasScript and tip:HasScript('OnTooltipSetItem') then
        tip:HookScript('OnTooltipSetItem',function(self)
          local owner=self:GetOwner()
          if owner and owner.GetBagID and owner.GetID then
            local bag,slot=owner:GetBagID(),owner:GetID()
            if type(bag)=='number' and type(slot)=='number' and slot>0 then
              local _,link=self:GetItem()
              local item=C_Container.GetContainerItemInfo(bag,slot)
              if item and item.hyperlink==link then M.tooltip(self,bag,slot);return end
            end
          end
          linkedValues(self)
        end)
      else
        if tip.SetHyperlink then hooksecurefunc(tip,'SetHyperlink',function(self,link)if type(link)=='string' and link:find('item:',1,true) then linkedValues(self,{hyperlink=link}) end end) end
        if tip.SetBagItem then hooksecurefunc(tip,'SetBagItem',M.tooltip) end
      end
    end
  end
end
local events=CreateFrame('Frame')
for _,event in ipairs({'PLAYER_LOGIN','ITEM_SEARCH_RESULTS_UPDATED','ITEM_SEARCH_RESULTS_ADDED','AUCTION_HOUSE_SHOW','OWNED_AUCTIONS_UPDATED','TRADE_SKILL_SHOW','TRADE_SKILL_UPDATE','TRADE_SKILL_LIST_UPDATE','CRAFT_SHOW','CRAFT_UPDATE','UNIT_SPELLCAST_START','UNIT_SPELLCAST_SUCCEEDED','COMMODITY_PRICE_UPDATED','COMMODITY_SEARCH_RESULTS_UPDATED','COMMODITY_PRICE_UNAVAILABLE','BAG_UPDATE_DELAYED','COMMODITY_PURCHASE_SUCCEEDED','REPLICATE_ITEM_LIST_UPDATE'}) do pcall(events.RegisterEvent,events,event) end
local capture,craftCapture,lastBook,nextCheck
events:SetScript('OnEvent',function(_,event,arg,second,third)
  if event=='PLAYER_LOGIN' then
    M.settings();M.restoreCollected()
    M.installItemTooltips()
  elseif event=='AUCTION_HOUSE_SHOW' then
    create()
    local p=AuctionHouseFrame.AuctionsFrame
    if p and not p.foreverMarketSummary then p.foreverMarketSummary=true;p:HookScript('OnShow',function() if C_AuctionHouse.QueryOwnedAuctions then C_AuctionHouse.QueryOwnedAuctions({}) end;totals() end) end
  elseif event=='OWNED_AUCTIONS_UPDATED' then totals()
  elseif event=='TRADE_SKILL_SHOW' or event=='TRADE_SKILL_UPDATE' or event=='TRADE_SKILL_LIST_UPDATE' or event=='CRAFT_SHOW' or event=='CRAFT_UPDATE' then
    capture=GetTime()+.15;craftCapture=event=='CRAFT_SHOW' or event=='CRAFT_UPDATE'
  elseif event=='UNIT_SPELLCAST_START' and arg=='player' then M.startCast(third)
  elseif event=='UNIT_SPELLCAST_SUCCEEDED' and arg=='player' then M.completed(third)
  elseif (event=='ITEM_SEARCH_RESULTS_UPDATED' or event=='ITEM_SEARCH_RESULTS_ADDED') and M.quote and M.quote.key and arg and arg.itemID==M.quote.id and (arg.itemLevel or 0)==(M.quote.key.itemLevel or 0) and (arg.itemSuffix or 0)==(M.quote.key.itemSuffix or 0) and (arg.battlePetSpeciesID or 0)==(M.quote.key.battlePetSpeciesID or 0) then
    local r=M.materialOffer(arg)
    if r then M.quote.auctionID=r.auctionID;M.quote.total=r.buyoutAmount;notice:SetText('Live buyout '..money(r.buyoutAmount)..' for one. Review the purchase total.')
    else M.cancelMaterial();notice:SetText('No matching item at the expected price.') end
    render()
  elseif event=='COMMODITY_PRICE_UPDATED' and M.quote and not M.quote.key then
    local q=M.quote
    if second and second>0 and second<=q.max and GetTime()-q.at<9 then q.total=second;notice:SetText('Live total '..money(second)..' for '..q.n..'. Review the purchase total.')
    else
      M.cancelMaterial()
      local api=C_AuctionHouse
      if api.SendSearchQuery and (not api.IsThrottledMessageSystemReady or api.IsThrottledMessageSystemReady()) then
        api.SendSearchQuery(api.MakeItemKey(q.id),{},false)
      end
      notice:SetText('Price changed. Review the refreshed material cost.')
    end
    render()
  elseif event=='COMMODITY_SEARCH_RESULTS_UPDATED' then M.invalidate();render()
  elseif event=='COMMODITY_PRICE_UNAVAILABLE' then M.cancelMaterial();render()
  elseif event=='BAG_UPDATE_DELAYED' or event=='COMMODITY_PURCHASE_SUCCEEDED' then M.settleCrafts();M.invalidate();render() end
end)
events:SetScript('OnUpdate',function()
  if panel and panel:IsVisible() and (not nextCheck or GetTime()>=nextCheck) then
    nextCheck=GetTime()+1
    local book=ForeverMarketReadySnapshot and ForeverMarketReadySnapshot()
    if book~=lastBook then lastBook=book;M.invalidate();render() end
  end
  if capture and GetTime()>=capture then capture=nil;M.capture(craftCapture);render() end
  if M.quote and GetTime()-M.quote.at>=9 then M.cancelMaterial();render() end
end)
