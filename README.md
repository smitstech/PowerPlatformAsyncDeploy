# PowerPlatformAsyncDeploy

A small PowerShell module for deploying Power Platform packages **asynchronously**. It submits the
work to your Dataverse environment and returns straight away — so your terminal, pipeline agent, or
runbook is never tied up waiting for a long import to finish. You check progress whenever you like.

It handles both kinds of artifact found in a Power Platform deployment package:

- **Dataverse solutions** — submitted as asynchronous solution imports.
- **Finance & Operations (xpp) packages** — uploaded and then deployed as a single batch.

The module exposes just two functions:

| Function | What it does |
| --- | --- |
| `Start-PpAsyncDeployment` | Reads a package, submits every solution and F&O package, and writes a small JSON **state file**. Returns immediately. |
| `Get-PpAsyncDeploymentStatus` | Reads that state file and reports the live status of every submitted operation. |

---

## How it works

1. `Start-PpAsyncDeployment` reads `PackageAssets/ImportConfig.xml` to find every solution and
   package, in order.
2. Each Dataverse solution is submitted to the Dataverse Web API as an **asynchronous** import. The
   server returns an *async operation id* and keeps working in the background.
3. Each Finance & Operations package is uploaded to the environment and then the whole set is
   deployed in one call, which returns a single async operation id for the batch.
4. All of those ids — plus the connection details needed to query them — are written to a JSON
   **state file**.
5. `Get-PpAsyncDeploymentStatus` reads the state file and queries each operation's current status.
   Because everything runs server-side, you can run the status check from a completely separate
   session, even after closing the one that started the deployment.

---

## Prerequisites

- **PowerShell 7.0+** (Windows, macOS, or Linux).
- A **Dataverse environment** URL, e.g. `https://your-org.crm.dynamics.com`.
- A **Microsoft Entra ID app registration** with a **client secret**, added as an **application
  user** in your environment with permission to import solutions and deploy packages (typically the
  *System Administrator* security role). See [docs/app-registration-setup.md](docs/app-registration-setup.md).
- An **unzipped deployment package** — a folder containing a `PackageAssets` sub-folder with an
  `ImportConfig.xml` manifest and the solution/package files it references. This is the same package
  layout produced by the standard Power Platform packaging tools.

---

## Set up the app registration

This module signs in as an **application** (app-only, unattended), so you need a Microsoft Entra ID
app registration with a client secret, added to your environment as an **application user**. It's a
one-time setup of about five minutes.

