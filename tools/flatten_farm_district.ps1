$ErrorActionPreference = 'Stop'

$project = 'D:/Program Files/Godot/et-game'
$targetPath = "$project/scenes/CountryTown/CountryTown.tscn"
$farmPath = "$project/scenes/CountryTown/Districts/FarmDistrict.tscn"
$infillPath = "$project/scenes/CountryTown/Districts/RuralInfill.tscn"
$workyardPath = "$project/scenes/CountryTown/Blocks/RuralWorkyard.tscn"
$cargoPath = "$project/scenes/CountryTown/Blocks/CargoStack.tscn"
$enc = [Text.Encoding]::GetEncoding(28591)

function Read-Scene([string]$path) {
    return ($enc.GetString([IO.File]::ReadAllBytes($path)) -replace "`r`n", "`n")
}

function Get-Resources([string]$text, [string]$prefix) {
    $ext = @([regex]::Matches($text, '(?m)^\[ext_resource .*?\]') | ForEach-Object {
        $line = $_.Value -replace ' uid="[^"]+"', ''
        [regex]::Replace($line, ' id="([^"]+)"', { param($m) ' id="' + $prefix + $m.Groups[1].Value + '"' })
    })
    $sub = @([regex]::Matches($text, '(?ms)^\[sub_resource .*?(?=^\[|\z)') | ForEach-Object {
        $block = $_.Value.TrimEnd()
        $block = [regex]::Replace($block, 'id="([^"]+)"', { param($m) 'id="' + $prefix + $m.Groups[1].Value + '"' })
        $block = [regex]::Replace($block, 'ExtResource\("([^"]+)"\)', { param($m) 'ExtResource("' + $prefix + $m.Groups[1].Value + '")' })
        [regex]::Replace($block, 'SubResource\("([^"]+)"\)', { param($m) 'SubResource("' + $prefix + $m.Groups[1].Value + '")' })
    })
    @{ Ext = $ext; Sub = $sub }
}

function Rewrite-Resources([string]$block, [string]$prefix) {
    $block = [regex]::Replace($block, 'ExtResource\("([^"]+)"\)', { param($m) 'ExtResource("' + $prefix + $m.Groups[1].Value + '")' })
    [regex]::Replace($block, 'SubResource\("([^"]+)"\)', { param($m) 'SubResource("' + $prefix + $m.Groups[1].Value + '")' })
}

function Get-NodeBlocks([string]$text) {
    $start = $text.IndexOf('[node ')
    @([regex]::Matches($text.Substring($start), '(?ms)^\[node .*?(?=^\[node |\z)') | ForEach-Object { $_.Value.TrimEnd() })
}

function Transform-RootBlock([string]$block, [string]$prefix, [string]$container) {
    $block = $block -replace ' unique_id=\d+', ''
    $block = Rewrite-Resources $block $prefix
    [regex]::Replace($block, 'parent="\.((?:/[^"]*)?)"', { param($m) 'parent="' + $container + $m.Groups[1].Value + '"' })
}

function Transform-WorkyardBlock([string]$block, [string]$prefix, [string]$container, [string]$rootName) {
    $block = $block -replace ' unique_id=\d+', ''
    $block = Rewrite-Resources $block $prefix
    $block = $block.Replace('parent="."', 'parent="' + $container + '/' + $rootName + '"')
    $block = $block.Replace('parent="' + $rootName + '/', 'parent="' + $container + '/' + $rootName + '/')
    $block
}

$dst = Read-Scene $targetPath
$farm = Read-Scene $farmPath
$infill = Read-Scene $infillPath
$workyard = Read-Scene $workyardPath
$cargo = Read-Scene $cargoPath

$farmRes = Get-Resources $farm 'fd_'
$infillRes = Get-Resources $infill 'ri_'
$workyardRes = Get-Resources $workyard 'rw_'
$cargoRes = Get-Resources $cargo 'cs_'
$allExt = @($farmRes.Ext) + @($infillRes.Ext) + @($workyardRes.Ext) + @($cargoRes.Ext)
$allSub = @($farmRes.Sub) + @($infillRes.Sub) + @($workyardRes.Sub) + @($cargoRes.Sub)

$farmExt = [regex]::Match($dst, '(?m)^\[ext_resource type="PackedScene" path="res://scenes/CountryTown/Districts/FarmDistrict\.tscn".*?\r?\n')
if (-not $farmExt.Success) { throw 'FarmDistrict resource not found' }
$dst = $dst.Remove($farmExt.Index, $farmExt.Length)
$insertPos = $dst.IndexOf('[sub_resource ')
if ($insertPos -lt 0) { $insertPos = $dst.IndexOf('[node ') }
$resourceText = (($allExt -join "`n") + "`n`n" + ($allSub -join "`n`n") + "`n`n")
$dst = $dst.Insert($insertPos, $resourceText)

