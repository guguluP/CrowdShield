# CrowdShield stack update (existing `crowdshield-phase1` in ap-south-2)

## What changed
1. **template.yaml** — Lambda `CodeUri` is now local folders (`src/incidents/`, etc.).
   SAM uploads code automatically (`resolve_s3 = true`). **No `LambdaCodeBucket` parameter.**
2. **incidents** — POST allowed for **any authenticated** user (Public + Command).
3. **samconfig.toml** — region **ap-south-2**.

Your 75 existing resources stay; this is an **update**, not a new stack.

## On your Mac

1. Replace files in `Desktop/CrowdShield/aws/`:
   - `template.yaml` ← this package’s `template.yaml`
   - `samconfig.toml` ← this package’s `samconfig.toml`
   - `src/incidents/app.py` ← this package’s `incidents-app.py` (rename to `app.py`)

2. Edit `samconfig.toml` → set `AlertEmail=your@email.com`

3. Deploy:
```bash
cd ~/Desktop/CrowdShield/aws
sam build
sam deploy
```

Confirm the changeset when prompted.

## Console-only (no CLI)

### Fastest: update only Incidents Lambda
1. Zip `src/incidents/` (app.py + crowdshield_common.py).
2. Lambda console (ap-south-2) → function `crowdshield-dev-incidents`.
3. Upload zip → Save.

### Full template update in Console
1. CloudFormation → `crowdshield-phase1` → Update.
2. Replace template → upload new `template.yaml`.
3. Parameters: keep EnvironmentName=dev, VenueIdDefault=technova-festival-grounds, AlertEmail=yours.
4. **Important:** With local CodeUri, Console update alone may **not** re-upload Lambda code from your laptop. Prefer `sam build && sam deploy` for code changes, or upload each function zip manually.

## After update
Public app → report incident on `technova-festival-grounds` → portal Refresh → should appear.
