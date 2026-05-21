{ config, lib, pkgs, ... }:

let
  cfg = config.programs.claudeCode;

  nodeBin = "${pkgs.nodejs_22}/bin/node";
  claudeDir = "${config.home.homeDirectory}/.claude";
  hooksDir = "${claudeDir}/hooks";

  defaultEnabledPlugins = {
    "reflexion@context-engineering-kit" = true;
    "customaize-agent@context-engineering-kit" = true;
    "ddd@context-engineering-kit" = true;
    "docs@context-engineering-kit" = true;
    "fpf@context-engineering-kit" = true;
    "git@context-engineering-kit" = true;
    "kaizen@context-engineering-kit" = true;
    "mcp@context-engineering-kit" = true;
    "sadd@context-engineering-kit" = true;
    "sdd@context-engineering-kit" = true;
    "tdd@context-engineering-kit" = true;
    "tech-stack@context-engineering-kit" = true;
    "claude-api@anthropic-agent-skills" = true;
    "document-skills@anthropic-agent-skills" = true;
    "example-skills@anthropic-agent-skills" = true;
    "superpowers@superpowers-marketplace" = true;
    "linear-cli@linear-skills" = true;
  };

  defaultMarketplaces = {
    context-engineering-kit = {
      source = {
        source = "github";
        repo = "NeoLabHQ/context-engineering-kit";
      };
    };
    anthropic-agent-skills = {
      source = {
        source = "github";
        repo = "anthropics/skills";
      };
    };
    superpowers-marketplace = {
      source = {
        source = "github";
        repo = "obra/superpowers-marketplace";
      };
    };
    linear-skills = {
      source = {
        source = "github";
        repo = "pawelwlazlo/linear-skills";
      };
    };
  };

  defaultPermissions = [
    "mcp__puppeteer__puppeteer_navigate"
    "mcp__puppeteer__puppeteer_screenshot"
    "mcp__puppeteer__puppeteer_evaluate"
  ];

  # Hook command builders — keep node/bash paths uniform.
  nodeHook = name: timeout: {
    type = "command";
    command = ''${nodeBin} "${hooksDir}/${name}"'';
  } // (lib.optionalAttrs (timeout != null) { inherit timeout; });

  bashHook = name: timeout: {
    type = "command";
    command = ''bash "${hooksDir}/${name}"'';
  } // (lib.optionalAttrs (timeout != null) { inherit timeout; });

  sessionStartHooks =
    lib.optional cfg.enableNerdbrain {
      matcher = "";
      hooks = [{
        type = "command";
        command = ''"${hooksDir}/nerdbrain-load.sh"'';
        timeout = 5;
      }];
    }
    ++ [
      { hooks = [ (nodeHook "gsd-check-update.js" null) ]; }
      { hooks = [ (bashHook "gsd-session-state.sh" null) ]; }
    ];

  settings = {
    env = {
      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
    };
    permissions = {
      allow = defaultPermissions ++ cfg.extraPermissions;
    };
    hooks = {
      SessionStart = sessionStartHooks;
      PostToolUse = [
        {
          matcher = "Bash|Edit|Write|MultiEdit|Agent|Task";
          hooks = [ (nodeHook "gsd-context-monitor.js" 10) ];
        }
        {
          matcher = "Read";
          hooks = [ (nodeHook "gsd-read-injection-scanner.js" 5) ];
        }
        {
          matcher = "Write|Edit";
          hooks = [ (bashHook "gsd-phase-boundary.sh" 5) ];
        }
      ];
      PreToolUse = [
        {
          matcher = "Write|Edit";
          hooks = [ (nodeHook "gsd-prompt-guard.js" 5) ];
        }
        {
          matcher = "Write|Edit";
          hooks = [ (nodeHook "gsd-read-guard.js" 5) ];
        }
        {
          matcher = "Write|Edit";
          hooks = [ (nodeHook "gsd-workflow-guard.js" 5) ];
        }
        {
          matcher = "Bash";
          hooks = [ (bashHook "gsd-validate-commit.sh" 5) ];
        }
      ];
    };
    statusLine = {
      type = "command";
      command = ''${nodeBin} "${hooksDir}/gsd-statusline.js"'';
    };
    enabledPlugins = cfg.enabledPlugins;
    extraKnownMarketplaces = cfg.extraMarketplaces;
  };

  # Compose CLAUDE.md: base + optional nerdbrain section.
  claudeMdText =
    let
      base = builtins.readFile ../home/CLAUDE-base.md;
      nerd = builtins.readFile ../home/CLAUDE-nerdbrain.md;
    in
      if cfg.enableNerdbrain then base + "\n\n" + nerd else base;

  # Compose nerdbrain.aliases file content from the aliases attrset.
  aliasesText =
    let
      header = ''
        # nerdbrain.aliases — managed by claude-code-nix.
        # Edit programs.claudeCode.gitHostAliases in your home.nix.
        # Format: <git-host>=<alias>   (alias: [a-z0-9-]+ only)

      '';
      lines = lib.mapAttrsToList (host: alias: "${host}=${alias}") cfg.gitHostAliases;
    in
      header + lib.concatStringsSep "\n" lines + (lib.optionalString (lines != []) "\n");
in
{
  options.programs.claudeCode = {
    enable = lib.mkEnableOption "Claude Code configuration management";

    enableNerdbrain = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable the nerdbrain Obsidian SessionStart hook and include the
        nerdbrain section in the global CLAUDE.md. Requires an Obsidian
        vault at ~/obsidian/nerdbrain (or NERDBRAIN_VAULT env override).
      '';
    };

    gitHostAliases = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = lib.literalExpression ''{ "my-gitlab.company.com" = "company"; }'';
      description = ''
        Map verbose git hostnames to short filesystem-safe slugs used by
        the nerdbrain SessionStart hook to resolve a project entity page.
      '';
    };

    extraPermissions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = lib.literalExpression ''[ "Bash(bun:*)" "WebFetch(domain:github.com)" ]'';
      description = ''
        Additional entries for settings.json permissions.allow. Merged with
        the baseline (puppeteer MCP tools).
      '';
    };

    enabledPlugins = lib.mkOption {
      type = lib.types.attrsOf lib.types.bool;
      default = defaultEnabledPlugins;
      description = ''
        Map of <plugin>@<marketplace> -> bool for settings.json enabledPlugins.
        Override entirely if you want a different plugin set.
      '';
    };

    extraMarketplaces = lib.mkOption {
      type = lib.types.attrs;
      default = defaultMarketplaces;
      description = ''
        extraKnownMarketplaces attribute set for settings.json. Each entry
        is `{ source = { source = "github"; repo = "owner/repo"; }; }`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.file.".claude/settings.json".text = builtins.toJSON settings;
    home.file.".claude/CLAUDE.md".text = claudeMdText;
    home.file.".claude/nerdbrain.aliases".text = aliasesText;
    home.file.".claude/agents".source = ../home/agents;
    home.file.".claude/hooks".source = ../home/hooks;
  };
}
