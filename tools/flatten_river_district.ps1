$ErrorActionPreference = 'Stop'
$stage = 'all'
if ($args.Count -gt 0) { $stage = $args[0] }
$repo = 'D:/Program Files/Godot/et-game'

function Read-Parts([string]$path, [string]$prefix) {
    $text = (Get-Content -LiteralPath $path -Raw) -replace "`r`n", "`n"
    $ext = @([regex]::Matches($text, '(?ms)^\[ext_resource .*?(?=^\[|\z)') | ForEach-Object {
        $b = $_.Value.TrimEnd() -replace ' uid="[^"]+"', ''
        [regex]::Replace($b, ' id="([^"]+)"', { param($m) ' id="' + $prefix + $m.Groups[1].Value + '"' })
    })
    $sub = @([regex]::Matches($text, '(?ms)^\[sub_resource .*?(?=^\[|\z)') | ForEach-Object {
        $b = [regex]::Replace($_.Value.TrimEnd(), 'id="([^"]+)"', { param($m) 'id="' + $prefix + $m.Groups[1].Value + '"' })
        $b = [regex]::Replace($b, 'ExtResource\("([^"]+)"\)', { param($m) 'ExtResource("' + $prefix + $m.Groups[1].Value + '")' })
        [regex]::Replace($b, 'SubResource\("([^"]+)"\)', { param($m) 'SubResource("' + $prefix + $m.Groups[1].Value + '")' })
    })
    $start = $text.IndexOf('[node ')
    $nodes = @([regex]::Matches($text.Substring($start), '(?ms)^\[node .*?(?=^\[node |\z)') | ForEach-Object { $_.Value.TrimEnd() })
    @{ Text = $text; Ext = $ext; Sub = $sub; Nodes = $nodes; Prefix = $prefix }
}

function Insert-Resources([string]$base, [hashtable]$parts) {
    $pos = $base.IndexOf('[sub_resource ')
    if ($pos -lt 0) { $pos = $base.IndexOf('[node ') }
    $insert = ($parts.Ext -join "`n") + "`n`n" + ($parts.Sub -join "`n") + "`n`n"
    $base.Insert($pos, $insert)
}

function Transform-Block([string]$block, [string]$name, [string]$prefix, [bool]$root, [string[]]$overrideKeys) {
    $out = @(); $first = $true
    foreach ($line0 in ($block -split "`n")) {
        if ($line0.Trim() -eq '') { continue }
        $line = $line0 -replace ' unique_id=\d+', ''
        if ($first -and $line -match '^\[node name="[^"]+" type="([^"]+)"') {
            if ($root) { $line = '[node name="' + $name + '" type="' + $Matches[1] + '" parent="."]' }
            $first = $false
        } elseif ($line -match '^\[node ') {
            $line = [regex]::Replace($line, 'parent="([^"]+)"', {
                param($m)
                $p = $m.Groups[1].Value
                $np = if ($p -eq '.') { $name } else { $name + '/' + $p }
                'parent="' + $np + '"'
            })
            $first = $false
        } elseif ($root -and $line -match '^([A-Za-z0-9_/]+)\s*=') {
            if ($overrideKeys -contains $Matches[1]) { continue }
        }
        $line = [regex]::Replace($line, 'ExtResource\("([^"]+)"\)', { param($m) 'ExtResource("' + $prefix + $m.Groups[1].Value + '")' })
        $line = [regex]::Replace($line, 'SubResource\("([^"]+)"\)', { param($m) 'SubResource("' + $prefix + $m.Groups[1].Value + '")' })
        $out += $line
    }
    $out -join "`n"
}

