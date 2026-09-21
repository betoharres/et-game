$ErrorActionPreference = 'Stop'
$target = 'D:/Program Files/Godot/et-game/scenes/CountryTown/CountryTown.tscn'
$enc = [Text.Encoding]::GetEncoding(28591)
$text = $enc.GetString([IO.File]::ReadAllBytes($target)) -replace "`r`n", "`n"
$marker = $text.IndexOf('[node name="Farmhouse" parent="BuildingsContainer"')
if ($marker -lt 0) { throw 'Embedded FarmDistrict marker not found' }
$head = $text.Substring(0, $marker)
$tail = $text.Substring($marker)
$lines = $tail -split "`n"
$fixed = @()
$workRoot = ''
foreach ($line in $lines) {
    if ($line -match '^\[node name="([^"]+)"[^\n]* parent="([^"]+)"') {
        $name = $matches[1]
        $parent = $matches[2]
        if ($parent -match '^(BuildingsContainer|NatureContainer|PropsContainer|VehiclesContainer)$') {
            $workRoot = $parent + '/' + $name
        } elseif ($parent -match '^(BuildingsContainer|PropsContainer)/Workyard\d+_(Buildings|Props)$') {
            $workRoot = $parent
        } elseif ($workRoot -ne '' -and $parent -notlike 'BuildingsContainer/*' -and $parent -notlike 'NatureContainer/*' -and $parent -notlike 'PropsContainer/*' -and $parent -notlike 'VehiclesContainer/*' -and $parent -ne $workRoot -and $parent -notlike "$workRoot/*") {
            $line = $line.Replace('parent="' + $parent + '"', 'parent="' + $workRoot + '/' + $parent + '"')
        }
    }
    $fixed += $line
}
$out = $head + (($fixed -join "`n") + "`n")
[IO.File]::WriteAllBytes($target, $enc.GetBytes($out))
Write-Output 'Repaired embedded farm parent paths.'
