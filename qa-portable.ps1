# Exercise the actual portable release with isolated data and the public US PvP Horde TSM feed.
$ErrorActionPreference='Stop'
$qa=Join-Path $env:RUNNER_TEMP ('QA-'+[guid]::NewGuid())
$client=Join-Path $qa 'WoW Forever'
$account=New-Item -ItemType Directory -Force "$client\WTF\Account\Test\SavedVariables"
$addon=New-Item -ItemType Directory -Force "$client\Interface\AddOns\ForeverMarket"
$data=New-Item -ItemType Directory -Force "$qa\data"
[IO.File]::WriteAllText("$addon\ForeverMarket.toc","## Title: QA")
[IO.File]::WriteAllText("$data\client.txt",$client)
$now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$history=@(1..5 | ForEach-Object {@{at=$now-86400*$_;low=100000;quantity=50}})
$snapshot=@{version=1;realm='';faction='Horde';region=1;rows=@(@{key='2589';name='Linen Cloth';history=$history;live=@{at=$now;price=1;quantity=100}})}
$json=$snapshot | ConvertTo-Json -Depth 8 -Compress
[IO.File]::WriteAllText("$account\ForeverMarket.lua",'ForeverMarketExport = '+(ConvertTo-Json -InputObject $json -Compress))
$exe=Join-Path $PSScriptRoot 'releases\ForeverMarket-Desktop-0.8.0-win-x64.exe'
$env:FM_DATA=$data.FullName
$env:PATH="$env:SystemRoot\system32;$env:SystemRoot"
foreach($run in 'first','reopen'){
    $launcher=Start-Process $exe -PassThru -WindowStyle Hidden
    $dashboard=$null
    try{
        $deadline=(Get-Date).AddSeconds(60)
        do{
            Start-Sleep -Milliseconds 400
            $dashboard=Get-CimInstance Win32_Process -Filter "ParentProcessId=$($launcher.Id) AND Name='ForeverMarket.exe'"
            if($dashboard){$service=Get-CimInstance Win32_Process -Filter "ParentProcessId=$($dashboard.ProcessId) AND Name='node.exe'"}
            if($service){$port=Get-NetTCPConnection -State Listen -OwningProcess $service.ProcessId -ErrorAction SilentlyContinue | Select-Object -ExpandProperty LocalPort -First 1}
        }until($port -or (Get-Date) -gt $deadline)
        if(!$port){throw 'The bundled market service did not open.'}
        $origin="http://127.0.0.1:$port"
        $state=Invoke-RestMethod "$origin/api/state"
        $headers=@{Origin=$origin;'X-FM-Token'=$state.token}
        if($state.items.Count -ne 1 -or $state.items[0].key -ne '2589'){throw 'WoW import failed.'}
        if($run -eq 'first'){
            $event=@{id='qa:1';kind='purchase';character='QATrader';realm='';faction='Horde';region=1;at=$now;itemId=2589;quantity=3;total=30} | ConvertTo-Json -Compress
            $bytes=[Text.Encoding]::UTF8.GetBytes($event)
            $hash=[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)).Replace('-','').ToLowerInvariant()
            [IO.File]::WriteAllBytes("$data\activity-inbox\$hash.json",$bytes)
            $deadline=(Get-Date).AddSeconds(10)
            do{Start-Sleep -Milliseconds 250;$a=Invoke-RestMethod "$origin/api/activity"}until($a.activity.count -gt 0 -or (Get-Date) -gt $deadline)
            if($a.activity.events[0].total -ne 30){throw 'Live inbox purchase missing.'}
            try{
                Invoke-RestMethod "$origin/api/settings" -Method Post -Headers $headers -ContentType application/json -Body '{"link":true,"feed":{"region":"eu","realm":"pvp-horde"}}'
                throw 'Wrong region was accepted.'
            }catch{if($_.ErrorDetails.Message -notmatch 'Region mismatch'){throw}}
            Invoke-RestMethod "$origin/api/settings" -Method Post -Headers $headers -ContentType application/json -Body '{"link":true,"feed":{"region":"us","realm":"pvp-horde"}}' | Out-Null
        }
        $state=Invoke-RestMethod "$origin/api/state"
        $linen=$state.preview | Where-Object id -eq '2589'
        $rank=$state.research.items | Where-Object id -eq 2589
        if($state.mapping -ne 'us/realm/pvp-horde' -or !$linen.marketValue -or $rank.tsm -ne $linen.marketValue){throw 'Linked live TSM price missing from research.'}
        $lua=Get-Content "$addon\Research.lua" -Raw
        if(!$lua.Contains("[2589]={rank=1,ceiling=$($rank.ceiling)}") -or !$lua.Contains('allowBlank=true') -or !$lua.Contains('region=1')){throw 'Addon return data mismatch.'}
        Write-Output "$run - $($state.preview.Count) TSM items, Linen Cloth market $($rank.tsm)c, addon ceiling $($rank.ceiling)c."
    }finally{
        if($dashboard){$process=Get-Process -Id $dashboard.ProcessId -ErrorAction SilentlyContinue;if($process){[void]$process.CloseMainWindow()}}
        if(!$launcher.WaitForExit(15000)){throw 'Portable dashboard failed to close.'}
        $port=$null;$service=$null
    }
}
$image=Join-Path $qa 'dashboard.png'
$test=Start-Process $exe -ArgumentList ('--visual-test "'+$image+'"') -WindowStyle Hidden -PassThru
if(!$test.WaitForExit(60000) -or $test.ExitCode -ne 0 -or !(Test-Path $image)){throw 'Desktop WebView smoke test failed.'}
Write-Output "Verified dashboard and linked data at $qa"
