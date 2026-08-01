# UnifiedCombat Build Commands

All commands below are run from:

- `C:\Program Files (x86)\Windower\addons\UnifiedCombat`

## WinForms UI (direct addon hub, no Python middleware)

Release build:

```powershell
dotnet build .\UnifiedCombatWinForms\UnifiedCombatWinForms.csproj -c Release
```

Release publish (`win-x64`, single-file, framework-dependent):

```powershell
dotnet publish .\UnifiedCombatWinForms\UnifiedCombatWinForms.csproj -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true
```

Publish output directory:

- `.\UnifiedCombatWinForms\bin\Release\net9.0-windows\win-x64\publish\`

## Notes

- UnifiedCombat now uses direct WinForms-to-addon hub connectivity.
- No `unified_combat_ui.py`/PyInstaller build step is required for normal operation.
