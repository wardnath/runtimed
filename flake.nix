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

        createKernel = pkgs: kernelName: language: 
          pkgs.writeTextFile {
            name = "${kernelName}-kernel.json";
            text = builtins.toJSON {
              argv = ["${pkgs.python3}/bin/python" "-m" "ipykernel_launcher" "-f" "{connection_file}"];
              display_name = kernelName;
              language = language;
            };
            destination = "/share/jupyter/kernels/${kernelName}/kernel.json";
          };

        kernelPackage = pkgs.symlinkJoin {
          name = "custom-jupyter-kernel";
          paths = [
            (createKernel pkgs "CustomPython" "python")
            pkgs.python3
            pkgs.python3Packages.ipykernel
          ];
        };

        buildRustPackage = { pname, cargoToml }: pkgs.rustPlatform.buildRustPackage {
          inherit pname;
          version = "0.1.0";

          src = ./.;
          cargoLock = {
            lockFile = ./Cargo.lock;
          };

          nativeBuildInputs = commonInputs;
          buildInputs = [ pkgs.openssl pkgs.jupyter kernelPackage ];

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
            mkdir -p $out/share
            cp -r ${kernelPackage}/share $out/
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
          buildInputs = [ pkgs.openssl pkgs.jupyter kernelPackage ];

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
