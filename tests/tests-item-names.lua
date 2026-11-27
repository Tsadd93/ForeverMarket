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

-- A completion may rebind multiple labels still waiting on another item.
local d,e=label(),label()
ForeverMarketSetItemText(d,'Item 10 / Item 11')
ForeverMarketSetItemText(e,'Item 10')
e:SetText('Different row')
names[10]='First'
received(nil,nil,10,true)
assert(d.text=='First / Loading item name...' and e.text=='Different row')
names[11]='Second'
received(nil,nil,11,true)
assert(d.text=='First / Second' and requests[10]==1 and requests[11]==1)
