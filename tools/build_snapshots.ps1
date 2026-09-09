# Gera os snapshots do repositorio em docs/generated/, um por camada.
#
# O snapshot inteiro (~378k tokens) nao cabe confortavelmente numa conversa,
# entao cada perfil abaixo e um arquivo carregavel sozinho. A divisao segue a
# estrutura de pastas de proposito: arquivo novo cai no perfil certo sem ninguem
# manter lista nenhuma.
#
#     .\tools\build_snapshots.ps1            # os cinco perfis
#     .\tools\build_snapshots.ps1 -Completo  # tambem o snapshot unico
#
# O perfil de contexto sozinho ja responde "o que existe e onde fica"; os demais
# entram sob demanda, quando a pergunta e sobre o codigo daquela camada.
#
# Por que um config temporario por perfil, e nao `repomix --include`: o --include
# da linha de comando SOMA ao include de repomix.config.json em vez de
# substitui-lo, e todo perfil sairia com o repositorio inteiro. Só `-c` troca o
# config de verdade (o repomix.config.json da raiz segue valendo para o snapshot
# unico).

param([switch]$Completo)

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

$perfis = @(
    @{ nome = "01-contexto"; titulo = "Contexto: documentacao, regras e configuracao do projeto"
       padroes = @("AGENTS.md", "CLAUDE.md", "README.md", "project.godot", "export_presets.cfg", "docs/**/*.md") }
    @{ nome = "02-scripts-principais"; titulo = "Scripts principais: jogador, mundo, entrega, ambientacao, veiculos"
       padroes = @("scripts/*.gd") }
    @{ nome = "03-scripts-subsistemas"; titulo = "Subsistemas: npc, space, dungeon, audio, levels, plane, portal, spider_bot, terrain"
       padroes = @("scripts/*/**/*.gd") }
    @{ nome = "04-tools"; titulo = "Ferramentas: geradores de asset, checagens e o procedimento de validacao"
       padroes = @("tools/**/*.gd", "tools/**/*.py", "tools/**/*.md") }
    @{ nome = "05-shaders"; titulo = "Shaders: ceu, nevoa, terreno, personagem, nave e pos-processo"
       padroes = @("shaders/**/*.gdshader") }
)

foreach ($perfil in $perfis) {
    $saida = "docs/generated/$($perfil.nome).md"
    Write-Host "==> $saida"

    $config = @{
        output = @{
            filePath   = $saida
            style      = "markdown"
            headerText = "$($perfil.titulo). Parte do snapshot do ET Game; a documentacao curada fica em docs/ e as regras em AGENTS.md."
        }
        include = $perfil.padroes
        ignore  = @{
            useGitignore      = $true
            useDefaultPatterns = $true
            # Nunca empacotar a propria saida: sem isto o perfil de contexto
            # engoliria os snapshots da rodada anterior.
            customPatterns    = @("docs/generated/**", ".godot/**", "addons/**", "build/**")
        }
        security = @{ enableSecurityCheck = $true }
    }

    # Sem BOM: o leitor de config do repomix nao aceita o marcador do PowerShell.
    $temporario = Join-Path $env:TEMP "repomix-$($perfil.nome).json"
    [System.IO.File]::WriteAllText($temporario, ($config | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding $false))

    npx --yes repomix --config $temporario
    Remove-Item $temporario -ErrorAction SilentlyContinue
}

if ($Completo) {
    Write-Host "==> docs/generated/repomix-snapshot.md (completo)"
    npx --yes repomix
}
