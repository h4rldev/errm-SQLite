{
  description = "Errm.. SQLite! - an erlang library exposing SQLite, and providing some helpers for working with it.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {inherit system;};
    beamPackages = pkgs.beamPackages;

    errm-prod = beamPackages.buildRebar3 {
      name = "errm-SQLite";
      version = "0.1.0-prod";

      src = ./.;

      nativeBuildInputs = with pkgs; [pkg-config];
      buildInputs = with pkgs; [sqlite just];

      preBuild = ''
        sed -i 's|#!/usr/bin/env bash|#!${pkgs.bash}/bin/bash|' justfile
      '';

      env = {
        REBAR_PROFILE = "prod";
        ERL_ROOT = "${beamPackages.erlang}/lib/erlang";
      };
    };

    errm-debug = beamPackages.buildRebar3 {
      name = "errm-SQLite";
      version = "0.1.0-debug";

      src = ./.;

      nativeBuildInputs = with pkgs; [pkg-config];
      buildInputs = with pkgs; [sqlite just];

      preBuild = ''
        sed -i 's|#!/usr/bin/env bash|#!${pkgs.bash}/bin/bash|' justfile
      '';

      env = {
        REBAR_PROFILE = "debug";
        ERL_ROOT = "${beamPackages.erlang}/lib/erlang";
      };
    };
  in {
    packages.${system} = {
      errm-sqlite-prod = errm-prod;
      default = errm-prod;
      errm-sqlite-debug = errm-debug;
    };

    devShells.${system}.default = pkgs.mkShell {
      name = "errm-SQLite";

      buildInputs = with pkgs; [
        beamPackages.erlang
        beamPackages.rebar3
        sqlite
      ];

      packages = with pkgs; [
        erlang-language-platform

        clang-tools
        bear

        just
      ];

      shellHook = ''
        export ERL_ROOT="${beamPackages.erlang}/lib/erlang"
      '';
    };
  };
}
