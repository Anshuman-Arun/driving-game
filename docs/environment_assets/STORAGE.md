# Source-art storage and public repository policy

GitHub is canonical for source code, shaders, manifests, approved optimized production derivatives and offline build instructions. The repo is now public; do not publish private account metadata or assets without individual redistribution rights. Public standard Actions runners are free, but public visibility is not unlimited Git/LFS/artifact storage. Ordinary Git files >100 MiB are blocked; repo health matters; Git LFS tracks large binary versions and bandwidth against owner quota. See https://docs.github.com/en/repositories/creating-and-managing-repositories/repository-limits and https://docs.github.com/en/billing/concepts/product-billing/git-lfs. Actual account quota/billing balance must be checked by owner. Do not alter billing, delete artifacts, or purchase storage.

Use a **private Google Drive source-art archive** via Drive for desktop on the Windows host (folder Aster Valley - Source Art Library; user has the private folder link). Do NOT put the Drive folder link/ID, Windows absolute user path, credentials or tokens in public Git. Lead asks for local mounted path only if auto-discovery of the folder in mounted Drive fails. Use local environment variable ASTER_ASSET_SOURCE_ROOT if configured; resolve path explicitly, never use credentials in scripts. Example layout:
- source/PolyHaven/{models,textures,hdris}/<asset-id>/<resolution>/ (untouched source and provenance)
- source/ambientCG/<asset-id>/ (original archive and provenance)
- reviews/ (contact sheets and APPROVED/REJECTED/HOLD inventory)
- working/ (only if necessary; prefer local SSD outside Drive for Blender temporary data)
- deliverables/ (optional archived optimized packs and QA evidence)
- manifests/ (source library hash index and immutable batch reports)

Single acquisition agent stages on local SSD outside repo, runs downloader, validates checksums then copies final source files and provenance into Drive archive. Avoid concurrent writers to same ID. Do not edit a master after publication; add versioned directories if upstream changes. Check both local free space and actual Drive remaining capacity (Google One/Drive storage page) before batch; start with 16 GiB local budget and expand after evidence. Drive for desktop streaming saves disk but offline files must be explicitly available; never have Godot depend on streamed files or Drive availability. If syncing is unavailable, preserve verified local archive and report cloud backup pending, do not claim success. Use manifest/hash verification after sync; no private Drive links in Git.

Example command from repository:
```powershell
py -3 tools/environment_assets/acquire.py --scope expanded --resolution 4k --budget-mib 16384 --output D:\AsterValleyAssetSource
```
Replace example path with actual writable local external staging folder. Do not run directly in Git checkout. The 4 uploaded sources can be copied and verified from asset_library/environment_sources. Do not redownload duplicates needlessly; archive those exact masters and include their provenance. For an unavailable 4K tier, explicitly rerun 2K for that asset and record. Source inventory is intentionally broader than final asset set.

Production asset publication: audit license and visual quality; export optimized GLBs/textures/LODs with source hashes and authored changes, only approved derivatives in repo. Verify existing .gitattributes and remaining LFS storage/bandwidth before uploading; use Git LFS where configured, inspect pointers and test fresh fetch. Never bypass LFS by splitting or hiding large files; never dump raw 16+ GiB library into git history. If LFS quota blocks production publication, retain local/Drive versioned pack and manifest, notify user; keep offline export self-contained. GitHub Releases are for actual versioned playable exports or curated packs, not an unlimited bulk source archive. No automatic public Drive sharing.

Google Drive connection was verified by creating a private folder, but the connector does not expose account-wide storage quota or a remote-host arbitrary URL ingestion API; source files must be transferred through the local Windows client or another authorized file-transfer path. Do not assume the folder has been populated.
