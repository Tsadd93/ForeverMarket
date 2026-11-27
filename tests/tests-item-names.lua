dofile('src/ItemNames.lua')
local requests,names={},{}
GetTime=function() return 1 end
C_Item={GetItemNameByID=function(id)return names[id] end,
  RequestLoadItemDataByID=function(id)requests[id]=(requests[id] or 0)+1 end}
local received
CreateFrame=function()return {RegisterEvent=function()end,SetScript=function(_,_,fn)received=fn end}end
local function label()
  return {SetText=function(self,s)self.text=s end,GetText=function(self)return self.text end}
end
local a,b,c=label(),label(),label()
ForeverMarketSetItemText(a,'Item 8845')
ForeverMarketSetItemText(b,'Item #8845 (50)')
ForeverMarketSetItemText(c,'Item 8845')
ForeverMarketSetItemText(c,'Item 8170')
assert(requests[8845]==1 and requests[8170]==1)
assert(a.text=='Loading item name...')
names[8845]='Ghost Mushroom'
received(nil,nil,8845,true)
assert(a.text==names[8845] and b.text=='Ghost Mushroom (50)' and c.text=='Loading item name...')
received(nil,nil,8170,false)
assert(c.text=='Unknown item (8170)')
print('PASS: cold cache, shared requests, late names, recycled rows and failed loads')
