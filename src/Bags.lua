local GetRealmName=ForeverMarketVenueRealm or function() return _G.GetRealmName and _G.GetRealmName() or '' end
-- Native bag decoration; never sells, moves or locks an item.
local enabled=true
local badges=setmetatable({},{__mode='k'})
local function money(n) return GetCoinTextureString and GetCoinTextureString(math.floor(n)) or tostring(math.floor(n))..'c' end
function ForeverMarketBagDecision(x)
  if x.bound or x.quest or x.class~=7 or not x.vendor then return nil end
  if not x.price or x.price<=0 or not x.age or x.age<0 or x.age>86400 then return 'check',nil,'Price missing or over 24 hours old. Scan the AH first.' end
  -- Use the same configured costs as the Sell tab.
  local edge=ForeverMarketSaleNet(ForeverMarketPostPrice(x.price)*x.count)-ForeverMarketDepositLoss(x.count)-x.vendor*x.count
  if edge>=math.max(100,x.vendor*x.count*.20) then
    return 'ah',edge,'Worth checking for auction: estimated stack advantage after fee/deposit allowance.'
  end
  return nil,edge,'Small or negative AH advantage after fee/deposit allowance. Other uses may still matter.'
end
local function location(button)
  if not button or not button.GetID then return end
  local parent=button:GetParent()
  local bag=button.GetBagID and button:GetBagID() or parent and parent.GetID and parent:GetID()
  local slot=button.GetSlotID and button:GetSlotID() or button:GetID()
  if type(bag)=='number' and bag>=0 and bag<=5 and type(slot)=='number' and slot>0 and slot<=C_Container.GetContainerNumSlots(bag) then return bag,slot end
end
local function evaluate(bag,slot)
  if not C_Container then return end
  local info=C_Container.GetContainerItemInfo(bag,slot)
  if not info or not info.itemID then return end
  local get=C_Item and C_Item.GetItemInfo or GetItemInfo
  local name,_,_,_,_,_,_,_,_,_,vendor,class=get(info.itemID)
  if not name or class~=7 then return end
  local quest=C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag,slot)
  local questItem=type(quest)=='table' and (quest.isQuestItem or quest.questID) or quest==true
  local loc=ItemLocation and ItemLocation:CreateFromBagAndSlot(bag,slot)
  local bound=info.isBound or (loc and C_Item and C_Item.IsBound and C_Item.IsBound(loc))
  local records=ForeverMarketDB and ForeverMarketDB[GetRealmName()..'|'..UnitFactionGroup('player')]
  local live=records and records[tostring(info.itemID)]
  local books=ForeverMarketDB and ForeverMarketDB.__depth
  local book=books and books[GetRealmName()..'|'..UnitFactionGroup('player')]
  local d=book and book[info.itemID]
  if d and time()-d.at<=3600 and (not live or d.at>=live.at) then live={price=d.floorPrice,at=d.at} else d=nil end
  local state,edge,reason=ForeverMarketBagDecision({bound=bound,quest=questItem,class=class,
    vendor=vendor,price=live and live.price,age=live and time()-live.at,count=info.stackCount or 1})
  if reason and d and d.floorPrice>d.low then
    reason=reason..' Low offer: '..d.lowQty..' at '..money(d.low)..'; next supported tier: '..d.floorQty..' at '..money(d.floorPrice)..'.'
  end
  return state,edge,reason,live and live.price
end
local function decorate(button)
  local bag,slot=location(button)
  local state=bag and enabled and evaluate(bag,slot)
  local badge=badges[button]
  if state and not badge and not InCombatLockdown() then
    badge={lines={}}
    for i,point in ipairs({'TOP','BOTTOM','LEFT','RIGHT'}) do
      local t=button:CreateTexture(nil,'OVERLAY',nil,6)
      if i<=2 then t:SetHeight(2);t:SetPoint(point..'LEFT',button,point..'LEFT',0,0);t:SetPoint(point..'RIGHT',button,point..'RIGHT',0,0)
      else t:SetWidth(2);t:SetPoint('TOP'..point,button,'TOP'..point,0,0);t:SetPoint('BOTTOM'..point,button,'BOTTOM'..point,0,0) end
      badge.lines[i]=t
    end
    badge.label=button:CreateFontString(nil,'OVERLAY');badge.label:SetFont('Fonts\\ARIALN.TTF',11,'OUTLINE');badge.label:SetPoint('TOPLEFT',2,-2)
    badges[button]=badge
  end
  if not badge then return end
  for _,t in ipairs(badge.lines) do
    t:SetShown(state~=nil and state~=false)
    if state=='ah' then t:SetColorTexture(.20,1,.70,.95) else t:SetColorTexture(1,.72,.20,.8) end
  end
  badge.label:SetText(state=='ah' and '|cff55ffb0AH|r' or state=='check' and '|cffffbd33?|r' or '')
end
local function walk(frame,depth)
  if not frame or not frame:IsShown() or depth>6 then return end
  if frame.IsObjectType and frame:IsObjectType('Button') then decorate(frame) end
  if frame.GetChildren then for _,child in ipairs({frame:GetChildren()}) do walk(child,depth+1) end end
end
local f=CreateFrame('Frame');local elapsed=0
f:SetScript('OnUpdate',function(_,dt)
  elapsed=elapsed+dt;if elapsed<.75 or not C_Container then return end;elapsed=0
  for i=1,13 do walk(_G['ContainerFrame'..i],0) end
  walk(ContainerFrameCombinedBags,0)
end)
function ForeverMarketBagToggle(on)
  enabled=on
  print('|cff65dfc0Forever Market:|r bag markers '..(enabled and 'on. AH = check auction price; ? = scan needed.' or 'off.'))
end
if type(ContainerFrameItemButton_OnEnter)=='function' then pcall(hooksecurefunc,'ContainerFrameItemButton_OnEnter',function(button)
  if not enabled or ForeverMarketTools then return end
  local bag,slot=location(button);if not bag then return end
  local state,edge,reason,price=evaluate(bag,slot)
  if not reason then return end
  GameTooltip:AddLine('Forever Market',.33,1,.70)
  GameTooltip:AddLine(reason,1,.85,.50,true)
  if price then GameTooltip:AddLine('Last observed AH ask / item: '..money(price),.8,.8,.8) end
  if edge then GameTooltip:AddLine('Estimated advantage over vendoring / stack: '..(edge<0 and '-' or '')..money(math.abs(edge)),.8,.8,.8) end
  GameTooltip:AddLine('No sale guarantee. Keep anything you need for quests or crafting.',.65,.7,.75,true);GameTooltip:Show()
end) end