$farmBlocks = @(Get-NodeBlocks $farm | Select-Object -Skip 1 | Where-Object { $_ -notmatch 'name="RuralInfill"' } | ForEach-Object {
    $h = ($_ -split "`n")[0]
    if ($h -match 'name="(Farmhouse|Barn|Silo|Garage|Windmill|WaterWell|LivestockPen|OldShed|WaterTower|Greenhouse|ProduceStand|Outhouse|HayBarn)"') {
        Transform-RootBlock $_ 'fd_' 'BuildingsContainer'
    } else {
        Transform-RootBlock $_ 'fd_' 'BuildingsContainer'
    }
})

$infillBlocks = @(Get-NodeBlocks $infill | Select-Object -Skip 1 | Where-Object { $_ -notmatch 'name="Workyard(0|2|4|6|8|10)"' } | ForEach-Object {
    $h = ($_ -split "`n")[0]
    $name = if ($h -match 'name="([^"]+)"') { $matches[1] } else { '' }
    if ($name -match '^Env_|^Generic_|Soil|^RiverFarmSoil|^PenGardenSoil|^PenPastureSoil|^SouthFarmSoil|^Wheat|^Sunflowers|^CornFieldSoil|^TownKitchenGardenSoil|^WestPastureSoil|^MillWheatSoil|^DeliveryCompoundSoil') {
        Transform-RootBlock $_ 'ri_' 'NatureContainer'
    } elseif ($name -match '^ParkedTractor') {
        Transform-RootBlock $_ 'ri_' 'VehiclesContainer'
    } elseif ($name -match '^ParcelFence|^Prop_|^HarvestStack|^HarvestYard') {
        Transform-RootBlock $_ 'ri_' 'PropsContainer'
    } else {
        Transform-RootBlock $_ 'ri_' 'BuildingsContainer'
    }
})

$workyardNodes = @(Get-NodeBlocks $workyard | Select-Object -Skip 1)
$cargoNodes = @(Get-NodeBlocks $cargo | Select-Object -Skip 1)
$workyardInstances = @(Get-NodeBlocks $infill | Where-Object { $_ -match 'instance=ExtResource\("1_7w0sj"\)' })
$workyardBlocks = @()
foreach ($instance in $workyardInstances) {
    $ih = ($instance -split "`n")[0]
    if ($ih -notmatch 'name="([^"]+)"') { continue }
    $workyardName = $matches[1]
    $transformLine = ($instance -split "`n" | Where-Object { $_ -match '^transform = ' })
    $buildRoot = '[node name="' + $workyardName + '_Buildings" type="Node3D" parent="BuildingsContainer"]' + "`n" + $transformLine
    $propsRoot = '[node name="' + $workyardName + '_Props" type="Node3D" parent="PropsContainer"]' + "`n" + $transformLine
    $workyardBlocks += $buildRoot
    $workyardBlocks += $propsRoot
    foreach ($node in $workyardNodes) {
        $nh = ($node -split "`n")[0]
        if ($nh -match 'name="Bld_Shelter_016"') {
            $workyardBlocks += Transform-WorkyardBlock $node 'rw_' 'BuildingsContainer' "${workyardName}_Buildings"
        } elseif ($nh -match 'name="Supplies"') {
            $sup = $node -replace ' instance=ExtResource\("7_bwrix"\)', ''
            $sup = $sup -replace ' unique_id=\d+', ''
            $sup = Rewrite-Resources $sup 'rw_'
            $sup = $sup.Replace('parent="."', 'parent="PropsContainer/' + $workyardName + '_Props"')
            $workyardBlocks += $sup
            foreach ($cargoNode in $cargoNodes) {
                $workyardBlocks += Transform-WorkyardBlock $cargoNode 'cs_' 'PropsContainer' "${workyardName}_Props/Supplies"
            }
        } else {
            $workyardBlocks += Transform-WorkyardBlock $node 'rw_' 'PropsContainer' "${workyardName}_Props"
        }
    }
}

$replacement = (($farmBlocks + $infillBlocks + $workyardBlocks) -join "`n`n") + "`n"
$farmInstance = [regex]::Match($dst, '(?ms)^\[node name="FarmDistrict" parent="\."[^\n]*instance=ExtResource\("[^"]+"\)\]\r?\n')
if (-not $farmInstance.Success) { throw 'FarmDistrict instance not found' }
$dst = $dst.Remove($farmInstance.Index, $farmInstance.Length)
$dst = $dst.TrimEnd("`n") + "`n`n" + $replacement
[IO.File]::WriteAllBytes($targetPath, $enc.GetBytes($dst))
Write-Output ('Flattened FarmDistrict: ' + $farmBlocks.Count + ' district blocks, ' + $infillBlocks.Count + ' RuralInfill blocks, ' + $workyardBlocks.Count + ' workyard blocks.')
