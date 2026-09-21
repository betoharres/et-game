$ErrorActionPreference = 'Stop'
$sourceStreet = 'D:/Program Files/Godot/et-game/scenes/CountryTown/Districts/StreetLife.tscn'
$sourcePed = 'D:/Program Files/Godot/et-game/scenes/CountryTown/Districts/PedestrianLife.tscn'
$target = 'D:/Program Files/Godot/et-game/scenes/CountryTown/CountryTown.tscn'
$enc = [Text.Encoding]::GetEncoding(28591)
$street = $enc.GetString([IO.File]::ReadAllBytes($sourceStreet)) -replace "`r`n", "`n"
$ped = $enc.GetString([IO.File]::ReadAllBytes($sourcePed)) -replace "`r`n", "`n"
$dst = $enc.GetString([IO.File]::ReadAllBytes($target))

function Get-Resources([string]$text, [string]$prefix) {
    $ext = @([regex]::Matches($text, '(?m)^\[ext_resource .*?\]') | ForEach-Object {
        $line = $_.Value -replace ' uid="[^"]+"', ''
        [regex]::Replace($line, ' id="([^"]+)"', { param($m) ' id="' + $prefix + $m.Groups[1].Value + '"' })
    })
    $sub = @([regex]::Matches($text, '(?ms)^\[sub_resource .*?(?=^\[|\z)') | ForEach-Object {
        $block = $_.Value.TrimEnd()
        $block = [regex]::Replace($block, 'id="([^"]+)"', { param($m) 'id="' + $prefix + $m.Groups[1].Value + '"' })
        $block = [regex]::Replace($block, 'ExtResource\("([^"]+)"\)', { param($m) 'ExtResource("' + $prefix + $m.Groups[1].Value + '")' })
        $block = [regex]::Replace($block, 'SubResource\("([^"]+)"\)', { param($m) 'SubResource("' + $prefix + $m.Groups[1].Value + '")' })
        $block
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

function Transform-Street([string]$block) {
    $header = ($block -split "`n")[0]
    $container = if ($header -match 'name="(Leaves|Dust|Fireflies)') { 'FXContainer' } else { 'PropsContainer' }
    $block = $block -replace ' unique_id=\d+', ''
    $block = Rewrite-Resources $block 'st_'
    [regex]::Replace($block, 'parent="\."', 'parent="' + $container + '"', 1)
}

function Transform-Ped([string]$block) {
    $header = ($block -split "`n")[0]
    $block = $block -replace ' unique_id=\d+', ''
    $block = Rewrite-Resources $block 'pl_'
    if ($header -match 'name="PedestrianLife" type=') {
        $lines = $block -split "`n"
        $lines[0] = $lines[0] -replace '\]$', ' parent="."]'
        return ($lines -join "`n")
    }
    if ($header -match 'parent="Pedestrians"') {
        $block = $block.Replace('parent="Pedestrians"', 'parent="NPCsContainer"')
    } elseif ($header -match 'parent="Pedestrians/') {
        $block = $block.Replace('parent="Pedestrians/', 'parent="NPCsContainer/')
    } elseif ($header -match 'parent="\."') {
        $block = [regex]::Replace($block, 'parent="\."', 'parent="BuildingsContainer"', 1)
    } elseif ($header -match 'parent="Crosswalk') {
        $block = [regex]::Replace($block, 'parent="(Crosswalk[^"]*)"', 'parent="BuildingsContainer/$1"', 1)
    }
    $block
}

$streetRes = Get-Resources $street 'st_'
$pedRes = Get-Resources $ped 'pl_'
$allExt = @($streetRes.Ext) + @($pedRes.Ext)
$allSub = @($pedRes.Sub)
$streetExt = [regex]::Match($dst, '(?m)^\[ext_resource type="PackedScene" path="res://scenes/CountryTown/Districts/StreetLife.tscn".*?\r?\n')
if (-not $streetExt.Success) { throw 'StreetLife resource not found' }
$dst = $dst.Remove($streetExt.Index, $streetExt.Length)
$insertPos = $dst.IndexOf('[sub_resource ')
if ($insertPos -lt 0) { $insertPos = $dst.IndexOf('[node ') }
$resourceText = (($allExt -join "`n") + "`n`n" + ($allSub -join "`n`n") + "`n`n")
$dst = $dst.Insert($insertPos, $resourceText)

$streetBlocks = @(Get-NodeBlocks $street | Select-Object -Skip 1 | Where-Object { $_ -notmatch 'name="PedestrianLife"' } | ForEach-Object { Transform-Street $_ })
$pedBlocks = @(Get-NodeBlocks $ped | Select-Object -Skip 1 | Where-Object { $_ -notmatch 'name="Pedestrians" type=' } | ForEach-Object { Transform-Ped $_ })
$pedEditables = @([regex]::Matches($ped, '(?m)^\[editable path="[^"]+"\]') | ForEach-Object {
    $_.Value.Replace('path="Pedestrians/', 'path="NPCsContainer/').Replace('path="Crosswalk', 'path="BuildingsContainer/Crosswalk')
})
$replacement = (($pedBlocks + $streetBlocks + $pedEditables) -join "`n`n") + "`n"
$instance = [regex]::Match($dst, '(?ms)^\[node name="StreetLife" parent="\."[^\n]*instance=ExtResource\("[^"]+"\)\]\r?\n.*?(?=^\[node |\z)')
if (-not $instance.Success) { throw 'StreetLife instance not found' }
$dst = $dst.Remove($instance.Index, $instance.Length).Insert($instance.Index, $replacement)
[IO.File]::WriteAllBytes($target, $enc.GetBytes($dst))
Write-Output ('Embedded PedestrianLife and StreetLife content: ' + $pedBlocks.Count + ' pedestrian blocks, ' + $streetBlocks.Count + ' street blocks.')
