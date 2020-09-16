{ npmlock2nix, testLib, writeText }:
(testLib.runTests {
  testSplitsIntoBlocks = {
    expr = let blocks = npmlock2nix.internal.yarn.splitBlocks ''
      "@babel/code-frame@^7.8.3":
        version "7.8.3"
        resolved "https://registry.yarnpkg.com/@babel/code-frame/-/code-frame-7.8.3.tgz#33e25903d7481181534e12ec0a25f16b6fcf419e"
        integrity sha512-a9gxpmdXtZEInkCSHUJDLHZVBgb1QS0jhss4cPP93EW7s+uC5bikET2twEF3KV+7rDblJcmNvTR7VJejqd2C2g==
        dependencies:
          "@babel/highlight" "^7.8.3"

      "@babel/compat-data@^7.8.4":
        version "7.8.5"
        resolved "https://registry.yarnpkg.com/@babel/compat-data/-/compat-data-7.8.5.tgz#d28ce872778c23551cbb9432fc68d28495b613b9"
        integrity sha512-jWYUqQX/ObOhG1UiEkbH5SANsE/8oKXiQWjj7p7xgj9Zmnt//aUvyz4dBkK0HNsS8/cbyC5NmmH87VekW+mXFg==
        dependencies:
          browserslist "^4.8.5"
          invariant "^2.2.4"
          semver "^5.5.0"''; in
      {
        count = builtins.length blocks;
        inherit blocks;
      };
    expected = {
      count = 2;
      blocks = [
        ''"@babel/code-frame@^7.8.3":
  version "7.8.3"
  resolved "https://registry.yarnpkg.com/@babel/code-frame/-/code-frame-7.8.3.tgz#33e25903d7481181534e12ec0a25f16b6fcf419e"
  integrity sha512-a9gxpmdXtZEInkCSHUJDLHZVBgb1QS0jhss4cPP93EW7s+uC5bikET2twEF3KV+7rDblJcmNvTR7VJejqd2C2g==
  dependencies:
    "@babel/highlight" "^7.8.3"''

        ''"@babel/compat-data@^7.8.4":
  version "7.8.5"
  resolved "https://registry.yarnpkg.com/@babel/compat-data/-/compat-data-7.8.5.tgz#d28ce872778c23551cbb9432fc68d28495b613b9"
  integrity sha512-jWYUqQX/ObOhG1UiEkbH5SANsE/8oKXiQWjj7p7xgj9Zmnt//aUvyz4dBkK0HNsS8/cbyC5NmmH87VekW+mXFg==
  dependencies:
    browserslist "^4.8.5"
    invariant "^2.2.4"
    semver "^5.5.0"''
      ];
    };
  };

  testUnquote = {
    expr = map npmlock2nix.internal.yarn.unquote [ "" "\"" "\"\"" "\"foo\"" "\"foo\":" ];
    expected = [ "" "" "" "foo" "foo\":" ];
  };

  testParseBlock = {
    expr =
      let
        block = ''"@babel/code-frame@^7.8.3":
  version "7.8.3"
  resolved "https://somewhere"
  integrity sha512-bla==
  dependencies:
    "@babel/highlight" "^7.8.3"
  '';
      in
      npmlock2nix.internal.yarn.parseBlock block;

    expected = {
      name = "@babel/code-frame@^7.8.3";
      version = "7.8.3";
      resolved = "https://somewhere";
      integrity = "sha512-bla==";
      dependencies."@babel/highlight" = "^7.8.3";
    };
  };

  testParseFile = {
    expr =
      let
        res = (npmlock2nix.internal.yarn.parseFile ./examples-projects/simple-yarn-project/yarn.lock);
      in
      {
        type = builtins.typeOf res;
        len = builtins.length res;
        inherit res;
      };
    expected = {
      type = "list";
      len = 1;
      res = [
        {
          name = "lodash@^4.17.20";
          version = "4.17.20";
          resolved = "https://registry.yarnpkg.com/lodash/-/lodash-4.17.20.tgz#b44a9b6297bcb698f1c51a3545a2b3b368d59c52";
          integrity = "sha512-PlhdFcillOINfeV7Ni6oF1TAEayyZBoZ8bcshTHqOYJYlrqzRK5hagpagky5o4HfCzzd1TRkXPMFq6cKk9rGmA==";
        }
      ];
    };
  };

  testPatchDep = {
    expr =
      let
        dep = {
          name = "lodash@^4.17.20";
          version = "4.17.20";
          resolved = "https://registry.yarnpkg.com/lodash/-/lodash-4.17.20.tgz#b44a9b6297bcb698f1c51a3545a2b3b368d59c52";
          integrity = "sha512-PlhdFcillOINfeV7Ni6oF1TAEayyZBoZ8bcshTHqOYJYlrqzRK5hagpagky5o4HfCzzd1TRkXPMFq6cKk9rGmA==";
        };
      in
      npmlock2nix.internal.yarn.patchDep dep.name dep;
    expected = {
      name = "lodash@^4.17.20";
      version = "4.17.20";
      resolved = "file:/nix/store/4f7z79pjad43nq0h7xk62g436r0bjxbz-lodash__4.17.20";
      integrity = "sha512-PlhdFcillOINfeV7Ni6oF1TAEayyZBoZ8bcshTHqOYJYlrqzRK5hagpagky5o4HfCzzd1TRkXPMFq6cKk9rGmA==";
    };
  };

  testPatchFile = {
    expr =
      (npmlock2nix.internal.yarn.patchFile ./examples-projects/simple-yarn-project/yarn.lock);
    expected = ''
      # THIS IS AN AUTOGENERATED FILE. DO NOT EDIT THIS FILE DIRECTLY.
      # yarn lockfile v1


      lodash@^4.17.20:
        version "4.17.20"
        resolved "file:/nix/store/4f7z79pjad43nq0h7xk62g436r0bjxbz-lodash__4.17.20"
        integrity sha512-PlhdFcillOINfeV7Ni6oF1TAEayyZBoZ8bcshTHqOYJYlrqzRK5hagpagky5o4HfCzzd1TRkXPMFq6cKk9rGmA==
    '';
  };


})