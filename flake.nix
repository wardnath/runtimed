{
  description = "RuntimeD - A daemon for REPLs built on top of Jupyter kernels";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs { inherit system overlays; };
        
        commonInputs = with pkgs; [
          openssl
          pkg-config
          cacert
          rust-bin.stable.latest.default
          perl
          gcc
          binutils
          jupyter
        ];

        buildRustPackage = { pname, cargoToml }: pkgs.rustPlatform.buildRustPackage {
          inherit pname;
          version = "0.1.0";

          src = ./.;
          cargoLock = {
            lockFile = ./Cargo.lock;
          };

          nativeBuildInputs = commonInputs;
          buildInputs = [ pkgs.openssl pkgs.jupyter ];

          buildPhase = ''
            export OPENSSL_DIR=${pkgs.openssl.dev}
            export OPENSSL_INCLUDE_DIR=${pkgs.openssl.dev}/include
            export OPENSSL_LIB_DIR=${pkgs.openssl.out}/lib
            export RUSTFLAGS="-L ${pkgs.openssl.out}/lib -L ${pkgs.openssl.dev}/lib --cfg openssl"
            cargo build --release --manifest-path ${cargoToml}
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp target/release/${pname} $out/bin/
          '';

          doCheck = false;  # Temporarily disable tests
        };

      in {
        packages = {
          runtimed = buildRustPackage {
            pname = "runtimed";
            cargoToml = "./runtimed/Cargo.toml";
          };

          runt = buildRustPackage {
            pname = "runt";
            cargoToml = "./runt/Cargo.toml";
          };
        };

        defaultPackage = self.packages.${system}.runtimed;

        devShell = pkgs.mkShell {
          nativeBuildInputs = commonInputs;
          buildInputs = [ pkgs.openssl pkgs.jupyter ];

          shellHook = ''
            export OPENSSL_DIR=${pkgs.openssl.dev}
            export OPENSSL_INCLUDE_DIR=${pkgs.openssl.dev}/include
            export OPENSSL_LIB_DIR=${pkgs.openssl.out}/lib
            export RUSTFLAGS="-L ${pkgs.openssl.out}/lib -L ${pkgs.openssl.dev}/lib --cfg openssl"
          '';
        };

        apps = {
          runtimed = flake-utils.lib.mkApp {
            drv = self.packages.${system}.runtimed;
          };

          runt = flake-utils.lib.mkApp {
            drv = self.packages.${system}.runt;
          };
        };
      }
    );
}
