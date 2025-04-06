{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    homeManager.url = "github:nix-community/home-manager";
    homeManager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, homeManager }: {

    modules.default = ./vscodes.nix;

  };
}
