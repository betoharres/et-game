$ErrorActionPreference = 'Stop'
$repo = 'D:/Program Files/Godot/et-game'
$source = Join-Path $repo 'scenes/CountryTown/Districts/CrashSiteDistrict.tscn'
$target = Join-Path $repo 'scenes/CountryTown/CountryTown.tscn'
$prefix = 'ct_crash_'

$enc = [Text.Encoding]::GetEncoding(28591)
$src = $enc.GetString([IO.File]::ReadAllBytes($source)) -replace "`r`n", "`n"
$dst = $enc.GetString([IO.File]::ReadAllBytes($target))

$ext = @([regex]::Matches($src, '(?m)^\[ext_resource .*?\]') | ForEach-Object {
    $line = $_.Value -replace ' uid="[^"]+"', ''
    [regex]::Replace($line, ' id="([^"]+)"', { param($m) ' id="' + $prefix + $m.Groups[1].Value + '"' })
})
$extLine = [regex]::Match($dst, '(?m)^\[ext_resource type="PackedScene" path="res://scenes/CountryTown/Districts/CrashSiteDistrict.tscn".*?\n')
if ($extLine.Success) { $dst = $dst.Remove($extLine.Index, $extLine.Length) }

$insert = ($ext -join "`n") + "`n`n"
$pos = $dst.IndexOf('[sub_resource ')
if ($pos -lt 0) { $pos = $dst.IndexOf('[node ') }
$dst = $dst.Insert($pos, $insert)

$start = $src.IndexOf('[node ')
$blocks = @([regex]::Matches($src.Substring($start), '(?ms)^\[node .*?(?=^\[node |\z)') | ForEach-Object { $_.Value.TrimEnd() })
$embedded = @()
foreach ($block in ($blocks | Select-Object -Skip 1)) {
    $header = ($block -split "`n")[0]
    if ($header -match '^\[node name="([^"]+)"[^\]]* parent="([^"]+)"') {
        $name = $Matches[1]
        $parent = $Matches[2]
    } elseif ($header -match '^\[node name="([^"]+)"[^\]]* parent="([^"]+)"') {
        $name = $Matches[1]
        $parent = $Matches[2]
    } else { continue }
    if ($name -eq 'Collision' -or $parent -eq 'Collision') { continue }
    if ($name -eq 'CrashedSaucer') { $container = 'VehiclesContainer' }
    elseif ($header -match 'type="(OmniLight3D|WorldEnvironment|GPUParticles3D|FogVolume)"' -or $name -match 'Fog|Fire|Smoke|Glow|Light|FX') { $container = 'FXContainer' }
    elseif ($header -match 'instance=ExtResource\("' -and $name -match '^(Rock|Pebble|HullFragment)') { $container = 'NatureContainer' }
    elseif ($header -match 'type="MeshInstance3D"') { $container = 'PropsContainer' }
    else { $container = 'PropsContainer' }
    $block = $block -replace ' unique_id=\d+', ''
    $block = [regex]::Replace($block, 'ExtResource\("([^"]+)"\)', { param($m) 'ExtResource("' + $prefix + $m.Groups[1].Value + '")' })
    $block = [regex]::Replace($block, 'parent="\."', 'parent="' + $container + '"', 1)
    $embedded += $block
}

$roots = @('[node name="NatureContainer" type="Node3D" parent="."]', '[node name="FXContainer" type="Node3D" parent="."]')
foreach ($root in $roots) {
    if ($dst -notmatch [regex]::Escape($root)) { $embedded = @($root) + $embedded }
}
$instance = [regex]::Match($dst, '(?ms)^\[node name="CrashSiteDistrict" parent="\."[^\n]*instance=ExtResource\("[^"]+"\)\]\n.*?(?=^\[node |\z)')
if (-not $instance.Success) { throw 'CrashSiteDistrict instance not found' }
$dst = $dst.Remove($instance.Index, $instance.Length)
$dst = $dst.TrimEnd() + "`n`n" + ($embedded -join "`n`n") + "`n"
[IO.File]::WriteAllBytes($target, $enc.GetBytes($dst))
Write-Output ('Embedded CrashSiteDistrict: ' + $embedded.Count + ' top-level blocks; collisions omitted.')
