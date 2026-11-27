local M,api=ForeverMarketTools,C_AuctionHouse
local queue
local function owned(id)
  for i=1,api.GetNumOwnedAuctions() do
    local r=api.GetOwnedAuctionInfo(i)
    if r and r.auctionID==id then return r end
  end
end
local function completeOwned()
  return not api.HasFullOwnedAuctionResults or api.HasFullOwnedAuctionResults()
end
local function sameKey(a,b)
  return a and b and a.itemID==b.itemID and (a.itemLevel or 0)==(b.itemLevel or 0)
    and (a.itemSuffix or 0)==(b.itemSuffix or 0) and (a.battlePetSpeciesID or 0)==(b.battlePetSpeciesID or 0)
end
local function matching(row)
  local r=owned(row.id)
  return r and r.status==0 and not r.bidder and (r.bidAmount or 0)==0 and sameKey(r.itemKey,row.key)
    and r.quantity==row.qty and M.listingGross(r)==row.gross and r
end
local function advance(result)
  queue[result]=queue[result]+1;queue.i=queue.i+1;queue.ready=nil;queue.sent=nil
end
function M.stopCancelQueue()
  if queue and queue.pending and M.pendingCancel then M.pendingCancel.queued=nil end
  queue=nil
end
function M.startCancelQueue()
  if queue and queue.pending then return 'Waiting for the auction house.' end
  if not completeOwned() then api.QueryOwnedAuctions({});return 'Loading your auctions. Start the queue when ready.' end
  local rows={}
  for i=1,api.GetNumOwnedAuctions() do
    local r=api.GetOwnedAuctionInfo(i)
    if r and r.status==0 and r.itemKey and r.auctionID and r.quantity and r.quantity>0 and not r.bidder and (r.bidAmount or 0)==0 then
      rows[#rows+1]={id=r.auctionID,key=r.itemKey,qty=r.quantity,gross=M.listingGross(r),variant=ForeverMarketVariant(r.itemKey,r.itemLink)}
    end
  end
  table.sort(rows,function(a,b)if a.key.itemID==b.key.itemID then return a.id<b.id end return a.key.itemID<b.key.itemID end)
  queue={rows=rows,i=1,skipped=0,removed=0}
end
local function economics(row,price)
  local sale=M.account().sales[row.id]
  local deposit=sale and sale.deposit
  local vendor=select(11,C_Item.GetItemInfo(row.key.itemID))
  if not deposit or not vendor or not price or price*row.qty>=row.gross then return end
  if api.GetCancelCost(row.id)~=0 or not api.CanCancelAuction(row.id) then return end
  if ForeverMarketSaleNet(ForeverMarketPostPrice(price)*row.qty)-deposit<=vendor*row.qty then return end
  return deposit
end
function M.cancelQueueCurrent()
  if queue then return queue.rows[queue.i],queue end
end
function M.cancelQueueText()
  if not queue then return end
  local row=queue.rows[queue.i]
  if not row then return ('Finished / %d removed / %d skipped'):format(queue.removed,queue.skipped) end
  local prefix=('%d/%d  %s x%d'):format(queue.i,#queue.rows,C_Item.GetItemNameByID(row.key.itemID) or row.key.itemID,row.qty)
  if queue.pending then return prefix..' / awaiting removal' end
  if queue.ready then return prefix..' / rival '..ForeverMarketCoins(queue.ready.price)..' / lose '..ForeverMarketCoins(queue.ready.deposit) end
  return prefix..' / checking competition'
end
function M.cancelQueueTick()
  if not queue or not queue.rows[queue.i] then return end
  local row=queue.rows[queue.i]
  if queue.pending then
    if M.pendingCancel and M.pendingCancel.id==row.id and M.pendingCancel.removalNotice and completeOwned() and not owned(row.id) then
      if M.pendingCancel and M.pendingCancel.id==row.id then M.recordMarket('cancel_confirmed',{auctionID=row.id}) end
      queue.pending=nil;advance('removed')
    elseif GetTime()-queue.pending>12 then queue=nil;return 'Removal unconfirmed. Refresh owned auctions before restarting.' end
    return
  end
  if queue.ready then
    if GetTime()-queue.ready.at<=12 then return end
    queue.ready=nil;queue.sent=nil
  end
  if queue.sent then
    if GetTime()-queue.sent>8 then advance('skipped') end
    return
  end
  if not completeOwned() or not api.IsThrottledMessageSystemReady() then return end
  if not matching(row) then advance('skipped');return end
  local info=api.GetItemKeyInfo(row.key)
  if not info or not info.isCommodity and not row.variant then advance('skipped');return end
  row.commodity=info.isCommodity
  local book=queue.book
  if book and GetTime()-book.at<10 and sameKey(row.key,book.key) and row.variant==book.variant then
    local deposit=economics(row,book.price)
    if deposit then queue.ready={price=book.price,deposit=deposit,at=book.at} else advance('skipped') end
    return
  end
  queue.sent=GetTime()
  if not pcall(api.SendSearchQuery,row.key,{},true) then advance('skipped') end
end
local events=CreateFrame('Frame')
events:RegisterEvent('COMMODITY_SEARCH_RESULTS_UPDATED')
events:RegisterEvent('ITEM_SEARCH_RESULTS_UPDATED')
events:RegisterEvent('AUCTION_HOUSE_CLOSED')
pcall(events.RegisterEvent,events,'AUCTION_CANCELED')
events:SetScript('OnEvent',function(_,event,key)
  if event=='AUCTION_CANCELED' then
    if M.pendingCancel and M.pendingCancel.id==key then M.pendingCancel.removalNotice=true end
    return
  end
  if event=='AUCTION_HOUSE_CLOSED' then M.stopCancelQueue();return end
  if not queue or not queue.sent or queue.ready or queue.pending then return end
  local row=queue.rows[queue.i]
  local levels={}
  local commodity=event=='COMMODITY_SEARCH_RESULTS_UPDATED'
  if commodity then
    if not row.commodity or key~=row.key.itemID then return end
    if not api.HasFullCommoditySearchResults(key) then
      if api.IsThrottledMessageSystemReady() then api.RequestMoreCommoditySearchResults(key) end
      return
    end
  elseif row.commodity or not sameKey(row.key,key) then return
  elseif not api.HasFullItemSearchResults(key) then
    if api.IsThrottledMessageSystemReady() then api.RequestMoreItemSearchResults(key) end
    return
  end
  local count=commodity and api.GetNumCommoditySearchResults(key) or api.GetNumItemSearchResults(key)
  for i=1,count do
    local r
    if commodity then r=api.GetCommoditySearchResultInfo(key,i) else r=api.GetItemSearchResultInfo(key,i) end
    if r and not r.containsOwnerItem and not r.containsAccountItem and r.auctionID~=row.id and (r.quantity or 0)>0 then
      local price
      if commodity then price=r.unitPrice
      elseif sameKey(row.key,r.itemKey) and r.buyoutAmount and r.buyoutAmount>0 then
        local link=r.itemLink or (api.GetItemSearchResultItemLink and api.GetItemSearchResultItemLink(key,i))
        if ForeverMarketVariant(r.itemKey,link)==row.variant then price=math.ceil(r.buyoutAmount/r.quantity) end
      end
      if price and price>0 then levels[price]=(levels[price] or 0)+r.quantity end
    end
  end
  local book=ForeverMarketPriceDepth(levels)
  local price=book and book.floorPrice
  queue.book={key=row.key,variant=row.variant,price=price,at=GetTime()}
  local deposit=economics(row,price)
  if deposit then queue.ready={price=price,deposit=deposit,at=GetTime()} else advance('skipped') end
end)
function M.cancelQueueReady() return queue and not queue.pending and queue.ready end
function M.cancelQueueOne(displayed)
  if not displayed or displayed~=M.cancelQueueReady() then return 'Review the current listing.' end
  local row=queue.rows[queue.i]
  if GetTime()-displayed.at>12 or not completeOwned() or not matching(row) or economics(row,displayed.price)~=displayed.deposit then
    queue.ready=nil;queue.sent=nil;return 'Listing changed. Checking again.'
  end
  if not api.IsThrottledMessageSystemReady() then return 'Auction house busy. Try again.' end
  if M.pendingCancel and GetTime()-M.pendingCancel.at<12 then return 'Waiting for the previous cancellation.' end
  queue.pending=GetTime()
  M.pendingCancel={id=row.id,item=row.key.itemID,at=GetTime(),fee=0,queued=true}
  local ok=pcall(api.CancelAuction,row.id)
  if not ok then M.pendingCancel=nil;queue=nil;return 'Cancellation refused. Review in Blizzard Auctions.' end
end
