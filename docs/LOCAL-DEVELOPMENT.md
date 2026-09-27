# Local development

## Backend and rescue dashboard

From `backend/CrisisMeshBackend`, configure the demo rescue and administrator
accounts in the current PowerShell session before starting the backend:

```powershell
$env:DemoUsers__RescueEmail = "rescue@example.local"
$env:DemoUsers__RescuePassword = "<choose-a-local-password>"
$env:DemoUsers__AdminEmail = "admin@example.local"
$env:DemoUsers__AdminPassword = "<choose-a-local-password>"
dotnet run --urls http://localhost:5249
```

The backend reads these values from environment variables and creates the
configured demo accounts when it starts. Do not commit real passwords or local
database files. The development CSV path defaults to
`../../database/datasets/dataset.csv` relative to the backend working directory.
Override it with `Dataset__CsvPath` if your dataset is stored elsewhere.

Open `http://localhost:5249/` for the workspace selector and sign in to view the
rescue dashboard. Keep this HTTP-only setup on a trusted local network; configure
HTTPS and production credentials before deploying the backend publicly.
