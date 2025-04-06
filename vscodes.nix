{ config, lib, pkgs, ... }:
let
  inherit (lib)
    flatten literalExpression mapAttrsToList mkOption mkIf optionalString types;

  inherit (pkgs.stdenv) mkDerivation;
  inherit (pkgs) makeDesktopItem;

  conf = config.programs.vscodes;

  jsonFormat = pkgs.formats.json { };

  userDir = cfg:
    let
      configDir = cfg.name;
    in
    if pkgs.stdenv.hostPlatform.isDarwin then
      "${config.home.homeDirectory}/Library/Application Support/${configDir}/User"
    else
      "${config.xdg.configHome}/${configDir}/User";

  configFilePath = cfg: name:
    "${userDir cfg}/${
      optionalString (name != "default") "profiles/${name}/"
    }settings.json";
  tasksFilePath = cfg: name:
    "${userDir cfg}/${
      optionalString (name != "default") "profiles/${name}/"
    }tasks.json";
  keybindingsFilePath = cfg: name:
    "${userDir cfg}/${
      optionalString (name != "default") "profiles/${name}/"
    }keybindings.json";

  snippetDir = cfg: name:
    "${userDir cfg}/${
      optionalString (name != "default") "profiles/${name}/"
    }snippets";

  extensionPath = cfg: "${config.home.homeDirectory}/.local/share/vscodes/${cfg.name}/extensions";

  extensionJson = ext: pkgs.vscode-utils.toExtensionJson ext;
  extensionJsonFile = name: text:
    pkgs.writeTextFile {
      inherit text;
      name = "extensions-json-${name}";
      destination = "/share/vscode/extensions/extensions.json";
    };

  mergedUserSettings =
    userSettings: enableUpdateCheck: enableExtensionUpdateCheck:
    userSettings // lib.optionalAttrs (enableUpdateCheck == false) {
      "update.mode" = "none";
    } // lib.optionalAttrs (enableExtensionUpdateCheck == false) {
      "extensions.autoCheckUpdates" = false;
    };

  profileOptions = {
    userSettings = mkOption {
      type = jsonFormat.type;
      default = { };
      example = literalExpression ''
        {
          "files.autoSave" = "off";
          "[nix]"."editor.tabSize" = 2;
        }
      '';
      description = ''
        Configuration written to Visual Studio Code's
        {file}`settings.json`.
      '';
    };

    userTasks = mkOption {
      type = jsonFormat.type;
      default = { };
      example = literalExpression ''
        {
          version = "2.0.0";
          tasks = [
            {
              type = "shell";
              label = "Hello task";
              command = "hello";
            }
          ];
        }
      '';
      description = ''
        Configuration written to Visual Studio Code's
        {file}`tasks.json`.
      '';
    };

    keybindings = mkOption {
      type = types.listOf (types.submodule {
        options = {
          key = mkOption {
            type = types.str;
            example = "ctrl+c";
            description = "The key or key-combination to bind.";
          };

          command = mkOption {
            type = types.str;
            example = "editor.action.clipboardCopyAction";
            description = "The VS Code command to execute.";
          };

          when = mkOption {
            type = types.nullOr (types.str);
            default = null;
            example = "textInputFocus";
            description = "Optional context filter.";
          };

          # https://code.visualstudio.com/docs/getstarted/keybindings#_command-arguments
          args = mkOption {
            type = types.nullOr (jsonFormat.type);
            default = null;
            example = { direction = "up"; };
            description = "Optional arguments for a command.";
          };
        };
      });
      default = [ ];
      example = literalExpression ''
        [
          {
            key = "ctrl+c";
            command = "editor.action.clipboardCopyAction";
            when = "textInputFocus";
          }
        ]
      '';
      description = ''
        Keybindings written to Visual Studio Code's
        {file}`keybindings.json`.
      '';
    };

    extensions = mkOption {
      type = types.listOf types.package;
      default = [ ];
      example = literalExpression "[ pkgs.vscode-extensions.bbenoist.nix ]";
      description = ''
        The extensions Visual Studio Code should be started with.
      '';
    };

    languageSnippets = mkOption {
      type = jsonFormat.type;
      default = { };
      example = {
        haskell = {
          fixme = {
            prefix = [ "fixme" ];
            body = [ "$LINE_COMMENT FIXME: $0" ];
            description = "Insert a FIXME remark";
          };
        };
      };
      description = "Defines user snippets for different languages.";
    };

    globalSnippets = mkOption {
      type = jsonFormat.type;
      default = { };
      example = {
        fixme = {
          prefix = [ "fixme" ];
          body = [ "$LINE_COMMENT FIXME: $0" ];
          description = "Insert a FIXME remark";
        };
      };
      description = "Defines global user snippets.";
    };

    enableUpdateCheck = mkOption {
      type = types.nullOr types.bool;
      default = null;
      description = ''
        Whether to enable update checks/notifications.
        Can only be set for the default profile, but
        it applies to all profiles.
      '';
    };

    enableExtensionUpdateCheck = mkOption {
      type = types.nullOr types.bool;
      default = null;
      description = ''
        Whether to enable update notifications for extensions.
        Can only be set for the default profile, but
        it applies to all profiles.
      '';
    };
  };

  profileType = types.submodule {
    options = profileOptions;
  };

  instanceType = types.submodule ({ name, config, ... }: {
    options = profileOptions // {
      enable = lib.mkOption {
        type = types.bool;
        default = true;
        example = false;
        description = ''
          Whether to enable this instance of Visual Studio Code.

          All defined instances are enabled by default.
        '';
      };

      name = mkOption {
        type = types.str;
        default = name;
        example = "vscode";
        description = ''
          The name of the instance. This is used to create
          the directory where the extensions are installed.

          Defaults to the name of the attribute set.
        '';
      };

      package = lib.mkPackageOption pkgs "vscode" {
        example = "pkgs.vscodium";
        extraDescription = "Version of Visual Studio Code to install.";
      };

      mutableExtensionsDir = mkOption {
        type = types.bool;
        default = false;
        example = true;
        description = ''
          Whether extensions can be installed or updated manually
          or by Visual Studio Code. Mutually exclusive to
          programs.vscode.profiles.
        '';
      };

      profiles = mkOption {
        type = types.attrsOf profileType;
        default = { };
        description = ''
          A list of all VSCode profiles. Mutually exclusive
          to programs.vscode.mutableExtensionsDir
        '';
      };
    };
  });

  mkWarnings = cfg:
    let
      inherit (profileInfos cfg) defaultProfile allProfilesExceptDefault;
    in
    [
      (mkIf (allProfilesExceptDefault != { } && cfg.mutableExtensionsDir)
        "programs.vscode.mutableExtensionsDir can be used only if no profiles apart from default are set.")
      (mkIf
        ((lib.filterAttrs
          (n: v:
            (v ? enableExtensionUpdateCheck || v ? enableUpdateCheck)
              && (v.enableExtensionUpdateCheck != null || v.enableUpdateCheck != null))
          allProfilesExceptDefault) != { })
        "The option programs.vscode.profiles.*.enableExtensionUpdateCheck and option programs.vscode.profiles.*.enableUpdateCheck is invalid for all profiles except default.")
    ];

  mkPackages = cfg: [
    (mkDerivation rec {
      pname = "${cfg.package.pname}-${cfg.name}";
      inherit (cfg.package) version;

      dontFetch = true;
      dontUnpack = true;
      dontPatch = true;
      dontConfigure = true;
      dontBuild = true;
      dontFixup = true;

      nativeBuildInputs = [ pkgs.makeWrapper ];

      installPhase = ''
        mkdir -p $out/bin
        makeWrapper \
          ${cfg.package}/bin/${cfg.package.executableName} \
          $out/bin/${cfg.name} \
          --inherit-argv0 \
          --add-flags '--user-data-dir="${userDir cfg}"' \
          --add-flags '--extensions-dir="${extensionPath cfg}"'
        chmod +x $out/bin/${cfg.name}
        mkdir -p $out/share/applications
        cp -r ${desktopItem}/share/applications/* $out/share/applications/
      '';

      desktopItem = makeDesktopItem {
        name = cfg.name;
        desktopName = "${cfg.package.longName or cfg.package.pname} (${cfg.name})";
        genericName = "Text Editor";
        icon = "vs${cfg.package.executableName}";
        exec = "${cfg.name} %F";
        categories = [ "Development" "Utility" "IDE" "TextEditor" ];
        keywords = [ "vscode" cfg.package.pname ];
        actions.new-empty-window = {
          name = "New Empty Window";
          exec = "${cfg.name} --new-window %F";
          icon = "vs${cfg.package.executableName}";
        };
      };
    })
  ];

  # The file `${userDir}/globalStorage/storage.json` needs to be writable by VSCode,
  # since it contains other data, such as theme backgrounds, recently opened folders, etc.

  # A caveat of adding profiles this way is, VSCode has to be closed
  # when this file is being written, since the file is loaded into RAM
  # and overwritten on closing VSCode.
  mkActivation = cfg:
    let
      inherit (profileInfos cfg) defaultProfile allProfilesExceptDefault;
    in
    {
      "${cfg.name}VscodeProfiles" = lib.hm.dag.entryAfter [ "writeBoundary" ]
        (
          let
            modifyGlobalStorage =
              pkgs.writeShellScript "vscode-global-storage-modify" ''
                PATH=${lib.makeBinPath [ pkgs.jq ]}''${PATH:+:}$PATH
                file="${userDir cfg}/globalStorage/storage.json"
                file_write=""
                profiles=(${
                  lib.escapeShellArgs
                  (flatten (mapAttrsToList (n: v: n) allProfilesExceptDefault))
                })

                if [ -f "$file" ]; then
                  existing_profiles=$(jq '.userDataProfiles // [] | map({ (.name): .location }) | add // {}' "$file")

                  for profile in "''${profiles[@]}"; do
                    if [[ "$(echo $existing_profiles | jq --arg profile $profile 'has ($profile)')" != "true" ]] || [[ "$(echo $existing_profiles | jq --arg profile $profile 'has ($profile)')" == "true" && "$(echo $existing_profiles | jq --arg profile $profile '.[$profile]')" != "\"$profile\"" ]]; then
                      file_write="$file_write$([ "$file_write" != "" ] && echo "...")$profile"
                    fi
                  done
                else
                  for profile in "''${profiles[@]}"; do
                    file_write="$file_write$([ "$file_write" != "" ] && echo "...")$profile"
                  done

                  mkdir -p $(dirname "$file")
                  echo "{}" > "$file"
                fi

                if [ "$file_write" != "" ]; then
                  userDataProfiles=$(jq ".userDataProfiles += $(echo $file_write | jq -R 'split("...") | map({ name: ., location: . })')" "$file")
                  echo $userDataProfiles > "$file"
                fi
              '';
          in
          modifyGlobalStorage.outPath
        );
    };

  mkFiles = cfg:
    let
      inherit (profileInfos cfg) defaultProfile allProfilesExceptDefault;
      vscodeVersion = cfg.package.version;
      vscodePname = cfg.package.pname;
    in
    lib.mkMerge (flatten [
      (mapAttrsToList
        (n: v: [
          (mkIf
            ((mergedUserSettings v.userSettings v.enableUpdateCheck
              v.enableExtensionUpdateCheck) != { })
            {
              "${configFilePath cfg n}".source =
                jsonFormat.generate "vscode-user-settings"
                  (mergedUserSettings v.userSettings v.enableUpdateCheck
                    v.enableExtensionUpdateCheck);
            })

          (mkIf (v.userTasks != { }) {
            "${tasksFilePath cfg n}".source =
              jsonFormat.generate "vscode-user-tasks" v.userTasks;
          })

          (mkIf (v.keybindings != [ ]) {
            "${keybindingsFilePath cfg n}".source =
              jsonFormat.generate "vscode-keybindings"
                (map (lib.filterAttrs (_: v: v != null)) v.keybindings);
          })

          (mkIf (v.languageSnippets != { }) (lib.mapAttrs'
            (language: snippet:
              lib.nameValuePair "${snippetDir cfg n}/${language}.json" {
                source =
                  jsonFormat.generate "user-snippet-${language}.json" snippet;
              })
            v.languageSnippets))

          (mkIf (v.globalSnippets != { }) {
            "${snippetDir n}/global.code-snippets".source =
              jsonFormat.generate "user-snippet-global.code-snippets"
                v.globalSnippets;
          })
        ])
        (allProfilesExceptDefault // {
          default = defaultProfile;
        }))

      # We write extensions.json for all profiles, except the default profile,
      # since that is handled by code below.
      (mkIf (allProfilesExceptDefault != { }) (lib.mapAttrs'
        (n: v:
          lib.nameValuePair "${userDir cfg}/profiles/${n}/extensions.json" {
            source = "${
              extensionJsonFile n (extensionJson v.extensions)
            }/share/vscode/extensions/extensions.json";
          })
        allProfilesExceptDefault))

      (mkIf (cfg.profiles != { } || defaultProfile != { }) (
        let
          # Adapted from https://discourse.nixos.org/t/vscode-extensions-setup/1801/2
          subDir = "share/vscode/extensions";
          toPaths = ext:
            map (k: { "${extensionPath cfg}/${k}".source = "${ext}/${subDir}/${k}"; })
              (if ext ? vscodeExtUniqueId then
                [ ext.vscodeExtUniqueId ]
              else
                builtins.attrNames (builtins.readDir (ext + "/${subDir}")));
        in
        if (cfg.mutableExtensionsDir && allProfilesExceptDefault == { }) then
        # Mutable extensions dir can only occur when only default profile is set.
        # Force regenerating extensions.json using the below method,
        # causes VSCode to create the extensions.json with all the extensions
        # in the extension directory, which includes extensions from other profiles.
          lib.mkMerge
            (lib.concatMap toPaths
              # only the default profile exists here
              (if (defaultProfile ? extensions) then defaultProfile.extensions else [ ])
            ++ lib.optional
              ((lib.versionAtLeast vscodeVersion "1.74.0"
                || vscodePname == "cursor") && defaultProfile != { })
              {
                # Whenever our immutable extensions.json changes, force VSCode to regenerate
                # extensions.json with both mutable and immutable extensions.
                "${extensionPath cfg}/.extensions-immutable.json" = {
                  text = extensionJson defaultProfile.extensions;
                  onChange = ''
                    run rm $VERBOSE_ARG -f ${extensionPath}/{extensions.json,.init-default-profile-extensions}
                    verboseEcho "Regenerating VSCode extensions.json"
                    run ${lib.getExe cfg.package} --list-extensions > /dev/null
                  '';
                };
              })
        else {
          "${extensionPath cfg}".source =
            let
              combinedExtensionsDrv = pkgs.buildEnv {
                name = "vscode-extensions";
                paths = (flatten (mapAttrsToList (n: v: v.extensions) cfg.profiles))
                  ++ defaultProfile.extensions
                  ++ lib.optional
                  ((lib.versionAtLeast vscodeVersion "1.74.0"
                    || vscodePname == "cursor") && defaultProfile != { })
                  (extensionJsonFile "default"
                    (extensionJson defaultProfile.extensions));
              };
            in
            "${combinedExtensionsDrv}/${subDir}";
        }
      ))
    ]);

  # TODO sanity check default profile vs immediate options
  profileInfos = cfg: {
    defaultProfile = if cfg.profiles ? default then cfg.profiles.default else {
      inherit (cfg) userSettings userTasks keybindings extensions
        languageSnippets globalSnippets enableUpdateCheck enableExtensionUpdateCheck;
    };
    allProfilesExceptDefault = removeAttrs cfg.profiles [ "default" ];
  };

in
{

  options.programs.vscodes = mkOption {
    type = types.attrsOf instanceType;
    default = { };
    example = ''
      {
        vscode = {
          enable = true;
          package = pkgs.vscodium;
          mutableExtensionsDir = false;
          profiles.default.userSettings."files.autoSave" = "off";
        };
      }
    '';
    description = ''
      Configuration for Visual Studio Code.

      Each instance of Visual Studio Code is configured
      using the attribute set name.
    '';
  };

  config = {
    warnings = lib.concatMap mkWarnings (lib.attrValues conf);

    home.packages = lib.concatMap mkPackages (lib.attrValues conf);
    home.activation = lib.concatMapAttrs (_: cfg: mkActivation cfg) conf;
    home.file = lib.mkMerge (flatten (lib.map mkFiles (lib.attrValues conf)));
  };

}
