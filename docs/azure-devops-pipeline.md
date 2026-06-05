# Deploy from an Azure DevOps pipeline

You can run `PowerPlatformAsyncDeploy` from Azure DevOps in **either a YAML or a classic pipeline**.
Both use the same one-line idea: run a single PowerShell step that calls the committed helper script
[`examples/pipeline-deploy.ps1`](../examples/pipeline-deploy.ps1). That script imports the module,
starts the deployment, waits for it to finish, and **fails the pipeline if the deployment fails** —
so there is almost nothing to get wrong in the pipeline itself.

> **Prerequisite:** complete the [app registration setup](app-registration-setup.md) first. You'll
> need the **environment URL**, **tenant ID**, **client ID**, and **client secret**.

---

## Step 1 — Store the credentials (once)

Create four pipeline variables. The simplest place is **Pipelines → Library → + Variable group**
(or the pipeline's own **Variables**):

| Variable | Example | Secret? |
| --- | --- | --- |
| `EnvironmentUrl` | `https://your-org.crm.dynamics.com` | No |
| `TenantId` | `00000000-0000-0000-0000-000000000000` | No |
| `ClientId` | `00000000-0000-0000-0000-000000000000` | No |
| `ClientSecret` | *(the secret value)* | **Yes** — click the lock icon |

> Marking `ClientSecret` as secret keeps it masked in logs. For extra safety you can link the
> variable group to **Azure Key Vault** instead of typing the secret in.

The helper script reads the secret from an environment variable named `PP_CLIENT_SECRET` (never as a
command-line argument), so it stays out of logs and process listings.

---

## Step 2a — YAML pipeline

Add this to your `azure-pipelines.yml`. Adjust `PackagePath` to wherever your unzipped package lives
on the agent (your repo, or a downloaded build artifact).

```yaml
trigger:
  - main

pool:
  vmImage: 'windows-latest'   # 'ubuntu-latest' also works

variables:
  - group: powerplatform-deploy   # the variable group from Step 1

steps:
  - checkout: self

  - task: PowerShell@2
    displayName: 'Async deploy to Power Platform'
    inputs:
      pwsh: true                                   # PowerShell 7 is required
      filePath: 'examples/pipeline-deploy.ps1'
      arguments: >
        -EnvironmentUrl "$(EnvironmentUrl)"
        -TenantId "$(TenantId)"
        -ClientId "$(ClientId)"
        -PackagePath "$(Build.SourcesDirectory)/package"
    env:
      PP_CLIENT_SECRET: $(ClientSecret)            # maps the secret to the env var
```

That's the whole integration. The step succeeds only if the deployment reaches **Succeeded**.

---

## Step 2b — Classic (designer) pipeline

The same thing through the UI:

1. **Pipelines → Edit → Variables** (or **Variable groups → Link**): add the four variables from
   Step 1, and mark `ClientSecret` as secret (lock icon).
2. Add a **PowerShell** task to the job and configure it:
   - **Type:** *File Path*
   - **Script Path:** `examples/pipeline-deploy.ps1`
   - **Arguments:**
     ```
     -EnvironmentUrl "$(EnvironmentUrl)" -TenantId "$(TenantId)" -ClientId "$(ClientId)" -PackagePath "$(Build.SourcesDirectory)/package"
     ```
   - **Advanced → Use PowerShell Core:** ✔ (this is the `pwsh: true` equivalent)
   - **Environment Variables:** add `PP_CLIENT_SECRET` = `$(ClientSecret)`
3. Make sure the agent job uses a **windows-latest** or **ubuntu-latest** hosted agent.

---

## Where does the package come from?

`PackagePath` must point at an **unzipped** package folder — one containing
`PackageAssets/ImportConfig.xml`. Common options:

- **Committed in the repo** → use `"$(Build.SourcesDirectory)/package"`.
- **Produced by an earlier build stage** and published as a pipeline artifact → add a
  **Download build artifacts** step first, then point `PackagePath` at the download location, e.g.
  `"$(Pipeline.Workspace)/package"`.

---

## Tuning and troubleshooting

| Symptom | Fix |
| --- | --- |
| `The term 'Start-PpAsyncDeployment' is not recognized` | The agent ran Windows PowerShell 5.1. Ensure **`pwsh: true`** (YAML) / **Use PowerShell Core** (classic). |
| `PP_CLIENT_SECRET environment variable is not set` | Add the `env:` mapping (YAML) or the environment variable (classic). |
| Pipeline runs forever | Long deployments are normal, but the helper stops itself after `-TimeoutMinutes` (default 120). Pass a larger value if needed. |
| Want a faster/slower status check | Pass `-PollSeconds` (default 60). |

The helper exits non-zero on a failed or timed-out deployment, so no extra "fail the build" logic is
needed.
