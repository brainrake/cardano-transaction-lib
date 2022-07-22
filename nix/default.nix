{ pkgs, system }:
{ src
  # The name of the project, used to generate derivation names
, projectName
  # The `package.json` for the project. It is *highly* recommended to pass this
  # in explicitly, even if it can be derived from the `src` argument. By doing
  # so, you will prevent frequent rebuilds of your generated `node_modules`
, packageJson ? "${src}/package.json"
  # The `package-lock.json` for the project. It is *highly* recommended to pass
  # this in explicitly, even if it can be derived from the `src` argument. By
  # doing so, you will prevent frequent rebuilds of your generated `node_modules`
, packageLock ? "${src}/package-lock.json"
  # If warnings generated from project source files will trigger a build error
, strictComp ? true
  # Warnings from `purs` to silence during compilation, independent of `strictComp`
, censorCodes ? [ "UserDefinedWarning" ]
  # The version of node to use across all project components
, nodejs ? pkgs.nodejs-14_x
  # Autogenerated Nix from `spago2nix generate`
, spagoPackages ? "${src}/spago-packages.nix"
  # Configuration that will be used to generate a `devShell` for the project
, shell ? { }
, ...
}:
let
  purs = pkgs.easy-ps.purs-0_14_5;

  spagoPkgs = import spagoPackages { inherit pkgs; };

  mkNodeEnv = { withDevDeps ? true }: import
    (pkgs.runCommand "node-packages-${projectName}"
      {
        buildInputs = [ pkgs.nodePackages.node2nix ];
      } ''
      mkdir $out
      cd $out
      cp ${packageLock} ./package-lock.json
      cp ${packageJson} ./package.json
      node2nix ${pkgs.lib.optionalString withDevDeps "--development" } \
        --lock ./package-lock.json -i ./package.json
    '')
    { inherit pkgs nodejs system; };

  mkNodeModules = { withDevDeps ? true }:
    let
      nodeEnv = mkNodeEnv { inherit withDevDeps; };
      modules = pkgs.callPackage
        (_:
          nodeEnv // {
            shell = nodeEnv.shell.override {
              # see https://github.com/svanderburg/node2nix/issues/198
              buildInputs = [ pkgs.nodePackages.node-gyp-build ];
            };
          });
    in
    (modules { }).shell.nodeDependencies;

  projectNodeModules = mkNodeModules { };

  shellFor =
    { packages ? [ ]
    , inputsFrom ? [ ]
    , shellHook ? ""
    , formatter ? "purs-tidy"
    , pursls ? true
    , nodeModules ? projectNodeModules
    , packageLockOnly ? false
    }:
      assert pkgs.lib.assertOneOf "formatter" formatter [ "purs-tidy" "purty" ];
      pkgs.mkShell {
        buildInputs = [
          nodeModules
          purs
          nodejs
          pkgs.easy-ps.spago
          pkgs.easy-ps."${formatter}"
          pkgs.easy-ps.pscid
          pkgs.easy-ps.psa
          pkgs.easy-ps.spago2nix
          pkgs.nodePackages.node2nix
        ] ++ pkgs.lib.lists.optional
          pursls
          pkgs.easy-ps.purescript-language-server;
        inherit packages inputsFrom;
        shellHook = ''
          export NODE_PATH="${nodeModules}/lib/node_modules"
          export PATH="${nodeModules}/bin:$PATH"
          ${pkgs.lib.optionalString packageLockOnly "export NPM_CONFIG_PACKAGE_LOCK_ONLY=true"}
        ''
        + shellHook;
      };

  buildPursProject =
    { name ? projectName
    , nodeModules ? projectNodeModules
    , ...
    }:
    let
      # This is what spago2nix does
      spagoGlob = pkg:
        ''".spago/${pkg.name}/${pkg.version}/src/**/*.purs"'';
      spagoGlobs = builtins.toString (
        builtins.map spagoGlob (builtins.attrValues spagoPkgs.inputs)
      );
    in
    pkgs.stdenv.mkDerivation {
      inherit name src;
      buildInputs = [
        nodeModules
        spagoPkgs.installSpagoStyle
        pkgs.easy-ps.psa
      ];
      nativeBuildInputs = [
        purs
        pkgs.easy-ps.spago
      ];
      unpackPhase = ''
        export HOME="$TMP"
        export NODE_PATH="${nodeModules}/lib/node_modules"
        export PATH="${nodeModules}/bin:$PATH"
        cp -r $src .
        install-spago-style
      '';
      buildPhase = ''
        psa ${pkgs.lib.optionalString strictComp "--strict" } \
          --censor-lib --is-lib=.spago ${spagoGlobs} \
          --censor-codes=${builtins.concatStringsSep "," censorCodes} "./**/*.purs"
      '';
      installPhase = ''
        mkdir $out
        mv output $out/
      '';
    };

  project = buildPursProject { };

  runPursTest =
    { testMain ? "Test.Main"
    , name ? "${projectName}-check"
    , nodeModules ? projectNodeModules
    , env ? { }
    , buildInputs ? [ ]
    , ...
    }: pkgs.runCommand "${name}"
      (
        {
          buildInputs = [ project nodeModules ] ++ buildInputs;
          NODE_PATH = "${nodeModules}/lib/node_modules";
        } // env
      )
      # spago will attempt to download things, which will fail in the
      # sandbox, so we can just use node instead
      # (idea taken from `plutus-playground-client`)
      ''
        cd ${src}
        ${nodejs}/bin/node -e 'require("${project}/output/${testMain}").main()'
        touch $out
      '';

  runPlutipTest = args: runPursTest (
    {
      buildInputs = with pkgs; [
        postgresql
        ogmios
        ogmios-datum-cache
        plutip-server
        ctl-server
      ];
    } // args
  );

  bundlePursProject =
    { name ? "${projectName}-bundle-" +
        (if browserRuntime then "web" else "nodejs")
    , entrypoint ? "index.js"
    , htmlTemplate ? "index.html"
    , main ? "Main"
    , browserRuntime ? true
    , webpackConfig ? "webpack.config.js"
    , bundledModuleName ? "output.js"
    , nodeModules ? projectNodeModules
    , ...
    }: pkgs.stdenv.mkDerivation {
      inherit name src;
      buildInputs = [
        nodejs
        nodeModules
        project
      ];
      nativeBuildInputs = [
        purs
        pkgs.easy-ps.spago
      ];
      buildPhase = ''
        export HOME="$TMP"
        export NODE_PATH="${nodeModules}/lib/node_modules"
        export PATH="${nodeModules}/bin:$PATH"
        ${pkgs.lib.optionalString browserRuntime "export BROWSER_RUNTIME=1"}
        cp -r ${project}/output .
        chmod -R +rwx .
        spago bundle-module --no-install --no-build -m "${main}" \
          --to ${bundledModuleName}
        cp $src/${entrypoint} .
        cp $src/${htmlTemplate} .
        cp $src/${webpackConfig} .
        mkdir ./dist
        webpack --mode=production -c ${webpackConfig} -o ./dist \
          --entry ./${entrypoint}
      '';
      installPhase = ''
        mkdir $out
        mv dist $out
      '';
    };

  pursDocsSearchNpm =
    let
      fakePackage = builtins.toJSON {
        name = "pursDocsSearch";
        version = "0.0.0";
        dependencies = { "purescript-docs-search" = "0.0.11"; };
      };
      fakePackageLock = builtins.toJSON {
        requires = true;
        lockfileVersion = 1;
        dependencies = {
          purescript-docs-search = {
            version = "0.0.11";
            resolved = "https://registry.npmjs.org/purescript-docs-search/-/purescript-docs-search-0.0.11.tgz";
            integrity = "sha512-eFcxaXv2mgI8XFBSMMuuI0S6Ti0+Ol4jxZSC5rUzeDuNQNKVhKotRWxBqoirIzFmSGXbEqYOo9oZVuDJAFLNIg==";
          };
        };
      };
    in
    import
      (pkgs.runCommand "purescript-docs-search-npm"
        {
          buildInputs = [ pkgs.nodePackages.node2nix ];
        }
        ''
          mkdir $out
          cd $out
          cat > package.json <<EOF
            ${fakePackage}
          EOF
          cat > package-lock.json <<EOF
            ${fakePackageLock}
          EOF
          node2nix --lock ./package-lock.json -i ./package.json
        '')
      { inherit pkgs nodejs system; };

  buildPursDocs =
    { name ? "${projectName}-docs"
    , format ? "html"
    , ...
    }@args:
    (buildPursProject args).overrideAttrs
      (oas: {
        inherit name;
        buildPhase = ''
          purs docs --format ${format} "./**/*.purs" ".spago/*/*/src/**/*.purs"
        '';
        installPhase = ''
          mkdir $out
          cp -r generated-docs $out
          cp -r output $out
        '';
      });

  buildSearchablePursDocs = { packageName, ... }:
    pkgs.stdenv.mkDerivation {
      name = "${projectName}-searchable-docs";
      dontUnpack = true;
      buildInputs = [ spagoPkgs.installSpagoStyle ];
      buildPhase = ''
        export NODE_PATH="${pursDocsSearchNpm.nodeDependencies}/lib/node_modules"
        export PATH="${pursDocsSearchNpm.nodeDependencies}/bin:$PATH"
        cp -r ${buildPursDocs { }}/{generated-docs,output} .
        install-spago-style
        chmod -R +rwx .
        purescript-docs-search build-index --package-name ${packageName}
      '';
      installPhase = ''
        mkdir $out
        cp -r generated-docs $out
      '';
    };

in
{
  inherit buildPursProject runPursTest runPlutipTest bundlePursProject
    buildPursDocs buildSearchablePursDocs purs nodejs mkNodeModules;
  devShell = shellFor shell;
}
