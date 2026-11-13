# =====================================================================================
# Saldos -> Pull Request in Azure DevOps (repo "MAZ_Command Center PA")
# Same flow as the other reports: own worktree + branch, copy the PBIP items,
# commit, push, then the PR to main in the Azure DevOps website.
# Run in PowerShell, one block at a time.
# =====================================================================================

# ---- 0) Settings (check these 3 before running) ------------------------------------
$Repo    = "C:\MAZ_Command Center PA"
$Wt      = "C:\MAZ_Command Center PA - saldos"
$Rama    = "pbi/saldos"
$Origen  = "$env:USERPROFILE\Downloads\Saldos_DBX_v2"     # unzipped folder from Saldos_DBX_v2.zip
$Destino = "BrewDat Prod MAZ Panama\Command Center"
$Nombre  = "Saldos_DBX"                                  # item name in the repo (see step 2)


# ---- 1) Worktree + branch from the latest main --------------------------------------
Set-Location -LiteralPath $Repo
git fetch origin
git worktree add -b $Rama "$Wt" origin/main
Set-Location -LiteralPath $Wt


# ---- 2) Is there already a Saldos item in the repo? ---------------------------------
# If this lists an existing Saldos item (for example pbi_pa_saldos.SemanticModel),
# set $Nombre to that name (without .SemanticModel) so the PR UPDATES it instead of
# creating a second report. Its .platform (logicalId) is kept by step 3.
Get-ChildItem -LiteralPath (Join-Path $Wt $Destino) | Where-Object { $_.Name -like "*aldos*" } | Select-Object Name


# ---- 3) Copy the 3 PBIP items with the name $Nombre ---------------------------------
$D = Join-Path $Wt $Destino
function Escribir($ruta, $texto) { [IO.File]::WriteAllText($ruta, $texto, (New-Object Text.UTF8Encoding($false))) }

foreach ($t in "Report", "SemanticModel") {
    $src = Join-Path $Origen "Saldos_DBX.$t"
    $dst = Join-Path $D "$Nombre.$t"
    $plat = $null
    if (Test-Path -LiteralPath (Join-Path $dst ".platform")) {
        $plat = [IO.File]::ReadAllText((Join-Path $dst ".platform"))   # existing item: keep its logicalId
    }
    if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
    Copy-Item -LiteralPath $src -Destination $dst -Recurse
    $p = Join-Path $dst ".platform"
    if ($plat) { Escribir $p $plat }
    else { Escribir $p (([IO.File]::ReadAllText($p)).Replace('"displayName": "Saldos_DBX"', "`"displayName`": `"$Nombre`"")) }
}
# report -> semantic model link
$pbir = Join-Path $D "$Nombre.Report\definition.pbir"
Escribir $pbir (([IO.File]::ReadAllText($pbir)).Replace("../Saldos_DBX.SemanticModel", "../$Nombre.SemanticModel"))
# .pbip file
$pbip = Join-Path $D "$Nombre.pbip"
Escribir $pbip (([IO.File]::ReadAllText((Join-Path $Origen "Saldos_DBX.pbip"))).Replace('"Saldos_DBX.Report"', "`"$Nombre.Report`""))

Get-ChildItem -LiteralPath $D | Where-Object { $_.Name -like "$Nombre*" } | Select-Object Name


# ---- 4) Commit + push ---------------------------------------------------------------
git add -A -- "$Destino"
git status
git commit -m "Saldos: origen Databricks (pa_accounts_receivable_line_item + pa_customer), warehouse brewdat-maz-sales-pa-adb-ep01-p"
git push -u origin $Rama


# ---- 5) Pull Request (Azure DevOps website) -----------------------------------------
# Repos > Pull requests > New pull request
#   source: pbi/saldos   target: main
#   Title: Saldos sobre Databricks
#   Description: Saldos (cuentas por cobrar) lee de Databricks en lugar de SQL Server.
#                Warehouse: brewdat-maz-sales-pa-adb-ep01-p (brewdat-maz-transformationeda-adbwks01-p).
#   Create


# ---- 6) After the PR is merged (optional cleanup) -----------------------------------
# Set-Location -LiteralPath $Repo
# git worktree remove "$Wt"
# git branch -d $Rama
