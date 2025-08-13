{
  outputs = { flake-utils, nixpkgs, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        inherit (pkgs.lib) getExe pipe readFile toLower trim;
        inherit (pkgs.lib.fileset) toSource unions;

        py = pkgs.python3.pkgs;
        proj = pipe ./pyproject.toml [ readFile fromTOML (x: x.project) ];
        repo = pipe ./repo [ readFile trim toLower ];
      in
      rec {
        packages = {
          default = py.buildPythonApplication rec {
            pname = proj.name;
            inherit (proj) version;

            src = toSource {
              root = ./.;
              fileset = unions [
                ./extract.py
                ./raw

                ./pyproject.toml
                ./src
              ];
            };

            preBuild = "python extract.py";

            pyproject = true;

            build-system = with py; [
              setuptools
            ];

            dependencies = with py; [

            ];

            meta.mainProgram = pname;
          };

          image = pkgs.dockerTools.buildImage {
            inherit (proj) name;
            config = {
              Cmd = [ (getExe packages.default) ];
              Labels = {
                "org.opencontainers.image.source" = "https://github.com/${repo}";
                "org.opencontainers.image.description" = "testing image";
                "org.opencontainers.image.licenses" = "GPL-3.0-or-later";
              };
            };
          };
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [ packages.default ];
          packages = with pkgs;  with py; [
            ipython
          ];
        };
      });
}
