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

        pythonEnv = pkgs.python3.withPackages (ps: with ps; [
          ipykernel
          numpy
          pandas
          matplotlib
          scipy
        ]);

        kernelspec = pkgs.runCommand "jupyter-kernel" {} ''
          export HOME=$out
          mkdir -p $out/share/jupyter/kernels/my-data-science-kernel
          ${pythonEnv}/bin/python -m ipykernel install --prefix=$out --name="my-data-science-kernel"
          sed -i 's|"python3"|"${pythonEnv}/bin/python"|' $out/share/jupyter/kernels/my-data-science-kernel/kernel.json
          cp $out/share/jupyter/kernels/my-data-science-kernel/kernel.json $out/kernelspec.json
        '';

        buildRustPackage = { pname, cargoToml }: pkgs.rustPlatform.buildRustPackage {
          inherit pname;
          version = "0.1.0";

          src = ./.;
          cargoLock = {
            lockFile = ./Cargo.lock;
          };

          nativeBuildInputs = commonInputs;
          buildInputs = [ pkgs.openssl pkgs.jupyter kernelspec ];

          buildPhase = ''
            export KERNELSPEC_PATH=$out/kernelspec.json
            export OPENSSL_DIR=${pkgs.openssl.dev}
            export OPENSSL_INCLUDE_DIR=${pkgs.openssl.dev}/include
            export OPENSSL_LIB_DIR=${pkgs.openssl.out}/lib
            export RUSTFLAGS="-L ${pkgs.openssl.out}/lib -L ${pkgs.openssl.dev}/lib --cfg openssl"
            cargo build --release --manifest-path ${cargoToml}
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp target/release/${pname} $out/bin/
            mkdir -p $out/share/jupyter
            cp -r ${kernelspec}/share/jupyter/kernels $out/share/jupyter/
            cp ${kernelspec}/kernelspec.json $out/
          '';

          doCheck = false;  # Temporarily disable tests
        };

      in {
        packages = {
          kernelspec = kernelspec;

          install-kernel = pkgs.writeShellScriptBin "install-kernel" ''
            ${pkgs.jupyter}/bin/jupyter kernelspec install ${kernelspec}/share/jupyter/kernels/my-data-science-kernel --user
          '';

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
          buildInputs = [ pkgs.openssl pkgs.jupyter pythonEnv ];

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

          install-kernel = flake-utils.lib.mkApp {
            drv = self.packages.${system}.install-kernel;
          };

          run-kernel = flake-utils.lib.mkApp {
            drv = pkgs.writeShellScriptBin "run-kernel" ''
              if ! ${pkgs.jupyter}/bin/jupyter kernelspec list | grep -q "my-data-science-kernel"; then
                echo "Installing kernel..."
                ${self.packages.${system}.install-kernel}/bin/install-kernel
              fi
              
              echo "Starting Jupyter console with my-data-science-kernel..."
              ${pkgs.jupyter}/bin/jupyter console --kernel=my-data-science-kernel
            '';
          };
        };
      }
    );
}
