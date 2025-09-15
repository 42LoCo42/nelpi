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

              (_: prev: {
                ${name} = prev.${name}.overrideAttrs {
                  preBuild = "python extract.py";
                };
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
