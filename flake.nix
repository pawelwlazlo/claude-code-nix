{
  description = "Claude Code configuration as a portable Home Manager module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }: {
    homeManagerModules.default = import ./modules;
    homeManagerModules.claudeCode = self.homeManagerModules.default;
  };
}
