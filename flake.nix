{
  description = "Fork, the git client, on Linux: its Windows build on Wine with the fixes it needs";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Wine's development branch: it already resolves WinRT metadata (RoResolveNamespace, 11.17),
      # which a Wine 11.0 base such as Proton's does not. patches/wine/ adds what Fork still needs.
      wine = pkgs.wineWow64Packages.unstable.overrideAttrs (prev: {
        patches = (prev.patches or [ ]) ++ [
          ./patches/wine/0001-combase-tests-Add-tests-for-RoGetParameterizedTypeIn.patch
          ./patches/wine/0002-combase-Implement-RoGetParameterizedTypeInstanceIID.patch
        ];
      });

      dotnet = pkgs.callPackage ./dotnet.nix { };
      winrt = pkgs.callPackage ./winrt.nix { inherit dotnet; };
      fork = pkgs.callPackage ./fork.nix { inherit wine dotnet winrt; };
    in
    {
      packages.${system} = {
        inherit wine fork;
        default = fork;
      };

      apps.${system}.default = {
        type = "app";
        program = pkgs.lib.getExe fork;
      };
    };
}
