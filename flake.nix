{
  inputs = {
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { flake-utils, nixpkgs, pyproject-build-systems, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        inherit (pkgs.lib) composeManyExtensions getExe pipe readFile toLower trim;
        inherit (pkgs.lib.fileset) toSource unions;
        inherit (pyproject-build-systems.inputs) pyproject-nix uv2nix;
        inherit (pkgs.callPackages pyproject-nix.build.util { }) mkApplication;

        name = "nelpi";
        repo = pipe ./repo [ readFile trim toLower ];

        python = pkgs.python311;

        workspace = uv2nix.lib.workspace.loadWorkspace {
          workspaceRoot = /. + (toString (builtins.unsafeDiscardStringContext (toSource {
            root = ./.;
            fileset = unions [
              ./extract.py
              ./pyproject.toml
              ./raw
              ./src
              ./uv.lock
            ];
          })));
        };

        pythonSet =
          (pkgs.callPackage pyproject-nix.build.packages {
            inherit python;
          }).overrideScope (
            composeManyExtensions [
              pyproject-build-systems.overlays.default

              (workspace.mkPyprojectOverlay {
                sourcePreference = "wheel";
              })

              (final: prev: {
                ${name} = prev.${name}.overrideAttrs {
                  preBuild = "python extract.py";
                };

                # https://github.com/TyberiusPrime/uv2nix_hammer_overrides/blob/68d84fd911afa2383a1c1cb28712ca1d090a8c32/flake.nix#L87
                cython_0 = prev.cython.overrideAttrs (old: rec {
                  version = "0.29.36";

                  src = pkgs.fetchPypi {
                    pname = "Cython";
                    inherit version;
                    hash = "sha256-QcDP0tdU44PJ7rle/8mqSrhH0Ml0cHfd18Dctow7wB8=";
                  };
                });

                # thinc must be built from source on aarch64, which is broken by default:
                # various cython files are missing and cython itself must be a 0.*, not 3.*
                thinc =
                  if !pkgs.hostPlatform.isAarch64 then prev.thinc else
                  (prev.thinc.override {
                    sourcePreference = "sdist";
                  }).overrideAttrs (old: {
                    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
                      (final.resolveBuildSystem {
                        blis = [ ];
                        cymem = [ ];
                        cython_0 = [ ];
                        murmurhash = [ ];
                        numpy = [ ];
                        preshed = [ ];
                        setuptools = [ ];
                      })
                    ];
                  });
              })
            ]);
      in
      rec {
        packages = {
          inherit workspace pythonSet;

          default = mkApplication {
            package = pythonSet.${name};
            venv = pythonSet.mkVirtualEnv "${name}-env" workspace.deps.default;
          };

          image = pkgs.dockerTools.buildImage {
            inherit name;
            config = {
              Cmd = [ (getExe packages.default) ];
              Labels = {
                "org.opencontainers.image.source" = "https://github.com/${repo}";
                "org.opencontainers.image.licenses" = "GPL-3.0-or-later";
              };
            };
          };
        };

        devShells.default =
          let
            editableOverlay = workspace.mkEditablePyprojectOverlay {
              root = "$REPO_ROOT";
            };

            editablePythonSet = pythonSet.overrideScope (
              composeManyExtensions [
                editableOverlay
              ]);

            venv = editablePythonSet.mkVirtualEnv "${name}-dev-env" workspace.deps.all;
          in
          pkgs.mkShell {
            packages = with pkgs; [
              dive
              uv
              venv
            ];

            env = {
              UV_NO_SYNC = "1";
              UV_PYTHON = python.interpreter;
              UV_PYTHON_DOWNLOADS = "never";

              LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath (with pkgs; [
                stdenv.cc.cc
                zlib
              ]);
            };

            shellHook = ''
              export REPO_ROOT="$(git rev-parse --show-toplevel)"
            '';
          };
      });
}
