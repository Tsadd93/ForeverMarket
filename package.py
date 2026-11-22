from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parent
toc = (root / "ForeverMarket.toc").read_bytes()
version = next(s.split(": ", 1)[1] for s in toc.decode().splitlines() if s.startswith("## Version:"))
modules = "History Market Valuation Crafting Activity Snapshot Scan Bags SellTab BuyTab Workshop".split()
sections = []
for name in modules:
    file = name + ".lua"
    source = (root / "src" / file).read_bytes().decode("utf-8-sig", errors="replace")
    sections.append("do local function loadModule()\n" + source +
                    "\nend local ok,err=pcall(loadModule); if not ok then print('Forever Market " +
                    file + " failed: '..tostring(err)) end end\n")
target = root / "dist" / ("ForeverMarket-" + version + "-forever.zip")
target.parent.mkdir(exist_ok=True)
with ZipFile(target, "w", ZIP_DEFLATED) as z:
    for name in ("ForeverMarket.toc", "ForeverMarket_Forever.toc"):
        z.writestr("ForeverMarket/" + name, toc)
    z.writestr("ForeverMarket/Research.lua", "-- Optional desktop research. Safe to leave empty.\n")
    z.writestr("ForeverMarket/Market.lua", "\n".join(sections))
print(target)
