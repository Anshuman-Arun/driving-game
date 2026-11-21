# Asset and dependency license ledger

**Status: candidates only.** No third-party models/textures or add-ons are currently committed. Never assume GitHub availability equals reuse permission.

| Source | Intended use | License / caveat |
|---|---|---|
| [Poly Haven](https://polyhaven.com/license) | PBR asphalt, rock, earth, HDRI, models | CC0 |
| [ambientCG](https://ambientcg.com/) | Gravel, grass, rock and pavement PBR | CC0 |
| [Kenney Car Kit](https://kenney.nl/assets/car-kit) | Starter vehicles and traffic | CC0; visual style may be too simple for hero cars |
| [Kenney Racing Kit](https://kenney.nl/assets/racing-kit) | Prototype barriers and roadside props | CC0; stylized |
| [Spectral GT RS](https://github.com/JaronKBragg7337/spectral-gt-rs) | Detailed fictional sports car candidate | Project advertises CC0; inspect model, materials and rig before adopting |
| [Terrain3D](https://github.com/TokisanGames/Terrain3D) | Terrain plugin | MIT; preserve license; sample assets require separate checks |
| [Godot Road Generator](https://github.com/TheDuckCow/godot-road-generator) | Roads and lanes | MIT; preserve license; pin v0.9.5 |
| [Godot Easy Vehicle Physics](https://github.com/DAShoe1/Godot-Easy-Vehicle-Physics) | Vehicle physics controller | MIT; preserve license; pin exact tested SHA |
| [OpenCity](https://github.com/webgl-games/opencity) | Optional traffic/city reference | MIT code; do not copy third-party assets without individual verification |

## Every imported asset record
```text
asset_id:
source_url:
author:
source_file_or_pack:
license:
license_notice_url_or_local_path:
downloaded_on:
installed_at:
modified:
notes:
```

For MIT dependencies include original copyright/permission notices. Prefer CC0 for game assets; for any CC BY assets, retain complete required attribution and change notes.

**Prohibited:** ripped Forza/commercial-game files; unlicensed car meshes; copyrighted manufacturer logos/textures without rights; commercial music; entire demo packs copied without license checking. If ownership is unclear, use original procedural placeholders or omit the asset.

Before export, inventory assets/, world_data/ and addons/, write THIRD_PARTY_NOTICES.md for applicable dependencies and ensure notices are included where required.
