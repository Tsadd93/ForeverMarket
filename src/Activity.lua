local GetRealmName=ForeverMarketVenueRealm or function() return _G.GetRealmName and _G.GetRealmName() or '' end
-- Observes confirmations only; never submits an auction, bid or mail operation.
if ForeverMarketActivityLoaded then return end
ForeverMarketActivityLoaded=true
local f=CreateFrame('Frame')
local pendingBuy,pendingPost,sellItem,mailTake
local received={}
local ah,mail,attached=false,false,false
local cells,strip={},nil
local cursor,elapsed,wake=0,0,0
-- Older dashboard releases do not accept expired-mail events.
local function desktopEvent(e)
  local realm=ForeverMarketDesktopRealm and ForeverMarketDesktopRealm(e.realm,e.region,e.faction)
  if not realm or realm==e.realm then return e end
  local copy={};for k,v in pairs(e) do copy[k]=v end
  copy.realm=realm;return copy
end
function ForeverMarketDesktopEvents()
  local exported={}
  for _,e in ipairs(ForeverMarketActivity and ForeverMarketActivity.events or {}) do
    if e.kind~='auction_expired' then exported[#exported+1]=desktopEvent(e) end
  end
  return exported
end
local function record(kind,data)
  local db=ForeverMarketActivity
  if not db then return end
  db.sequence=db.sequence+1
  local e=data or {}
  e.id=db.install..':'..db.sequence; e.kind=kind; e.at=time()
  e.character=UnitName('player'); e.realm=GetRealmName(); e.faction=UnitFactionGroup('player'); e.region=GetCurrentRegion()
  e.gold=GetMoney()
  db.events[#db.events+1]=e
  if ForeverMarketFundActivity then ForeverMarketFundActivity(kind,e); e.tradingCash=ForeverMarketFundCash() end
  if ForeverMarketTools then ForeverMarketTools.onActivity(kind,e) end
  cursor=#db.events-1; wake=GetTime()+12
end
function ForeverMarketItemBought(p)
  record('purchase',{itemId=p.id,name=p.name,quantity=1,total=p.total,auctionId=p.auctionID})
end
function ForeverMarketSellDiagnostic(message) record('session',{name='Market Sell: '..tostring(message):sub(1,240)}) end
local function item(link) return link and tonumber(link:match('item:(%d+)')) end
local function invoice(index)
  if not GetInboxInvoiceInfo then return end
  local typ,name,who,bid,buyout,deposit,fee,delay,hh,mm,count=GetInboxInvoiceInfo(index)
  if not typ then return end
  local _,_,_,subject,money=GetInboxHeaderInfo(index)
  return {invoiceType=typ,name=name,quantity=count,total=bid,buyout=buyout,deposit=deposit,fee=fee,
    amount=money,subject=subject,delay=delay}
end
local seenMail={}
local function requestItem(index,attachment)
  if not GetInboxItem then return end
  local name,id,_,count=GetInboxItem(index,attachment or 1)
  local getCount=C_Item and C_Item.GetItemCount or GetItemCount
  if not id or not count or count<1 or not getCount then return end
  local e=invoice(index)
  if not e or e.invoiceType~='buyer' then return end
  local key=index..':'..(attachment or 1)
  if received[key] and received[key].expires>=GetTime() then return end
  received[key]={name=name,itemId=id,quantity=count,before=getCount(id),expires=GetTime()+10}
  record('item_collection_requested',{name=name,itemId=id,quantity=count})
end
local function settleMoney()
  local b=mailTake
  if not b then return end
  if GetTime()>b.expires then mailTake=nil;return end
  local delta=GetMoney()-b.before
  if delta==0 then return end
  local sum=0
  for i,e in ipairs(b.entries) do
    sum=sum+e.amount
    if sum==delta then
      for j=1,i do
        local entry=table.remove(b.entries,1)
        local copy={};for k,v in pairs(entry) do copy[k]=v end
        record('proceeds_collected',copy)
      end
      b.before=GetMoney()
      if #b.entries==0 then mailTake=nil end
      return
    end
  end
  mailTake=nil
end
local function requestMoney(index)
  local e=invoice(index)
  if not e or (e.amount or 0)<=0 then return end
  if ForeverMarketTools then e.mailRevision=ForeverMarketTools.account().mailRevision end
  settleMoney()
  local wallet=GetMoney()
  if not mailTake or GetTime()>mailTake.expires or mailTake.before~=wallet then
    mailTake={entries={},before=wallet,expires=GetTime()+10}
  end
  for _,p in ipairs(mailTake.entries) do
    if p.mailIndex==index and p.mailRevision==e.mailRevision and p.name==e.name and p.amount==e.amount then return end
  end
  e.mailIndex=index;mailTake.expires=GetTime()+10
  mailTake.entries[#mailTake.entries+1]=e
  record('collection_requested',e)
end
local function readMail()
  if not mail or not GetInboxNumItems then return end
  local occurrences={}
  local sellerMail={}
  local returned={}
  local expiredPattern=AUCTION_EXPIRED_MAIL_SUBJECT and AUCTION_EXPIRED_MAIL_SUBJECT:gsub('([%.%+%-%*%?%[%]%(%)%^%$])','%%%1'):gsub('%%s','(.+)')
  local loaded,total=GetInboxNumItems()
  for i=1,loaded do
    local e=invoice(i)
    if not e and expiredPattern and GetInboxItem then
      local _,_,_,subject=GetInboxHeaderInfo(i)
      local itemName,id,_,quantity=GetInboxItem(i,1)
      if id and quantity and subject and subject:match('^'..expiredPattern..'$') then
        local key=id..'/'..quantity;returned[key]=(returned[key] or 0)+1
        if ForeverMarketTools then
          local old=ForeverMarketTools.account().returns or {}
          if returned[key]>(old[key] or 0) then record('auction_expired',{itemId=id,name=itemName,quantity=quantity}) end
        end
      end
    end
    if e then
      -- An observation, not a second purchase or realized sale. Classic mail has no stable ID.
      if e.invoiceType=='seller' and (e.amount or 0)>0 then
        sellerMail[#sellerMail+1]={key=table.concat({e.name or '',e.amount,e.quantity or 0},'/'),name=e.name,amount=e.amount,qty=e.quantity}
      end
      local sig=ForeverMarketJSON(e)
      occurrences[sig]=(occurrences[sig] or 0)+1
      local key=sig..':'..occurrences[sig]
      if not seenMail[key] then seenMail[key]=true; record('invoice_observed',e) end
    end
  end
  if ForeverMarketTools then ForeverMarketTools.mailSnapshot(sellerMail);ForeverMarketTools.account().mailPartial=total and total>loaded;ForeverMarketTools.account().returns=returned end
end
local function readSellSlot()
  if not GetAuctionSellItemInfo then return nil end
  local name=GetAuctionSellItemInfo()
  if name then return {name=name,itemId=item(GetAuctionSellItemLink and GetAuctionSellItemLink())} end
end
function ForeverMarketPriceDepth(levels)
  local prices,volume={},0
  for price,qty in pairs(levels) do prices[#prices+1]=price;volume=volume+qty end
  table.sort(prices)
  local low=prices[1]
  if not low then return end
  local floorPrice,below=low,0
  for i=2,#prices do
    below=below+levels[prices[i-1]]
    if below>5 or below>volume*.05 then break end
    local p=prices[i]
    if p>=prices[i-1]*1.25 and levels[p]>=math.max(10,below*5) then floorPrice=p;break end
  end
  return {low=low,lowQty=levels[low],floorPrice=floorPrice,floorQty=levels[floorPrice],nextPrice=prices[2],nextQty=prices[2] and levels[prices[2]]}
end
local function captureDepth(id)
  local api=C_AuctionHouse
  if not ah or type(id)~='number' or not api or not api.GetNumCommoditySearchResults then return end
  local levels={}
  for i=1,api.GetNumCommoditySearchResults(id) do
    local r=api.GetCommoditySearchResultInfo(id,i)
    if r and r.unitPrice and r.quantity and r.unitPrice>0 and r.quantity>0 then
      levels[r.unitPrice]=(levels[r.unitPrice] or 0)+r.quantity
    end
  end
  local d=ForeverMarketPriceDepth(levels)
  if not d then return end
  local market=GetRealmName()..'|'..UnitFactionGroup('player')
  ForeverMarketDB.__depth=ForeverMarketDB.__depth or {}
  local all=ForeverMarketDB.__depth
  all[market]=all[market] or {}
  local prev=all[market][id]
  if prev and time()-prev.at<60 and prev.low==d.low and prev.lowQty==d.lowQty and prev.floorPrice==d.floorPrice and prev.floorQty==d.floorQty and prev.nextPrice==d.nextPrice and prev.nextQty==d.nextQty and not ForeverMarketTools then return end
  if ForeverMarketTools then
    if api.HasFullCommoditySearchResults and not api.HasFullCommoditySearchResults(id) then return end
    d.levels=ForeverMarketTools.levels(levels)
    if prev and time()-prev.at<60 and prev.levels and #d.levels==#prev.levels then
      local same=true
      for i,t in ipairs(d.levels) do if t[1]~=prev.levels[i][1] or t[2]~=prev.levels[i][2] then same=false;break end end
      if same then return end
    end
  end
  d.itemId=id;d.at=time();all[market][id]=d
  if ForeverMarketObserve and (not api.HasFullCommoditySearchResults or api.HasFullCommoditySearchResults(id)) then
    local total=0;for _,qty in pairs(levels) do total=total+qty end
    ForeverMarketObserve(tostring(id),d.low,total,d.floorPrice)
  end
  local event={}
  for key,value in pairs(d) do if key~='levels' then event[key]=value end end
  record('price_depth',event)
end
local function attach()
  if attached then return end
  attached=true
  local api=C_AuctionHouse
  if api then
    local function observe(method,fn)
      if type(api[method])=='function' then hooksecurefunc(api,method,fn) end
    end
    observe('StartCommoditiesPurchase',function(id,quantity)
      f.marketQuote={id=id,quantity=quantity}
    end)
    observe('ConfirmCommoditiesPurchase',function(id,quantity)
      local q=f.marketQuote
      f.marketBuy={itemId=id,quantity=quantity,total=q and q.id==id and q.quantity==quantity and q.total or nil}
      f.marketQuote=nil
    end)
    local function posted(location,duration,quantity,total,bid,commodity)
      local ok,id=pcall(C_Item.GetItemID,location)
      local calc=commodity and api.CalculateCommodityDeposit or api.CalculateItemDeposit
      local depOK,dep=pcall(calc,commodity and id or location,duration,quantity)
      if ForeverMarketFundPost and ok and id and quantity and quantity>0 and total and total>0 and depOK and dep then
        local holding=commodity and id
        if not commodity and api.GetItemKeyFromItem and C_Item.GetItemLink then
          local keyOK,k=pcall(api.GetItemKeyFromItem,location)
          local linkOK,link=pcall(C_Item.GetItemLink,location)
          if keyOK and linkOK then holding=ForeverMarketVariant(k,link) end
        end
        if holding then ForeverMarketFundPost(holding,quantity,total/quantity,dep,id) end
      end
      f.marketPost={deposit=depOK and dep or nil,itemId=ok and id or nil,quantity=quantity,total=total,bid=bid,duration=duration}
    end
    observe('PostCommodity',function(loc,duration,qty,price) posted(loc,duration,qty,qty*price,nil,true) end)
    observe('PostItem',function(loc,duration,qty,bid,total) posted(loc,duration,qty,total,bid) end)
  end
  if PlaceAuctionBid then hooksecurefunc('PlaceAuctionBid',function(list,index,amount)
    if list~='list' then return end
    local name,_,count,_,_,_,_,_,_,buyout,_,_,_,_,_,_,id=GetAuctionItemInfo(list,index)
    pendingBuy={kind=buyout and buyout>0 and amount==buyout and 'purchase' or 'bid',
      name=name,itemId=id,quantity=count,total=amount,expires=GetTime()+15}
  end) end
  if PostAuction then hooksecurefunc('PostAuction',function(bid,buyout,duration,size,stacks)
    local cached=readSellSlot() or sellItem or {}
    local deposit
    if GetAuctionDeposit then local ok,value=pcall(GetAuctionDeposit,duration,bid,buyout,size,1);if ok and type(value)=='number' then deposit=value end end
    pendingPost={name=cached.name,itemId=cached.itemId,quantity=size,total=buyout,bid=bid,
      deposit=deposit,duration=duration,remaining=stacks or 1,expires=GetTime()+120}
  end) end
  if TakeInboxMoney then hooksecurefunc('TakeInboxMoney',requestMoney) end
  if TakeInboxItem then hooksecurefunc('TakeInboxItem',requestItem) end
  if AutoLootMailItem then hooksecurefunc('AutoLootMailItem',function(index)
    requestMoney(index)
    for attachment=1,(ATTACHMENTS_MAX_RECEIVE or 16) do requestItem(index,attachment) end
  end) end
end
local function draw(e)
  local payload=ForeverMarketJSON(desktopEvent(e))
  if #payload>760 then return end
  if not strip then
    strip=CreateFrame('Frame',nil,UIParent)
    strip:SetFrameStrata('TOOLTIP'); strip:SetFrameLevel(1000)
    strip:SetPoint('TOPRIGHT',UIParent,'TOPRIGHT',0,0)
    strip:SetSize(128,18); strip:EnableMouse(false)
    for i=0,2303 do
      local t=strip:CreateTexture(nil,'OVERLAY');t:SetSize(1,1)
      t:SetPoint('TOPLEFT',strip,'TOPLEFT',i%128,-math.floor(i/128))
      cells[i+1]=t
    end
  end
  local width=GetPhysicalScreenSize and GetPhysicalScreenSize()
  strip:SetScale(width and width>0 and UIParent:GetWidth()/width or 1/UIParent:GetEffectiveScale())
  local a,b=0,0
  for i=1,#payload do a=(a+payload:byte(i))%255;b=(b+a)%255 end
  local bytes='FMA1'..string.char(math.floor(#payload/256),#payload%256,b,a)..payload
  local at=1
  for i=1,#bytes do
    local n=bytes:byte(i)
    for _,v in ipairs({math.floor(n/32),math.floor(n/4)%8,(n%4)*2}) do
      cells[at]:SetColorTexture(math.floor(v/4),math.floor(v/2)%2,v%2,1); at=at+1
    end
  end
  for i=at,#cells do cells[i]:SetColorTexture(0,0,0,0) end
  strip:Show()
end
local skipped={}
local function initialize()
    ForeverMarketDB=ForeverMarketDB or {}
    ForeverMarketActivity=ForeverMarketActivity or ForeverMarketDB.__activity or {sequence=0,events={},install=(UnitGUID('player') or UnitName('player'))..':'..time()}
    ForeverMarketDB.__activity=ForeverMarketActivity

end
function ForeverMarketLiveSync(enabled)
  initialize()
  if enabled~=nil then
    ForeverMarketDB.liveDesktopSync=enabled==true
    if enabled then record('session',{name='Live desktop sync enabled'})
    elseif strip then strip:Hide() end
  end
  return ForeverMarketDB.liveDesktopSync==true
end
function ForeverMarketActivityStatus()
  initialize()
  if not ForeverMarketLiveSync() then print('Forever Market: '..#ForeverMarketActivity.events..' events. Live desktop sync is off. /fm sync on enables it.');return end
  record('session',{name='Connection test'});wake=GetTime()+30
  print('|cff65dfc0Forever Market:|r '..#ForeverMarketActivity.events..' events. Sending connection test for 30 seconds.'..(#skipped>0 and (' Unsupported events: '..table.concat(skipped,', ')) or ''))
end
for _,ev in ipairs({'PLAYER_LOGIN','AUCTION_HOUSE_SHOW','AUCTION_HOUSE_CLOSED',
  'CHAT_MSG_SYSTEM','UI_ERROR_MESSAGE','MAIL_SHOW','MAIL_CLOSED','MAIL_INBOX_UPDATE','PLAYER_MONEY','PLAYER_LOGOUT','BAG_UPDATE_DELAYED'}) do if not pcall(f.RegisterEvent,f,ev) then skipped[#skipped+1]=ev end end
if C_AuctionHouse then
  for _,ev in ipairs({'COMMODITY_SEARCH_RESULTS_UPDATED','COMMODITY_PRICE_UPDATED','COMMODITY_PURCHASE_SUCCEEDED','COMMODITY_PURCHASE_FAILED','AUCTION_HOUSE_AUCTION_CREATED','AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION'}) do
    pcall(f.RegisterEvent,f,ev)
  end
end
f:SetScript('OnEvent',function(_,event,...)
  if event=='PLAYER_LOGIN' then
    initialize();record('session',{name='Activity tracking started'});attach()
  elseif event=='AUCTION_HOUSE_SHOW' then ah=true; record('wallet',{name='Auction house opened'})
  elseif event=='AUCTION_HOUSE_CLOSED' then ah=false;sellItem=nil;f.marketQuote=nil;f.marketBuy=nil;f.marketPost=nil
  elseif event=='COMMODITY_SEARCH_RESULTS_UPDATED' then captureDepth(...)
  elseif event=='COMMODITY_PRICE_UPDATED' and f.marketQuote then
    local _,total=...;f.marketQuote.total=total
  elseif event=='COMMODITY_PURCHASE_FAILED' then f.marketBuy=nil;f.marketQuote=nil
  elseif event=='COMMODITY_PURCHASE_SUCCEEDED' or event=='AUCTION_HOUSE_AUCTION_CREATED' then
    local posting=event=='AUCTION_HOUSE_AUCTION_CREATED'
    local field=posting and 'marketPost' or 'marketBuy'
    local e=f[field] or {};f[field]=nil
    if e.itemId then e.name=C_Item.GetItemNameByID and C_Item.GetItemNameByID(e.itemId) or ('Item '..e.itemId) end
    if posting then e.auctionId=... end
    record(posting and 'posted' or 'purchase',e)
  elseif event=='AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION' then
    local kind,text,id=...
    if Enum and Enum.AuctionHouseNotification and kind==Enum.AuctionHouseNotification.AuctionSold then
      record('sale_notice',{name=text,auctionId=id})
    end
  elseif event=='UI_ERROR_MESSAGE' then
    -- Never promote a request after an error or timeout.
    pendingBuy=nil;pendingPost=nil;received={};f.marketBuy=nil;f.marketPost=nil
  elseif event=='CHAT_MSG_SYSTEM' then
    local msg=...
    if msg==ERR_AUCTION_BID_PLACED and pendingBuy and pendingBuy.expires>=GetTime() then
      local e=pendingBuy;pendingBuy=nil;local kind=e.kind;e.kind=nil;e.expires=nil;record(kind,e)
    elseif msg==ERR_AUCTION_STARTED and pendingPost and pendingPost.expires>=GetTime() then
      local p=pendingPost
      record('posted',{name=p.name,itemId=p.itemId,quantity=p.quantity,total=p.total,bid=p.bid,duration=p.duration,deposit=p.deposit})
      p.remaining=p.remaining-1;if p.remaining<=0 then pendingPost=nil end
    elseif msg==ERR_AUCTION_REMOVED then record('cancel_confirmed',{name='Auction cancelled; item identity not supplied'})
    elseif ERR_AUCTION_SOLD_S and type(msg)=='string' then
      local prefix=ERR_AUCTION_SOLD_S:match('^(.-)%%s')
      if prefix and prefix~='' and msg:sub(1,#prefix)==prefix then record('sale_notice',{name=msg}) end
    end
  elseif event=='PLAYER_LOGOUT' then ForeverMarketActivityExport=ForeverMarketJSON(ForeverMarketDesktopEvents())
  elseif event=='MAIL_SHOW' then mail=true;readMail()
  elseif event=='MAIL_CLOSED' then settleMoney();mail=false;received={}
  elseif event=='BAG_UPDATE_DELAYED' then
    local getCount=C_Item and C_Item.GetItemCount or GetItemCount
    if getCount then
      -- Several stacks can arrive in one bag update. Confirm each request once
      -- only when the combined bag increase matches a recorded starting count.
      local groups={}
      for key,e in pairs(received) do
        if GetTime()>e.expires then received[key]=nil
        else
          local g=groups[e.itemId] or {items={},n=0,before=e.before};groups[e.itemId]=g
          g.items[key]=e;g.n=g.n+e.quantity;g.before=math.min(g.before,e.before)
        end
      end
      for id,g in pairs(groups) do
        if getCount(id)-g.before==g.n then
          for key,e in pairs(g.items) do
            record('purchased_item_received',{name=e.name,itemId=id,quantity=e.quantity});received[key]=nil
          end
        end
      end
    end
  elseif event=='MAIL_INBOX_UPDATE' then readMail()
  elseif event=='PLAYER_MONEY' then
    settleMoney()
    if ah or mail then record('wallet',{name='Wallet balance changed'}) end
  end
end)
f:SetScript('OnUpdate',function(_,dt)
  elapsed=elapsed+dt;if elapsed<0.5 then return end;elapsed=0
  if ah then sellItem=readSellSlot() end
  local db=ForeverMarketActivity
  if ForeverMarketDB and ForeverMarketDB.liveDesktopSync==true and db and #db.events>0 and (ah or mail or GetTime()<wake) then
    cursor=cursor%#db.events+1;if db.events[cursor].kind~='auction_expired' then draw(db.events[cursor]) end
  elseif strip then strip:Hide() end
end)
