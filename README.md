# claude-code-nix

Portable Claude Code configuration as a Home Manager module.

Drop this into your `flake.nix`, set a few options, and any machine — laptop,
Coder workspace, VM — gets the same Claude Code setup: hooks, agents,
`CLAUDE.md`, plugins, and permissions.

This module does **not** install the Claude Code CLI itself. Install it
however you prefer (npm, nix, fnm). The module only manages `~/.claude/`.

## Usage

In your Home Manager flake:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    claude-code-nix.url = "github:pawelwlazlo/claude-code-nix";
  };

  outputs = { nixpkgs, home-manager, claude-code-nix, ... }: {
    homeConfigurations."me" = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        claude-code-nix.homeManagerModules.default
        {
          programs.claudeCode = {
            enable = true;
            enableNerdbrain = true;
            gitHostAliases."simgit.example.com" = "example";
            extraPermissions = [ "Bash(bun:*)" ];
          };
        }
      ];
    };
  };
}
```

## Options

| Option | Type | Default | Description |
|---|---|---|---|
| `enable` | bool | `false` | Enable Claude Code config management |
| `enableNerdbrain` | bool | `false` | Wire the nerdbrain Obsidian SessionStart hook + add nerdbrain section to `CLAUDE.md` |
| `gitHostAliases` | attrs of str | `{}` | Map verbose git hosts to short slugs (used by nerdbrain) |
| `extraPermissions` | list of str | `[]` | Additional `settings.json` permissions.allow entries |
| `enabledPlugins` | attrs of bool | (17 defaults) | `plugin@marketplace -> bool` map |
| `extraMarketplaces` | attrs | (4 defaults) | `extraKnownMarketplaces` block for `settings.json` |

## What's managed vs. what isn't

**Managed by this module** (overwritten on every `home-manager switch`):

- `~/.claude/settings.json` — generated from options
- `~/.claude/CLAUDE.md` — generated (with/without nerdbrain section)
- `~/.claude/nerdbrain.aliases` — generated from `gitHostAliases`
- `~/.claude/hooks/` — copied verbatim from this repo
- `~/.claude/agents/` — copied verbatim from this repo

**Not touched** (per-machine state, written by Claude at runtime):

- `~/.claude/sessions/`, `~/.claude/projects/`, `~/.claude/history.jsonl`
- `~/.claude/cache/`, `~/.claude/plugins/`, `~/.claude/skills/`
- `~/.claude/settings.local.json` (per-machine permissions overrides)

## Layout

```
.
├── flake.nix
├── modules/default.nix      # the home-manager module
└── home/
    ├── CLAUDE-base.md       # global CLAUDE.md base
    ├── CLAUDE-nerdbrain.md  # nerdbrain section (appended when enabled)
    ├── agents/              # 33 GSD agent definitions
    └── hooks/               # 13 hook scripts (gsd-*, nerdbrain-load.sh)
```

## License

MIT
