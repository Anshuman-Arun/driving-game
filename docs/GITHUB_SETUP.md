# Windows / GitHub / Antigravity setup

**Repository already exists. Do not run git init or gh repo create.**
Canonical remote: https://github.com/Anshuman-Arun/driving-game
Visibility: private; default branch: main.

## Install once
1. Git for Windows: https://git-scm.com/downloads/win
2. Git LFS: https://git-lfs.com/
3. Godot 4.7.2 standard (not .NET): https://godotengine.org/download/archive/4.7.2-stable/
4. Google Antigravity: https://antigravity.google/
5. GitHub CLI: https://cli.github.com/ (optional for PR creation)

## Clone this existing repository
Open Windows PowerShell in the parent directory where you want the game folder, for example C:\\Projects.

```powershell
git --version
git lfs version
git lfs install
git clone https://github.com/Anshuman-Arun/driving-game.git
cd driving-game
git status
git remote -v
```

GitHub will require authentication to clone a private repository; Git Credential Manager (bundled with Git for Windows) can guide browser authentication. Do not paste tokens into source files or prompts.

**Open exactly this cloned `driving-game` folder in Antigravity.** Do not extract the old planning ZIP into a separate work directory and do not create a second unrelated repository.

## Start first implementation on a branch
```powershell
git switch -c feat/p0-driving
```
Tell Antigravity to read AGENTS.md and prompts/FIRST_EXECUTION_PROMPT.md. Ask it to implement P0 and P1 only. Review its changes before committing. After verifying basic checks:

```powershell
git status
git add -A
git commit -m "feat: add first playable driving prototype"
git push -u origin feat/p0-driving
```

If commit fails due to absent identity:
```powershell
git config --global user.name "YOUR GITHUB NAME"
git config --global user.email "YOUR VERIFIED GITHUB EMAIL"
```
Use your actual details, not literal placeholders.

Open a pull request on GitHub from feat/p0-driving into main, review it and merge after acceptance. Never have ChatGPT and Antigravity simultaneously modify the same branch.

## Start next session after a merge
```powershell
git switch main
git pull --ff-only origin main
git switch -c feat/next-milestone
```

## Useful lightweight Godot checks
Godot executable path varies by installation; first locate it. From the cloned repository after project.godot exists:
```powershell
godot --headless --path . --editor --quit
```
Use the full executable path if Godot is not on PATH. Record console errors and exit codes. Actual keyboard, controller and physics feel still require real playtesting.

## Git LFS and generated data
The supplied .gitattributes tracks selected large binary source formats through Git LFS. Run git lfs install on every machine before committing those files. Do not commit .godot/ cache, builds/, exports/, secrets, or whole third-party demo libraries. Honor all asset licenses and preserve MIT notices.

## ChatGPT Project integration
See docs/PROJECT_WORKFLOW.md for ChatGPT Project sources, project instructions, Codex and Antigravity sharing. ChatGPT Project uploads are not equivalent to a live Git checkout. Always verify remote revisions before editing.
