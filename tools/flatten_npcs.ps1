$ErrorActionPreference = 'Stop'
$source = 'D:/Program Files/Godot/et-game/scenes/CountryTown/Districts/NPCs.tscn'
$target = 'D:/Program Files/Godot/et-game/scenes/CountryTown/CountryTown.tscn'
$enc = [Text.Encoding]::GetEncoding(28591)
$src = $enc.GetString([IO.File]::ReadAllBytes($source)) -replace "`r`n", "`n"
$dst = $enc.GetString([IO.File]::ReadAllBytes($target))
$prefix = 'ct_npcs_'

$ext = @([regex]::Matches($src, '(?m)^\[ext_resource .*?\]') | ForEach-Object {
    $line = $_.Value -replace ' uid="[^"]+"', ''
    [regex]::Replace($line, ' id="([^"]+)"', { param($m) ' id="' + $prefix + $m.Groups[1].Value + '"' })
})
$oldExt = [regex]::Match($dst, '(?m)^\[ext_resource type="PackedScene" path="res://scenes/CountryTown/Districts/NPCs.tscn".*?\r?\n')
if (-not $oldExt.Success) { throw 'NPCs scene resource not found' }
$dst = $dst.Remove($oldExt.Index, $oldExt.Length)
$insertPos = $dst.IndexOf('[sub_resource ')
if ($insertPos -lt 0) { $insertPos = $dst.IndexOf('[node ') }
$dst = $dst.Insert($insertPos, (($ext -join "`n") + "`n`n"))

$start = $src.IndexOf('[node ')
$blocks = @([regex]::Matches($src.Substring($start), '(?ms)^\[node .*?(?=^\[node |\z)') | ForEach-Object { $_.Value.TrimEnd() })
$children = @()
foreach ($block in ($blocks | Select-Object -Skip 1)) {
    $block = $block -replace ' unique_id=\d+', ''
    $block = [regex]::Replace($block, 'parent="\."', 'parent="NPCsContainer"', 1)
    $block = [regex]::Replace($block, 'ExtResource\("([^"]+)"\)', { param($m) 'ExtResource("' + $prefix + $m.Groups[1].Value + '")' })
    $children += $block
}
$instance = [regex]::Match($dst, '(?ms)^\[node name="NPCs" parent="NPCsContainer"[^\n]*instance=ExtResource\("[^"]+"\)\]\r?\n.*?(?=^\[node |\z)')
if (-not $instance.Success) { throw 'NPCs wrapper instance not found' }
$dst = $dst.Remove($instance.Index, $instance.Length).Insert($instance.Index, (($children -join "`n`n") + "`n"))
[IO.File]::WriteAllBytes($target, $enc.GetBytes($dst))
Write-Output ('Moved ' + $children.Count + ' NPC instances directly under NPCsContainer.')
