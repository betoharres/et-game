$ErrorActionPreference = 'Stop'
$project = 'D:\Program Files\Godot\et-game'
$levelPath = Join-Path $project 'scenes\CountryTown\CountryTown.tscn'
$sourcePath = Join-Path $project 'scenes\CountryTown\Blocks\LivestockPen.tscn'
$enc = [Text.Encoding]::GetEncoding(28591)

function Read-Latin1([string]$path) { $enc.GetString([IO.File]::ReadAllBytes($path)) }
function Write-Latin1([string]$path, [string]$text) { [IO.File]::WriteAllBytes($path, $enc.GetBytes($text)) }
function Sections([string]$text, [string]$kind) {
    [regex]::Matches($text, "(?ms)^\[$kind .*?(?=^\[|\z)") | ForEach-Object Value
}

$level = Read-Latin1 $levelPath
$source = Read-Latin1 $sourcePath

$instance = [regex]::Matches($level, '(?ms)^\[node .*?(?=^\[node |\z)') |
    Where-Object { $_.Value -match 'instance=ExtResource\("fd_7_livestockpen"\)' } | Select-Object -First 1
if (-not $instance) { throw 'LivestockPen instance not found in CountryTown.' }
$level = $level.Remove($instance.Index, $instance.Length)

$resource = [regex]::Matches($level, '(?ms)^\[ext_resource .*?(?=^\[|\z)') |
    Where-Object { $_.Value -match 'path="res://scenes/CountryTown/Blocks/LivestockPen\.tscn"' } | Select-Object -First 1
if ($resource) { $level = $level.Remove($resource.Index, $resource.Length) }

$resourceText = ''
foreach ($block in (Sections $source 'ext_resource')) {
    $resourceText += [regex]::Replace($block, '(?m)(^\[ext_resource[^\r\n]*\bid=")([^"]+)(")', '$1lp_$2$3')
}
foreach ($block in (Sections $source 'sub_resource')) {
    $resourceText += [regex]::Replace($block, '(?m)(^\[sub_resource[^\r\n]*\bid=")([^"]+)(")', '$1lp_$2$3')
}
$resourceText = $resourceText -replace 'ExtResource\("([^"]+)"\)', 'ExtResource("lp_$1")'
$resourceText = $resourceText -replace 'SubResource\("([^"]+)"\)', 'SubResource("lp_$1")'

$nodeStart = $source.IndexOf('[node ')
$nodeBlocks = [regex]::Matches($source.Substring($nodeStart), '(?ms)^\[node .*?(?=^\[node |\z)')
$embedded = ''
$root = ''
foreach ($match in $nodeBlocks) {
    $block = $match.Value
    $header = [regex]::Match($block, '(?m)^\[node name="([^"]+)"[^\r\n]*')
    if (-not $header.Success) { continue }
    $name = $header.Groups[1].Value
    $parent = [regex]::Match($header.Value, 'parent="([^"]*)"')
    if (-not $parent.Success) {
        if ($name -eq 'LivestockPen') { continue }
        throw "Node $name has no parent."
    }
    if ($parent.Groups[1].Value -eq '.') { $root = $name }
    $block = [regex]::Replace($block, '(?m)(^\[node[^\r\n]*?)\sunique_id=\d+', '$1')
    $block = [regex]::Replace($block, 'parent="([^"]*)"', {
        param($m)
        $p = $m.Groups[1].Value
        if ($p -eq '.') { return 'parent="BuildingsContainer"' }
        if ($p -eq $root) { return 'parent="BuildingsContainer/' + $root + '"' }
        if ($p.StartsWith($root + '/')) { return 'parent="BuildingsContainer/' + $p + '"' }
        throw "Unexpected parent path '$p'."
    })
    $block = $block -replace 'ExtResource\("([^"]+)"\)', 'ExtResource("lp_$1")'
    $block = $block -replace 'SubResource\("([^"]+)"\)', 'SubResource("lp_$1")'
    $embedded += $block
}

$at = $level.IndexOf('[sub_resource')
if ($at -lt 0) { $at = $level.IndexOf('[node ') }
if ($at -lt 0) { throw 'CountryTown node section not found.' }
$level = $level.Insert($at, $resourceText)
$level += $embedded
Write-Latin1 $levelPath $level
Write-Output 'Flattened LivestockPen into BuildingsContainer.'
