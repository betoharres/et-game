$ErrorActionPreference = 'Stop'

$project = 'D:\Program Files\Godot\et-game'
$levelPath = Join-Path $project 'scenes\CountryTown\CountryTown.tscn'
$sourcePath = Join-Path $project 'scenes\CountryTown\Districts\Detailing.tscn'

function Read-Latin1([string]$path) {
    [Text.Encoding]::GetEncoding(28591).GetString([IO.File]::ReadAllBytes($path))
}

function Write-Latin1([string]$path, [string]$text) {
    [IO.File]::WriteAllBytes($path, [Text.Encoding]::GetEncoding(28591).GetBytes($text))
}

function Get-SectionBlocks([string]$text, [string]$kind) {
    [regex]::Matches($text, "(?ms)^\[$kind .*?(?=^\[|\z)") | ForEach-Object { $_.Value }
}

function Classify([string]$name) {
    if ($name -match '^(Flowers|Hedge)') { return 'VegetationContainer' }
    if ($name -match '(Rock|Stump)') { return 'NatureContainer' }
    return 'PropsContainer'
}

$level = Read-Latin1 $levelPath
$source = Read-Latin1 $sourcePath

$detailingInstance = [regex]::Matches($level, '(?ms)^\[node .*?(?=^\[node |\z)') |
    Where-Object { $_.Value -match 'instance=ExtResource\("16_detailing"\)' } |
    Select-Object -First 1
if (-not $detailingInstance) { throw 'Could not find the CountryTown Detailing instance.' }
$level = $level.Remove($detailingInstance.Index, $detailingInstance.Length)

$detailingResource = [regex]::Matches($level, '(?ms)^\[ext_resource .*?(?=^\[|\z)') |
    Where-Object { $_.Value -match 'path="res://scenes/CountryTown/Districts/Detailing\.tscn"' } |
    Select-Object -First 1
if ($detailingResource) {
    $level = $level.Remove($detailingResource.Index, $detailingResource.Length)
}

if ($level -notmatch '(?m)^\[node name="VegetationContainer"') {
    $level = [regex]::Replace($level, '(?m)^(\[node name="NatureContainer"[^\r\n]*\r?\n)', '$1[node name="VegetationContainer" type="Node3D" parent="."]$([Environment]::NewLine)')
}

$sourceExt = Get-SectionBlocks $source 'ext_resource'
$sourceSub = Get-SectionBlocks $source 'sub_resource'
$resourceText = ''
foreach ($block in $sourceExt) {
    $resourceText += ([regex]::Replace($block, '(?m)(^\[ext_resource[^\r\n]*\bid=")([^"]+)(")', ('$1' + 'dt_$2' + '$3')))
}
foreach ($block in $sourceSub) {
    $resourceText += ([regex]::Replace($block, '(?m)(^\[sub_resource[^\r\n]*\bid=")([^"]+)(")', ('$1' + 'dt_$2' + '$3')))
}
$resourceText = $resourceText -replace 'ExtResource\("([^"]+)"\)', 'ExtResource("dt_$1")'
$resourceText = $resourceText -replace 'SubResource\("([^"]+)"\)', 'SubResource("dt_$1")'

$nodeStart = $source.IndexOf('[node ')
if ($nodeStart -lt 0) { throw 'Detailing has no nodes.' }
$sourceNodes = $source.Substring($nodeStart)
$nodeBlocks = [regex]::Matches($sourceNodes, '(?ms)^\[node .*?(?=^\[node |\z)')
$embedded = ''
$currentRoot = ''
$currentTarget = ''
$rootCount = 0
$childCount = 0
foreach ($match in $nodeBlocks) {
    $block = $match.Value
    $header = [regex]::Match($block, '(?m)^\[node name="([^"]+)"[^\r\n]*')
    if (-not $header.Success) { continue }
    $name = $header.Groups[1].Value
    $parentMatch = [regex]::Match($header.Value, 'parent="([^"]*)"')
    if (-not $parentMatch.Success) {
        if ($name -eq 'Detailing') { continue }
        throw "Node $name has no parent."
    }
    $sourceParent = $parentMatch.Groups[1].Value
    if ($sourceParent -eq '.') {
        $currentRoot = $name
        $currentTarget = Classify $name
        $rootCount++
    } else {
        if ([string]::IsNullOrEmpty($currentRoot)) { throw "Child node $name appeared before a root." }
        $childCount++
    }

    $block = [regex]::Replace($block, '(?m)(^\[node[^\r\n]*?)\sunique_id=\d+', '$1')
    $block = [regex]::Replace($block, 'parent="([^"]*)"', {
        param($m)
        $parent = $m.Groups[1].Value
        if ($parent -eq '.') {
            return 'parent="' + $currentTarget + '"'
        }
        if ($parent -eq $currentRoot) {
            return 'parent="' + $currentTarget + '/' + $currentRoot + '"'
        }
        if ($parent.StartsWith($currentRoot + '/')) {
            return 'parent="' + $currentTarget + '/' + $parent + '"'
        }
        throw "Unexpected parent path '$parent' under '$currentRoot'."
    })
    $block = $block -replace 'ExtResource\("([^"]+)"\)', 'ExtResource("dt_$1")'
    $block = $block -replace 'SubResource\("([^"]+)"\)', 'SubResource("dt_$1")'
    $embedded += $block
}

$insertAt = $level.IndexOf('[node ')
if ($insertAt -lt 0) { throw 'CountryTown has no node section.' }
$level = $level.Insert($insertAt, $resourceText)
$level += $embedded
Write-Latin1 $levelPath $level
Write-Output "Flattened Detailing: $rootCount roots, $childCount child nodes."