function Embed-Scene([string]$target, [string]$source, [string]$instanceId, [string]$name, [string]$prefix, [bool]$addResources = $true) {
    $base = (Get-Content -LiteralPath $target -Raw) -replace "`r`n", "`n"
    $parts = Read-Parts $source $prefix
    $rel = ($source.Substring($repo.Length).TrimStart('\','/') -replace '\\','/')
    $base = [regex]::Replace($base, '(?ms)^\[ext_resource type="PackedScene" path="res://' + [regex]::Escape($rel) + '".*?(?=^\[|\z)', '')
    if ($addResources) { $base = Insert-Resources $base $parts }
    $pattern = '(?ms)^\[node name="' + [regex]::Escape($name) + '"[^\n]*instance=ExtResource\("' + [regex]::Escape($instanceId) + '"\)\]\n(.*?)(?=^\[node |\z)'
    if (-not [regex]::IsMatch($base, $pattern)) { throw "Instance not found: $name / $instanceId in $target" }
    $children = @(); $rootBlock = $parts.Nodes[0]
    $match = [regex]::Match($base, $pattern)
    $overrideLines = @($match.Groups[1].Value -split "`n") | Where-Object { $_.Trim() -ne '' }
    $overrideKeys = @($overrideLines | ForEach-Object { if ($_ -match '^([A-Za-z0-9_/]+)\s*=') { $Matches[1] } })
    $root = Transform-Block $rootBlock $name $prefix $true $overrideKeys
    $rootLines = @($root -split "`n")
    $rootLines += $overrideLines
    foreach ($child in ($parts.Nodes | Select-Object -Skip 1)) { $children += Transform-Block $child $name $prefix $false @() }
    $replacement = ''
    $base = [regex]::Replace($base, $pattern, $replacement, 1)
    $embedded = ($rootLines -join "`n") + "`n`n" + ($children -join "`n`n")
    Set-Content -LiteralPath $target -Value ($base.TrimEnd() + "`n`n" + $embedded + "`n") -Encoding utf8
}

function Inline-Scene([string]$target, [string]$source, [string]$instanceId, [string]$name, [string]$prefix) {
    $base = (Get-Content -LiteralPath $target -Raw) -replace "`r`n", "`n"
    $parts = Read-Parts $source $prefix
    $rel = ($source.Substring($repo.Length).TrimStart('\','/') -replace '\\','/')
    $base = [regex]::Replace($base, '(?ms)^\[ext_resource type="PackedScene" path="res://' + [regex]::Escape($rel) + '".*?(?=^\[|\z)', '')
    $base = Insert-Resources $base $parts
    $pattern = '(?ms)^\[node name="' + [regex]::Escape($name) + '" parent="\."[^\n]*instance=ExtResource\("' + [regex]::Escape($instanceId) + '"\)\]\n.*?(?=^\[node |\z)'
    if (-not [regex]::IsMatch($base, $pattern)) { throw "Instance not found: $name / $instanceId in $target" }
    $root = Transform-Block $parts.Nodes[0] $name $prefix $true @()
    $children = @($parts.Nodes | Select-Object -Skip 1 | ForEach-Object { Transform-Block $_ $name $prefix $false @() })
    $base = [regex]::Replace($base, $pattern, '', 1)
    $embedded = $root + "`n`n" + ($children -join "`n`n")
    Set-Content -LiteralPath $target -Value ($base.TrimEnd() + "`n`n" + $embedded + "`n") -Encoding utf8
}

$wooden = "$repo/scenes/CountryTown/Blocks/WoodenDock.tscn"
$river = "$repo/scenes/CountryTown/Districts/RiverDistrict.tscn"
$country = "$repo/scenes/CountryTown/CountryTown.tscn"
if ($stage -in @('all','dock_shelter')) {
    Embed-Scene $wooden "$repo/scenes/CountryTown/Blocks/DockShelter.tscn" '20_shelter' 'DockShelter' 'wd_shelter_'
    Write-Output 'Flattened DockShelter into WoodenDock.'
}
if ($stage -in @('all','river','water')) {
    Embed-Scene $river "$repo/scenes/CountryTown/Districts/RiverWater.tscn" '1_riverwater' 'RiverWater' 'rd_water_'
    Write-Output 'Flattened RiverWater.'
}
if ($stage -in @('all','river','bridge_north')) {
    Embed-Scene $river "$repo/scenes/CountryTown/Blocks/RiverBridge.tscn" '2_riverbridge' 'BridgeNorth' 'rd_bridge_' $true
    Write-Output 'Flattened BridgeNorth.'
}
if ($stage -in @('all','river','bridge_south')) {
    Embed-Scene $river "$repo/scenes/CountryTown/Blocks/RiverBridge.tscn" '2_riverbridge' 'BridgeSouth' 'rd_bridge_' $false
    Write-Output 'Flattened BridgeSouth.'
}
if ($stage -in @('all','river','river_dock')) {
    Embed-Scene $river $wooden '3_woodendock' 'Dock' 'rd_dock_'
    Write-Output 'Flattened Dock.'
}
if ($stage -in @('all','river','fog_first')) {
    Embed-Scene $river "$repo/scenes/FX/FogZone.tscn" '4_fogzone' 'FogRiver01' 'rd_fog_' $true
    Write-Output 'Flattened FogRiver01.'
}
if ($stage -in @('all','river','fog_rest')) {
    foreach ($name in @('FogRiver02','FogRiver03','FogRiver04','FogRiver05')) { Embed-Scene $river "$repo/scenes/FX/FogZone.tscn" '4_fogzone' $name 'rd_fog_' $false }
    Write-Output 'Flattened remaining fog zones.'
}
if ($stage -in @('all','country')) {
    Inline-Scene $country $river '8_river_district' 'RiverDistrict' 'ct_river_'
    Write-Output 'Inlined RiverDistrict into CountryTown.'
}
