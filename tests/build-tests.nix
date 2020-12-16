{ lib, callPackage, symlinkJoin, npmlock2nix, runCommand, libwebp, pkgs }:
let
  symlinkAttrs = attrs: runCommand "symlink-attrs"
    { passthru.tests = attrs; }
    (
      let
        drvs = lib.attrValues (lib.mapAttrs (name: drv: { inherit name drv; }) attrs);
      in
      ''
          mkdir $out
        ${lib.concatMapStringsSep "\n" (o: "ln -s ${o.drv} $out/${o.name}") drvs}
      ''
    );
in
symlinkAttrs {
  webpack-cli-project-default-build-command = npmlock2nix.build {
    src = ./examples-projects/webpack-cli-project;
    installPhase = ''
      cp -r dist $out
    '';
  };

  webpack-cli-project-custom-build-command = npmlock2nix.build {
    src = ./examples-projects/webpack-cli-project;
    buildCommands = [ "webpack --mode=production" ];
    installPhase = ''
      cp -r dist $out
    '';
  };

  node-modules-attributes-are-passed-through = npmlock2nix.build {
    src = ./examples-projects/bin-wrapped-dep;
    buildCommands = [
      ''
        readlink -f $(node -e "console.log(require('cwebp-bin'))") > actual
        echo ${libwebp}/bin/cwebp > expected
      ''
    ];
    installPhase = ''
      cp actual $out
    '';

    doCheck = true;
    checkPhase = ''
      cmp actual expected || exit 1
    '';

    node_modules_attrs = {
      preInstallLinks = {
        "cwebp-bin"."vendor/cwebp" = "${libwebp}/bin/cwebp";
      };
    };
  };

  build-yarn-node-modules = npmlock2nix.internal.yarn.node_modules {
    src = ./examples-projects/simple-yarn-project;
  };

  build-yarn-webpack-cli =
    let
      nm = npmlock2nix.internal.yarn.node_modules {
        src = ./examples-projects/webpack-cli-project;
      };
    in
    npmlock2nix.build {
      src = ./examples-projects/webpack-cli-project;
      node_modules = nm;
      installPhase = ''
        cp -r dist $out
      '';
    };

  build-yarn-vscode =
    let
      src = callPackage ./examples-projects/vscode-yarn-project/src.nix { };
      commonOpts = {
        inherit src;
        yarnLockFile = ./examples-projects/vscode-yarn-project/yarn.lock;
        packageJsonFile = ./examples-projects/vscode-yarn-project/package.json;
      };
      nm = npmlock2nix.internal.yarn.node_modules (commonOpts // {
        npm_execpath = "yarnpkg";
        ELECTRON_SKIP_BINARY_DOWNLOAD = 1;
        buildInputs = with pkgs; [
          python3
          git
          pkgconfig
          xlibs.libxkbfile
          xlibs.libX11
          libsecret
          electron
        ];
        postConfigure = ''
          git init . # pretend this is a git repo so husky? is happy

          echo "// nop" > build/npm/postinstall.js
        '';

        preInstallLinks = {
          playwright."browsers.json" = pkgs.writeText "browsers.json" (builtins.toJSON { browsers = [ ]; });
          vscode-ripgrep = {
            "bin" = "${pkgs.ripgrep}/bin";
          };
        };
      });

      nm_extensions = npmlock2nix.internal.yarn.node_modules {
        inherit src;
        yarnLockFile = src + "/extensions/yarn.lock";
        packageJsonFile = src + "/extensions/package.json";
        prePatch = "cd extensions";
        postBuild = ''
          for dir in $(find . -type d -depth 1); do
            cd $dir
            yarn --frozen-lockfile --ignore-optional --offline --verbose install
          done
        '';
      };

      nm_build = npmlock2nix.internal.yarn.node_modules {
        inherit src;
        yarnLockFile = src + "/build/yarn.lock";
        packageJsonFile = src + "/build/package.json";
        prePatch = "cd build";
        preInstallLinks = {
          playwright."browsers.json" = pkgs.writeText "browsers.json" (builtins.toJSON { browsers = [ ]; });
          vscode-ripgrep = {
            "bin" = "${pkgs.ripgrep}/bin";
          };
        };
      };

      nm_test_automation = npmlock2nix.internal.yarn.node_modules {
        inherit src;
        yarnLockFile = src + "/test/automation/yarn.lock";
        packageJsonFile = src + "/test/automation/package.json";
        prePatch = "cd test/automation";
        buildInputs = [
          nm
        ];
      };

      nm_test_smoke = npmlock2nix.internal.yarn.node_modules {
        inherit src;
        yarnLockFile = src + "/test/smoke/yarn.lock";
        packageJsonFile = src + "/test/smoke/package.json";
        prePatch = "cd test/smoke";
        buildInputs = [
          nm
        ];
      };

      nm_test_integration_browser = npmlock2nix.internal.yarn.node_modules {
        inherit src;
        yarnLockFile = src + "/test/integration/browser/yarn.lock";
        packageJsonFile = src + "/test/integration/browser/package.json";
        prePatch = "cd test/integration/browser";
        preBuild = "cd ../../..";
        yarnArgs = "test/integration/browser";
        buildInputs = [
          nm
        ];
      };
    in
    npmlock2nix.build (commonOpts // {
      node_modules = nm;
      extra_node_modules = [ nm_build nm_test_automation nm_test_smoke nm_test_integration_browser ];
      preConfigure = ''
        set -x
      '';
      buildCommands = [ "ls -la" "npm run compile" ];
      installPhase = ''
        cp -r dist $out
      '';
    });

  # build-yarn-node-modules-concourse = npmlock2nix.internal.yarn.node_modules {
  #   src = ./examples-projects/simple-yarn-project;
  #   yarnLockFile = ./concourse-yarn.lock;
  # };

}
