# Rules for AI agents working in this repo

This folder is David's Personal Hub (GitHub Pages: https://ganymededl.github.io/liudavid_od4b_root/).
More than one agent edits it (Scout, Claude/Cowork, other sessions), and a GitHub Action commits a
daily podcast refresh. These rules keep edits from colliding.

## Who does what
- **Scout is the only git operator.** Only Scout runs `git pull`, `commit` and `push` here.
- **Claude (Cowork) only edits files.** It never runs git in this folder (its shell cannot delete
  files, so git leaves stale `.lock` files behind). When it finishes, it hands David a one-line Scout
  prompt to publish.
- Any other agent: edit files only, then ask David to have Scout publish.

## Before and after editing
1. Scout pulls first (`git pull`) before editing, committing or pushing. The repo is set to
   `pull.rebase=true` and `rebase.autostash=true`.
2. Publish soon after an edit. Unpublished edits are what turn into conflicts.
3. One agent per file at a time. Finish and push before another agent edits the same file,
   especially the card list (`tools: [...]`) in `index.html`.
4. On a rebase conflict, keep both sides' changes unless David says otherwise, and tell him what
   was merged.

## Commits
- Author email: `17201905+ganymededl@users.noreply.github.com` (GitHub rejects the private
  address, GH007).
- Non-interactive rebases: set `GIT_EDITOR=true` so git doesn't wait for an editor.

## Never publish
- `_archive/`, `DemoIQ_Liudavid_Files/` and anything else in `.gitignore`.
- Passwords, keys, tenant credentials, or real customer/institution data.
