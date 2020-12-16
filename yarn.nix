# Helper library to parse yarn.lock files that are some custom format and not just JSON :(
{ lib, internal, stdenv, nodejs, yarn, writeText, writeScriptBin, writeShellScriptBin }:
let
  default_nodejs = nodejs;

  # Description: Split a file into logicla blocks of "dependencies", on dependency per block.
  # Type: String -> [ String ]
  splitBlocks = text:
    assert builtins.typeOf text != "string" -> throw "Expected the argument text to be of type string.";
    let blocks = builtins.split "\n\n" text;
    in builtins.filter (x: builtins.typeOf x == "string") blocks;


  # Description: Unquote a given string, e.g remove the quotes around a value
  # Type: String -> String
  # Note: It does not check if the quotes are well-formed (aka. that there is one at the start and one at the beginning).
  unquote = text:
    assert builtins.typeOf text != "string" -> throw "Expected the argument text to be of type string.";
    let
      s = if lib.hasPrefix "\"" text then builtins.substring 1 (builtins.stringLength text) text else text;
    in
    if s != "" then
      if lib.hasSuffix "\"" s then builtins.substring 0 ((builtins.stringLength s) - 1) s else s else s;


  # Description: Parse a single "block" from the lock file into an attrset
  # Type: String -> Attrset
  parseBlock = block:
    let
      getField = fieldName: prefix: body:
        let
          ls = builtins.filter (lib.hasPrefix prefix) body;
          line = assert builtins.length ls == 0 -> throw "no ${fieldName} line found in block for package ${name}"; let x = builtins.head ls; in builtins.substring (builtins.stringLength prefix) (builtins.stringLength x) x;
        in
        line;

      lines =
        let
          ls = builtins.filter (x: builtins.typeOf x != "list") (builtins.split "\n" block);
        in
        ls;
      name = let x = builtins.head lines; in
        assert !(lib.hasSuffix ":" x) -> throw "`name` line is malformed, must end with a colon. Got: \"${x}\"";
        unquote (lib.substring 0 ((builtins.stringLength x) - 1) x);

      body =
        let
          ls = builtins.tail lines;
          strippedLines = map (line: assert line != "" && !lib.hasPrefix "  " line -> throw "invalid line (`${line}`) in block for ${name}"; builtins.substring 2 (builtins.stringLength line) line) ls;
        in
        strippedLines;

      version = unquote (getField "version" "version " body);
      resolved = unquote (getField "resolved" "resolved " body);
      integrity = getField "integrity" "integrity " body;

      dependencies = parseDependencies body;
    in
    ({
      inherit name version resolved;
    }) // (
      let res = builtins.tryEval integrity; in if res.success then { integrity = res.value; } else { }
    )

    // (if dependencies != null then { inherit dependencies; } else { });

  parseDependencies = lines:
    let
      parseDepLine = acc: cur:
        let
          a = if acc != null then acc else { deps = { }; };
        in
        if lib.hasPrefix "  " cur then
          let
            stripped = builtins.substring 2 (builtins.stringLength cur) cur;
            parts = builtins.filter (x: x != [ ]) (builtins.split " " stripped);
            name = unquote (lib.head parts);
            version = unquote (lib.head (lib.tail parts));
          in
          { deps = a.deps // { ${name} = version; }; }
        else { inherit (a) deps; done = true; };
      innerFn = acc: cur: if acc != null || cur == "dependencies:" then parseDepLine acc cur else acc;
      res = builtins.foldl' innerFn null lines;
    in
    if res == null then null else res.deps;

  stripLeadingEmptyLines = lines:
    let
      head = builtins.head lines;
      tail = builtins.tail lines;
    in
    if head == "" then stripLeadingEmptyLines tail else lines;

  removePreamble = text:
    let
      lines = builtins.filter (x: x != [ ]) (builtins.split "\n" text);
      nonCommentLines = builtins.filter (line: !lib.hasPrefix "#" line) lines;
      nonEmptyLeadingLines = stripLeadingEmptyLines nonCommentLines;
    in
    lib.concatStringsSep "\n" nonEmptyLeadingLines;

  parseFile = filePath:
    let
      content = removePreamble (builtins.readFile filePath);
    in
    map parseBlock (builtins.filter (block: block != "") (splitBlocks content));

  # Description: Takes a string of the format package@org/repo#rev and returns
  # an attrset with those components extracted. If no match is found null is returned.
  # Type: String -> Set
  parseGitHubSource = name:
    let
      m = builtins.match "([^@]+)@([^/]+)/([^#]+)#(.+)" name;
    in
    if m != null then {
      package = builtins.elemAt m 0;
      org = builtins.elemAt m 1;
      repo = builtins.elemAt m 2;
      rev = builtins.elemAt m 3;
    } else null;

  patchDep = name: dep:
    let
      # yarn points github rev source to the github tarball e.g.:
      # {
      #  "dependencies": …,
      #  "name":"tsec@googleinterns/tsec#7bf4ab23686500522341b977b3e2cc04b1f720b1",
      #  "resolved":"https://codeload.github.com/googleinterns/tsec/tar.gz/7bf4ab23686500522341b977b3e2cc04b1f720b1",
      #  "version":"0.0.1"
      # }
      # we must take care of these here and can pass all the other cased to the
      # standard makeSource function. Instead of using the given URL we will
      # use a git fetcher.
      parsedGitHubSource = parseGitHubSource dep.name;
    in
    if parsedGitHubSource == null then dep // { inherit (internal.makeSource name dep) resolved; }
    else
      dep // {
        resolved = "file:/" + (internal.buildTgzFromGitHub {
          inherit name;
          inherit (parsedGitHubSource) org repo rev;
          ref = parsedGitHubSource.rev;
        });
      };

  patchFile = filePath:
    let
      parsedFile = parseFile filePath;
      patchedDeps = builtins.listToAttrs (map (x: lib.nameValuePair x.name (patchDep x.name x)) parsedFile);

      searchStrings = map (x: x.resolved) parsedFile;
      replaceStrings = map (x: patchedDeps.${x.name}.resolved) parsedFile;

      contents = builtins.readFile filePath;
    in
    builtins.replaceStrings searchStrings replaceStrings contents;

  patchShebangs = preInstallLinks:
    let
      preInstallLinkCommands = lib.concatStringsSep "\n"
        (
          lib.mapAttrsToList
            (name: mappings: ''
              if test -d "$1/${name}"; then
              ls -la
              ${lib.concatStringsSep "\n"
                (lib.mapAttrsToList
                    (to: from: ''
                        dirname=$(dirname ${to})
                        mkdir -p $1/${name}/$dirname
                        ln -sf ${from} $1/${name}/${to}
                      '')
                    mappings
                )}
              fi
            '')
            preInstallLinks
        );
    in
    writeShellScriptBin "patchShebangs.sh" ''
      set -ex
      ${preInstallLinkCommands}

      if grep -I -q -r '/bin/' "$1"; then
      cat $TMP/preinstall-env
        source $TMP/preinstall-env
        patchShebangs "$1"
      fi
    '';

  yarnWrapper = { nodejs, yarn, patchShebangs }: writeScriptBin "yarn" ''
    #!${nodejs}/bin/node
    const { promisify } = require('util')
    const child_process = require('child_process');
    const exec = promisify(child_process.exec)
    const { existsSync } = require('fs')
    async function getYarn() {
        const yarn = "${yarn}/bin/yarn"
        if (existsSync(`''${yarn}.js`)) return `''${yarn}.js`
        return yarn
    }
    global.experimentalYarnHooks = {
        async linkStep(cb) {
            const res = await cb()
            console.log("patching shebangs")
            await exec("${patchShebangs}/bin/patchShebangs.sh node_modules")
            return res
        }
    }
    getYarn().then(require)
  '';

  # FIXME: deduplicate the code with the npmlock node_modules function
  node_modules =
    args@{ src
    , filterSource ? true
    , sourceFilter ? internal.onlyPackageJsonFilter
    , yarnLockFile ? src + "/yarn.lock"
    , packageJsonFile ? src + "/package.json"
    , buildInputs ? [ ]
    , nodejs ? default_nodejs
    , preInstallLinks ? { }
    , yarnArgs ? ""
    , ...
    }:
    let
      packageJson = builtins.fromJSON (builtins.readFile packageJsonFile);
      patchedLockfile = writeText "yarn.lock" (patchFile yarnLockFile);

      yWrapper = yarnWrapper { inherit nodejs yarn; patchShebangs = patchShebangs preInstallLinks; };
      extraArgs = builtins.removeAttrs args [ "preInstallLinks" "yarnArgs" ];

    in
    stdenv.mkDerivation (extraArgs // {
      pname = packageJson.name;
      version = packageJson.version;
      inherit src;

      buildInputs = [ yWrapper nodejs ] ++ buildInputs;

      propagatedBuildInputs = [ nodejs yWrapper ];

      setupHooks = [ ./set-paths.sh ];

      outputs = [ "out" "yarn_cache" ];

      configurePhase = ''
        runHook preConfigure

        export HOME=$(mktemp -d)

        runHook postConfigure
      '';

      postPatch = ''
        ln -sf ${patchedLockfile} yarn.lock
      '';

      buildPhase = ''
        runHook preBuild
        declare -pf > $TMP/preinstall-env
        export PATH="$(pwd)/node_modules/.bin:$PATH"
        yarn config set nodedir ${internal.nodeSource nodejs}
        set -x
        yarn install --verbose --offline ${yarnArgs}
        test -d node_modules/.bin && patchShebangs node_modules/.bin

        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        mkdir $out

        if test -d node_modules; then
          if [ $(ls -1 node_modules | wc -l) -gt 0 ] || [ -e node_modules/.bin ]; then
            mv node_modules $out/
            if test -d $out/node_modules/.bin; then
              ln -s $out/node_modules/.bin $out/bin
            fi
          fi
        fi

        mkdir -p $yarn_cache
        test -d $HOME/.cache/yarn && cp -rv $HOME/.cache/yarn $yarn_cache


        runHook postInstall
      '';

      passthru.nodejs = nodejs;
    });
in
{
  inherit splitBlocks parseBlock unquote parseFile patchFile patchDep node_modules;
}
