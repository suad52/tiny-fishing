# Tiny Fishing

A Roblox fishing game, with its source managed through [Rojo](https://rojo.space).

Play it on Roblox: https://www.roblox.com/games/83205688837463/Tiny-Fishing

## What's here

- `src/ServerScriptService` - server game logic and services
- `src/ReplicatedStorage` - shared modules and asset models
- `src/StarterPlayerScripts` - client scripts
- `src/ReplicatedFirst`, `src/ServerStorage` (fishing rods, dev tools)
- `readable-scripts/` - UI controllers (menus, HUD) and other scripts that Rojo had to bundle into binary `.rbxm` files, extracted as plain text so you can read them
- `default.project.json` - Rojo project file

The `.rbxm` files in `src/` are models and UI that Rojo can't represent as plain files. The world map and terrain in Workspace are not included in this repo, and old backup copies of scripts are left out.

## Using it

```
rojo build -o TinyFishing.rbxlx
```

Or run `rojo serve` and connect from the Rojo plugin in Studio.

