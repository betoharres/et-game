$ErrorActionPreference = 'Stop'
$project = 'D:/Program Files/Godot/et-game'
$targetPath = "$project/scenes/CountryTown/CountryTown.tscn"
$minePath = "$project/scenes/CountryTown/Districts/MinePortalSite.tscn"
$enc = [Text.Encoding]::GetEncoding(28591)
function Read-Scene([string]$path) { $enc.GetString([IO.File]::ReadAllBytes($path)) -replace "`r`n", "`n" }
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
function Transform-Block([string]$block, [string]$container) {
    $block = $block -replace ' unique_id=\d+', ''
    $block = Rewrite-Resources $block 'mine_'
    [regex]::Replace($block, 'parent="\.((?:/[^"]*)?)"', { param($m) 'parent="' + $container + $m.Groups[1].Value + '"' })
}

$dst = Read-Scene $targetPath
$mine = Read-Scene $minePath
$mineRes = Get-Resources $mine 'mine_'
$mineExt = [regex]::Match($dst, '(?ms)^\[ext_resource type="PackedScene".*?path="res://scenes/CountryTown/Districts/MinePortalSite\.tscn".*?\r?\n')
if (-not $mineExt.Success) { throw 'MinePortalSite resource not found' }
$dst = $dst.Remove($mineExt.Index, $mineExt.Length)
$insertPos = $dst.IndexOf('[sub_resource ')
if ($insertPos -lt 0) { $insertPos = $dst.IndexOf('[node ') }
$resources = (($mineRes.Ext -join "`n") + "`n`n" + ($mineRes.Sub -join "`n`n") + "`n`n")
$dst = $dst.Insert($insertPos, $resources)

$blocks = @(Get-NodeBlocks $mine)
$portal = $blocks | Where-Object { $_ -match 'name="Portal".*instance=ExtResource\("1_portal"\)' } | Select-Object -First 1
if (-not $portal) { throw 'Portal instance not found in MinePortalSite' }
$portal = $portal -replace ' unique_id=\d+', ''
$portal = Rewrite-Resources $portal 'mine_'
$levelBlocks = @($portal)
foreach ($block in ($blocks | Select-Object -Skip 1 | Where-Object { $_ -notmatch 'name="Portal".*instance=ExtResource\("1_portal"\)' })) {
    $header = ($block -split "`n")[0]
    $name = if ($header -match 'name="([^"]+)"') { $matches[1] } else { '' }
    $container = if ($name -match '^(ArchPillar|ArchLintel|Rock|Boulder)') { 'NatureContainer' } else { 'PropsContainer' }
    $levelBlocks += Transform-Block $block $container
}
$instance = [regex]::Match($dst, '(?m)^\[node name="MinePortalSite" parent="\."[^\n]*instance=ExtResource\("[^"]+"\)\]\r?\n')
if (-not $instance.Success) { throw 'MinePortalSite instance not found' }
$dst = $dst.Remove($instance.Index, $instance.Length)
$dst = $dst.TrimEnd("`n") + "`n`n" + (($levelBlocks -join "`n`n") + "`n")
[IO.File]::WriteAllBytes($targetPath, $enc.GetBytes($dst))

$mineOut = $mine
$mineOut = [regex]::Replace($mineOut, '(?m)^\[ext_resource type="PackedScene" uid="[^"]+" path="res://scenes/Portal/portal\.tscn" id="1_portal"\]\r?\n', '')
$mineOut = [regex]::Replace($mineOut, '(?ms)^\[node name="Portal" parent="\.".*?(?=^\[node |\z)', '')
[IO.File]::WriteAllBytes($minePath, $enc.GetBytes($mineOut))
Write-Output ('Flattened MinePortalSite: preserved portal instance, relocated ' + ($levelBlocks.Count - 1) + ' site nodes.')
