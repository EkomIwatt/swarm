<#
.SYNOPSIS
  Bootstrap a new Swarm project as its OWN git repo under PROJECTS/.

.DESCRIPTION
  Creates PROJECTS/<Name> as a standalone git repository with a starter
  .gitignore and an initial commit, so it is ready for /swarm-initialiser.

  This is the step whose absence caused worktrees to be cut from the outer
  Swarm container repo (and inherit the wrong CLAUDE.md). Each project must
  be its own repo BEFORE any `git worktree add` is run.

  Worktrees use the SIBLING layout: after you approve the initialiser plan,
  run its `git worktree add -b instance/<x> ../<Name>-<x>` commands from
  inside PROJECTS/<Name>, creating scratch copies at PROJECTS/<Name>-<x>.
  /swarm-reconciler merges those branches back and the scratch dirs are removed.

.PARAMETER Name
  Project name. Becomes the folder PROJECTS/<Name> and the repo root.

.EXAMPLE
  .\new-swarm-project.ps1 -Name Snipp
  cd ".\PROJECTS\Snipp"
  claude   # then run: /swarm-initialiser <your brief>
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$Name
)

$ErrorActionPreference = 'Stop'

# Swarm root = the folder this script lives in. PROJECTS lives NEXT TO Swarm
# (sibling on the Desktop), not inside it, so project repos never tangle with
# the Swarm container repo.
$swarmRoot   = $PSScriptRoot
$projectsDir = Join-Path (Split-Path $swarmRoot -Parent) 'PROJECTS'
$projectPath = Join-Path $projectsDir $Name

# Ensure PROJECTS/ exists.
if (-not (Test-Path $projectsDir)) {
    New-Item -ItemType Directory -Path $projectsDir | Out-Null
}

# Refuse to clobber an existing non-empty project folder.
if (Test-Path $projectPath) {
    $existing = Get-ChildItem -Force $projectPath -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Error "PROJECTS\$Name already exists and is not empty. Pick another name or remove it first."
        return
    }
} else {
    New-Item -ItemType Directory -Path $projectPath | Out-Null
}

# Starter .gitignore covering the usual Swarm stacks (Python + Node + env + OS).
$gitignore = @'
# Python (backend)
__pycache__/
*.py[cod]
.venv/
venv/
env/
*.egg-info/
.pytest_cache/
.mypy_cache/
.ruff_cache/

# Node / frontend
node_modules/
dist/
build/
.vite/
*.local

# Env / secrets
.env
.env.*
!.env.example

# OS / editor
.DS_Store
Thumbs.db
.idea/
.vscode/
'@
Set-Content -Path (Join-Path $projectPath '.gitignore') -Value $gitignore -Encoding utf8

# Minimal README so the repo has a title and a non-empty first commit.
$readme = "# $Name`n`nA Swarm multi-agent project. Run `/swarm-initialiser` here to plan the parallel build.`n"
Set-Content -Path (Join-Path $projectPath 'README.md') -Value $readme -Encoding utf8

# Initialize the project's OWN repo and make the first commit.
git -C $projectPath init -b main | Out-Null
git -C $projectPath add .gitignore README.md
git -C $projectPath commit -m "Initialize $Name project repo" | Out-Null

# Sanity: the project's repo root must be the project folder, NOT the Swarm container.
$top = (git -C $projectPath rev-parse --show-toplevel).Trim()

Write-Host ""
Write-Host "Created project repo:" -ForegroundColor Green
Write-Host "  $top"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  cd `"$projectPath`""
Write-Host "  claude"
Write-Host "  # then run:  /swarm-initialiser <your project brief>"
Write-Host ""
Write-Host "After you approve the plan, run the initialiser's worktree commands from"
Write-Host "inside the project folder, e.g.:"
Write-Host "  git worktree add -b instance/backend  ..\$Name-backend"
Write-Host "  git worktree add -b instance/frontend ..\$Name-frontend"
Write-Host ""
