# bootstrap-dotfiles

VPS bootstrap script + dotfiles. Repo: `bbastanza/bootstrap-dotfiles`

## Structure
- `bootstrap.sh` — main script, run as root on fresh VPS. Args: `USERNAME GIT_EMAIL [VPS_NAME]`
- `nvim/` — neovim config, symlinked to `~/.config/nvim`
- `broot/` — broot config, symlinked to `~/.config/broot`

## Key Design Decisions
- Script must be **idempotent** — safe to re-run
- Supports both apt (Debian/Ubuntu) and dnf (Fedora)
- Fedora 43+ uses dnf5 syntax (`addrepo --from-repofile=` not `--add-repo`)
- Dotfiles cloned to `~/.dotfiles` on VPS, configs symlinked from there
- Starship prompt shows VPS name (no brackets/styling — TOML escaping issues)
- gh auth checked before prompting; ssh key add uses `|| true` for dedup
- zsh path added to `/etc/shells` before `chsh` (required on some distros)
- Git credentials reused from existing `.gitconfig` on re-runs

## Status
- Script working on Fedora 43 VPS
- dnf5 config-manager syntax just fixed (not yet pushed)

## TODOs
- Delete old `bbastanza/nvim-dotfiles` repo (needs `delete_repo` scope)
- Remove old `~/Projects/Scripts/bootstrap.sh` (outdated copy)
