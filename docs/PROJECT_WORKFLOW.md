# One repository, three work surfaces

Canonical GitHub repository: https://github.com/Anshuman-Arun/driving-game
Default branch: main. Keep it stable; feature branches and pull requests for code.

## 1. ChatGPT Project (conversation organization)
Create a ChatGPT Project named **Aster Valley — Driving Game** and paste the text of docs/CHATGPT_PROJECT_INSTRUCTIONS.md into its Project instructions.
Move the existing racing-game planning conversation into that ChatGPT Project using the chat menu's **Move to project** action where available.
Connect GitHub in ChatGPT and authorize Anshuman-Arun/driving-game. Ask ChatGPT to inspect the repository's files, branches, PRs and issues rather than relying on potentially outdated project-file uploads.
Current ChatGPT Projects documentation lists Google Drive and Slack as supported linked project sources, not GitHub. Put this GitHub repository URL into project instructions, and select/use the connected GitHub app within chats to read the live repository on demand.

IMPORTANT: A ChatGPT Project is NOT a two-way synchronized folder. Uploaded Project files are snapshots unless the UI explicitly indicates a live linked source. GitHub commits made by Antigravity are visible only after push. Ask ChatGPT to refresh from GitHub when beginning a new work session.

Suggested Project sources/uploads (ONLY if needed because live GitHub source cannot be linked):
- docs/GAME_DESIGN.md
- docs/TECHNICAL_ARCHITECTURE.md
- docs/IMPLEMENTATION_PLAN.md
- docs/PROJECT_STATUS.md
Do not upload the ZIP, duplicate README + MASTER_CONTEXT, .gitignore, .gitattributes, addons or binary textures as Project sources. Don't treat static copies as more authoritative than GitHub.

## 2. ChatGPT coding / Codex
Choose the GitHub repository Anshuman-Arun/driving-game as the task repository, on a fresh feature branch/worktree; read AGENTS.md and docs/PROJECT_STATUS.md.
Ask for focused milestones, run tests where possible, review PR/diff and merge when accepted.
Regular GitHub access in ChatGPT is generally for reading/searching code, not live local-file editing; use Codex or Work for coding changes, or an explicitly authorized GitHub write action where available. ChatGPT cannot automatically access Antigravity's unpushed working tree.

## 3. Gemini Antigravity local workspace
On Windows install Git, Git LFS and Godot 4.7.2 standard build, then clone this existing remote (do NOT create a new repo):
    git lfs install
    git clone https://github.com/Anshuman-Arun/driving-game.git
    cd driving-game
Open that folder in Antigravity via Open Folder / Add Folder (local Git checkout). Keep Antigravity work on a feature branch.
    git switch -c feat/p0-driving
Give the agent prompts/FIRST_EXECUTION_PROMPT.md and tell it to read AGENTS.md. After working, require commit + push:
    git status
    git add -A
    git commit -m "feat: first driving prototype"
    git push -u origin feat/p0-driving
Then open/review a PR against main. Do NOT have ChatGPT and Antigravity edit the same branch concurrently.
When a PR merges, fetch/pull main into the local checkout before the next task.

## Source-of-truth order
1. GitHub current main / accepted PR / docs/PROJECT_STATUS.md
2. Branch diff and verified test evidence (for in-progress work)
3. ChatGPT Project instructions and current chat
4. Old chat history and uploaded document snapshots

## Safety and housekeeping
Never commit tokens, saved credentials, generated .godot cache, or unlicensed assets. Use small batches, test what is feasible, and preserve notices. See docs/GITHUB_SETUP.md.
