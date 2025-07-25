# Smart Clone

Smart clone is a simple utility tool that allows fast cloning from GitHub without requiring a full URL, through a simple TUI.

## Features
- **Search**: Searches GitHub repositories
- **Priorities**: Prioritise specific accounts so that they show up higher in the list
- **HTTPS or SSH**: Allow both HTTPS and SSH, although SSH is the default
- **Git Flags**: Pass any extra flags into the `git clone` command
- **Private Access**: Supports the usage of a GitHub Personal Access Token to search for private repos.

## Requirements
- bash
- curl
- jq
- fzf
- git

## Usage
**Cloning**
```
smartclone clone <repo-name> [--https] [-- <git flags>...]
```

**Configuring**
The `config` command allows prioritising certain accounts, and adding or removing your PAT.
These configurations are saved to `$HOME/.smartclonerc`

```
smartclone config add <alias>
smartclone config remove <alias>
smartclone config set-token <token>
smartclone config clear-token
```

**PAT**
To view private repositories, your Personal Access Token needs:
- All repositories
- Repository Permissions > Metadata: Read-only

Note that this token is *not* used for cloning the repositories. It is recommended that you use git directly to configure repository access.
