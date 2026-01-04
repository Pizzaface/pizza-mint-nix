{
  description = "Jordan's Mint 22.2 Home Manager setup";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      homeConfigurations."jordan@mint" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ ./home/jordan.nix ];
      };
    };
}
