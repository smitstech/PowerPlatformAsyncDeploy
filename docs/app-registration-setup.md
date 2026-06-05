# Set up the app registration

This module signs in as an **application** (app-only, unattended), so you need a Microsoft Entra ID
app registration with a client secret, and that app must be added to your environment as an
**application user**. It's a one-time setup of about five minutes.

The three values you collect here — **Client ID**, **Tenant ID**, and **Client secret** — go into the
[connection string](../README.md#the-connection-string) the module uses.

## 1. Register the application (Microsoft Entra ID)

1. In the [Azure portal](https://portal.azure.com), go to **Microsoft Entra ID → App registrations →
   New registration**.
2. Give it a name (e.g. `PowerPlatformAsyncDeploy`). Leave **Supported account types** as
   *Accounts in this organizational directory only (single tenant)*. **No redirect URI is needed** —
   this app never signs a user in interactively.
3. Select **Register**, then from the app's **Overview** page copy:
   - **Application (client) ID** → your `ClientId`
   - **Directory (tenant) ID** → your `Tenant`

## 2. Create a client secret

1. In the app, go to **Certificates & secrets → Client secrets → New client secret**.
2. Add a description and an expiry, select **Add**, then **copy the secret Value immediately** — it
   is shown only once. This is your `ClientSecret`.

> For production, a **certificate** is more secure than a shared secret; this module currently uses
> the secret-based flow.

## 3. Add the app as an application user in your environment

This is the step that actually grants access. Dataverse authorizes the app through an **application
user** record — not through Entra "API permissions".

1. Open the [Power Platform admin center](https://admin.powerplatform.microsoft.com) → **Environments**
   → select your environment.
2. Go to **Settings → Users + permissions → Application users → + New app user**.
3. Select **Add an app** and pick your registration by name / client ID.
4. Choose the **Business unit**, then assign a **security role**. **System Administrator** is the
   simplest and covers both solution import and package deployment. (A custom role works too, as long
   as it grants solution-import privileges plus create/read/write on the package-deployment tables and
   the deploy action.)
5. Select **Create**.

That's all — for this app-only Dataverse flow you do **not** need to add any Entra **API
permissions**; the application user above is what authorizes the calls.

## Does the app also need separate D365 / Finance & Operations access?

**No separate credentials, app registration, or login.** Both halves of a deployment authenticate
with the *same* Dataverse token:

- **Dataverse solutions** are imported through the Dataverse Web API.
- **Finance & Operations packages** are also driven through Dataverse — the module creates package
  records and calls a Dataverse action that orchestrates the F&O deployment server-side.

So the single application user is all the client needs. It does need to be allowed to work with the
F&O package-deployment tables and action in Dataverse, which **System Administrator** covers. Some
tenants enforce additional platform configuration on the F&O side; if an F&O batch is rejected while
solutions import fine, that's where to look — but it is not a second set of app credentials.
