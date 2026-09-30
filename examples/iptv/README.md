# Controlled IPTV validation example

This optional example shows how an application-specific wrapper can reuse the
generic managed cycle while adding fixture hosting and persisted receipt
validation. It is not required by the core protocol.

`Run-IptvCycle.ps1` accepts an already-built app directory and optional FFPFSC
image. `Run-IptvCodecCycle.ps1` additionally requires the root of the IPTV app project
([ProsperoTV](https://github.com/blackbearreloaded/ProsperoTV))
because it calls that project's MkPFS and UFS2 setup scripts.

Generated MPEG-TS fixtures are intentionally ignored. Prepare the files listed
in [fixtures/README.md](fixtures/README.md) locally before running the codec
cycle.

Example:

```powershell
.\examples\iptv\Run-IptvCycle.ps1 `
  -AppDirectory C:\path\to\PPSA88000 `
  -ImagePath C:\path\to\PPSA88000.ffpfsc `
  -TitleId PPSA88000 `
  -Ps5Host 192.0.2.10   # or set $env:PS5_HOST
```

The wrapper owns the declared PS5 lock for the complete run. Do not launch it
while another agent owns the console.
