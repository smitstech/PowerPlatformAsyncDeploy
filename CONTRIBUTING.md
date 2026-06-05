# Contributing to PowerPlatformAsyncDeploy

Thanks for your interest in improving this module! Contributions of all sizes are welcome —
bug fixes, docs, and features alike.

## Getting set up

You'll need **PowerShell 7.0+** (Windows, macOS, or Linux). Clone the repo and import the module:

```powershell
git clone https://github.com/smitstech/PowerPlatformAsyncDeploy.git
cd PowerPlatformAsyncDeploy
Import-Module ./PowerPlatformAsyncDeploy.psd1 -Force
```

## Project layout

| Path | What lives there |
| --- | --- |
| `Public/` | Exported functions (one file per function). |
| `Private/` | Internal helpers, not exported. |
| `docs/` | User-facing documentation. |
| `examples/` | Runnable example scripts. |

The module loader (`PowerPlatformAsyncDeploy.psm1`) dot-sources everything in `Private/` then
`Public/`, and exports only the public functions.

## Coding conventions

- **Use approved PowerShell verbs** for public functions (`Get-Verb` lists them). Public functions
  use the `Pp` noun prefix, e.g. `Start-PpAsyncDeployment`.
- **Add comment-based help** (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`, `.OUTPUTS`) to
  every public function.
- **Never commit secrets.** Connection strings, client secrets, and state files
  (`*deployment-state.json`) are git-ignored — keep it that way.
- Keep new public surface area small and documented in the `README.md`.

## Check your changes locally

CI runs these on every pull request; run them first to get a fast green light:

```powershell
# 1. The manifest is valid
Test-ModuleManifest ./PowerPlatformAsyncDeploy.psd1

# 2. The module imports and exports the expected functions
Import-Module ./PowerPlatformAsyncDeploy.psd1 -Force
Get-Command -Module PowerPlatformAsyncDeploy

# 3. Static analysis (no Error-severity findings)
Install-Module PSScriptAnalyzer -Scope CurrentUser   # first time only
Invoke-ScriptAnalyzer -Path . -Recurse
```

## Pull request process

1. **Branch** off `main` (`git switch -c fix/short-description`).
2. Make your change and update docs/examples if behaviour changed.
3. Open a **pull request** against `main`. The CODEOWNERS file will request a review automatically.
4. A PR can merge once:
   - **CI passes**,
   - it has **at least one approving review**,
   - and all **review conversations are resolved**.

`main` is protected: force-pushes and deletions are blocked, and changes land through PRs. Thanks
for helping keep the history clean!