**See [docs/app-registration-setup.md](docs/app-registration-setup.md) for step-by-step
instructions** — registering the app, creating the secret, adding the application user, and whether
the app needs separate D365 / Finance & Operations access (it doesn't).

---

## Install

Clone or copy this repository, then import the module:

```powershell
Import-Module ./PowerPlatformAsyncDeploy.psd1 -Force
```

To make it importable by name from any session, copy the folder into one of your
`$env:PSModulePath` locations (for example `~/.local/share/powershell/Modules/PowerPlatformAsyncDeploy`
on macOS/Linux, or `~/Documents/PowerShell/Modules/PowerPlatformAsyncDeploy` on Windows), then:

```powershell
Import-Module PowerPlatformAsyncDeploy
```

---

## The connection string

Both functions authenticate with a Dataverse connection string using a client secret:

```
AuthType=ClientSecret;Url=https://your-org.crm.dynamics.com;Tenant=<tenant-id>;ClientId=<app-id>;ClientSecret=<secret>
```

| Key | Required | Notes |
| --- | --- | --- |
| `Url` | Yes | Your environment URL. |
| `ClientId` | Yes | Application (client) ID of the app registration. `ApplicationId` is also accepted. |
| `ClientSecret` | Yes | Client secret for that app registration. |
| `Tenant` | Recommended | Directory (tenant) ID. Defaults to `common` if omitted. |

> **Keep secrets out of source control.** Build the connection string from environment variables or a
> secret store rather than hard-coding it. The state file written by `Start-PpAsyncDeployment`
> contains this connection string, so it is git-ignored by default — treat it as a secret.

---

## Usage

### 1. Start a deployment

```powershell
$connectionString = "AuthType=ClientSecret;Url=https://your-org.crm.dynamics.com;Tenant=$tenantId;ClientId=$clientId;ClientSecret=$clientSecret"

Start-PpAsyncDeployment `
    -PackagePath 'C:\path\to\unzipped\package' `
    -ConnectionString $connectionString
```

This submits every artifact and writes `./pp-async-deployment-state.json`. It returns a summary
object and prints the exact command to check status.

**Parameters**

| Parameter | Required | Default | Description |
| --- | --- | --- | --- |
| `-PackagePath` | Yes | — | Folder containing `PackageAssets\ImportConfig.xml`. |
| `-ConnectionString` | Yes | — | Dataverse connection string (see above). |
| `-DeploymentId` | No | `deploy-<timestamp>` | Friendly name for this run. |
| `-StateFilePath` | No | `./pp-async-deployment-state.json` | Where to write the state file. |
| `-OverwriteUnmanagedCustomizations` | No | `$false` | Passed to each solution import. |
| `-PublishWorkflows` | No | `$true` | Passed to each solution import. |

A named deployment with a custom state-file location:

```powershell
Start-PpAsyncDeployment `
    -PackagePath 'C:\path\to\unzipped\package' `
    -ConnectionString $connectionString `
    -DeploymentId 'release-2026-06' `
    -StateFilePath 'C:\deploys\release-2026-06.json'
```

### 2. Check status

```powershell
Get-PpAsyncDeploymentStatus -StateFilePath './pp-async-deployment-state.json'
```

It prints a line per operation and returns an object whose `OverallStatus` is one of
`InProgress`, `Succeeded`, or `Failed`.

**Parameters**

| Parameter | Required | Default | Description |
| --- | --- | --- | --- |
| `-StateFilePath` | No | `./pp-async-deployment-state.json` | The state file written by `Start-PpAsyncDeployment`. |

### 3. Poll until done

```powershell
do {
    Start-Sleep -Seconds 60
    $status = Get-PpAsyncDeploymentStatus -StateFilePath './pp-async-deployment-state.json'
} while ($status.OverallStatus -eq 'InProgress')

Write-Host "Final status: $($status.OverallStatus)"
```

A ready-to-edit version of this is in [`examples/deploy-and-poll.ps1`](examples/deploy-and-poll.ps1).

### Run it from a pipeline

To deploy from **Azure DevOps** (YAML or classic), see
[docs/azure-devops-pipeline.md](docs/azure-devops-pipeline.md) — a single PowerShell step that starts
the deployment, waits for it, and fails the pipeline if it fails.

---

## Understanding the status output

Each operation reports one of the standard Dataverse async operation statuses:

| Code | Meaning | | Code | Meaning |
| --- | --- | --- | --- | --- |
| 0 | Waiting For Resources | | 22 | Canceling |
| 10 | Waiting | | 30 | **Succeeded** |
| 20 | In Progress | | 31 | **Failed** |
| 21 | Pausing | | 32 | **Canceled** |

`Get-PpAsyncDeploymentStatus` rolls these up into a single `OverallStatus`:

- **InProgress** — at least one operation has not reached a terminal state.
- **Succeeded** — every operation reached `Succeeded`.
- **Failed** — every operation is terminal and at least one `Failed` or was `Canceled`.

---

## The state file

`Start-PpAsyncDeployment` writes a JSON file recording the deployment id, the connection string, and
the async operation ids for each solution and the F&O batch. `Get-PpAsyncDeploymentStatus` reads it
to know what to query. Keep it for the lifetime of the deployment; you can delete it once the work
has finished.

```jsonc
{
  "DeploymentId": "deploy-20260605-101500",
  "StartTime": "2026-06-05T10:15:00.0000000+00:00",
  "Status": "InProgress",
  "Solution": [
    { "FileName": "MySolution_managed.zip", "AsyncOperationId": "…", "StartTime": "…" }
  ],
  "Fno": {
    "Packages": [ { "FileName": "MyFnoPackage.zip", "FnoPackageId": "…", "ModuleName": "…" } ],
    "BuildType": "Full",
    "PackageType": "Release",
    "AsyncOperationId": "…"
  }
}
```

> Because it contains your connection string, the state file is git-ignored by default. Store it
> securely.

---

## Notes & limitations

- **F&O packages in one package must share BuildType and PackageType.** They are deployed as a single
  batch; `Start-PpAsyncDeployment` verifies they match and stops if they don't.
- **External entries other than `xpp`** in `ImportConfig.xml` are not handled and are skipped with a
  warning.
- **Solutions are submitted in manifest order**, but Dataverse runs the imports asynchronously and
  may process them concurrently. If your solutions have install-order dependencies, deploy dependent
  layers in separate runs and confirm each has `Succeeded` before starting the next.

---

## License

[MIT](LICENSE)
