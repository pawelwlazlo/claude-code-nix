{
  description = "Claude Code configuration as a portable Home Manager module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      mkHmConfig = system: extraModule:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs { inherit system; };
          modules = [
            self.homeManagerModules.default
            {
              home.username = "ci";
              home.homeDirectory = "/home/ci";
              home.stateVersion = "25.05";
            }
            extraModule
          ];
        };
    in
    {
      homeManagerModules.default = import ./modules;
      homeManagerModules.claudeCode = self.homeManagerModules.default;

      checks = forAllSystems (system: {
        module-minimal = (mkHmConfig system {
          programs.claudeCode.enable = true;
        }).activationPackage;

        module-with-nerdbrain = (mkHmConfig system {
          programs.claudeCode = {
            enable = true;
            enableNerdbrain = true;
          };
        }).activationPackage;

        module-with-overrides = (mkHmConfig system {
          programs.claudeCode = {
            enable = true;
            enableNerdbrain = true;
            gitHostAliases."example.com" = "example";
            extraPermissions = [ "Bash(bun:*)" ];
          };
        }).activationPackage;
      });
    };
}
