<#
.SYNOPSIS
  Move PROJECTS from inside Swarm out to the Desktop (sibling of Swarm),
  then repair the git worktrees whose absolute paths the move invalidates.

.DESCRIPTION
  Run this ONCE, from a terminal that is NOT inside the PROJECTS folder, and
  with no Claude Code session rooted inside PROJECTS (otherwise Windows locks
  the folder and the move fails with "insufficient access rights").

  After moving, git worktrees still point at their old absolute paths, so this
  script runs `git worktree repair` on the Snipp repo to relink Snipp-backend
  and Snipp-frontend at their new locations. It auto-detects any *-backend /
  *-frontend style worktree siblings, so it also works for future projects.

.EXAMPLE
  # From the Desktop (NOT inside PROJECTS), and with the Snipp Claude sessions closed:
  cd "$env:USERPROFILE\OneDrive - University of Lagos\Desktop"
  .\Swarm\move-projects.ps1
#>
[CmdletBinding()]
param(
    [string]$Src  = "$env:USERPROFILE\OneDrive - University of Lagos\Desktop\Swarm\PROJECTS",
    [string]$Dest = "$env:USERPROFILE\OneDrive - University of Lagos\Desktop\PROJECTS"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Src)) {
    Write-Error "Source not found: $Src  (already moved?)"
    return
}
if (Test-Path $Dest) {
    Write-Error "Destination already exists: $Dest  (remove/rename it first)"
    return
}

# Guard: refuse to run from inside the folder we are about to move.
$here = (Get-Location).Path
if ($here.StartsWith($Src, [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Error "You are inside PROJECTS ($here). cd somewhere else (e.g. the Desktop) and re-run."
    return
}

Write-Host "Moving:" -ForegroundColor Cyan
Write-Host "  $Src"
Write-Host "    -> $Dest"
Move-Item -LiteralPath $Src -Destination $Dest
Write-Host "Move OK." -ForegroundColor Green

# Repair every project repo's worktrees. A 'project repo' is any subfolder of
# the new PROJECTS that contains a .git directory AND has *-<suffix> siblings.
Get-ChildItem -Directory $Dest | ForEach-Object {
    $repo = $_.FullName
    if (-not (Test-Path (Join-Path $repo '.git'))) { return }

    # Gather sibling worktrees whose name starts with "<this repo name>-".
    $prefix    = "$($_.Name)-"
    $worktrees = Get-ChildItem -Directory $Dest |
        Where-Object { $_.Name.StartsWith($prefix) } |
        ForEach-Object { $_.FullName }

    if ($worktrees) {
        Write-Host "Repairing worktrees for $($_.Name): $($worktrees -join ', ')" -ForegroundColor Cyan
        git -C $repo worktree repair @worktrees
        Write-Host "--- $($_.Name) worktree list ---"
        git -C $repo worktree list
    }
}

Write-Host ""
Write-Host "Done. PROJECTS now lives at:" -ForegroundColor Green
Write-Host "  $Dest"
