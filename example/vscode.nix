{ inputs, ... }:
{ pkgs, lib, config, ... }:

/*

  in the flake add input like this:

    vscodes = {
      url = "github:jcszymansk/vscodes";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.homeManager.follows = "home-manager";
    };


*/

let
  inherit (pkgs.stdenv) isLinux;
  myvscode = with pkgs; (nur.repos.jacekszymanski.vscode-insiders.fhsWithPackages (_: [
    direnv
    nix
    nodejs
    gcc
    gnumake
    cmake
    binutils # C...
    docker

    libsecret # for gnome-keyring

    jdk17
    maven # for Netbeans & lemminx

  ]));


  # multiple vscode stuff
  baseVSConfig = {
    enableUpdateCheck = false;
    enableExtensionUpdateCheck = false;
    /* need mutable on mac, as cpptools work only when manually installed */
    mutableExtensionsDir = !isLinux;

    userSettings = with builtins; lib.foldl' lib.recursiveUpdate { } [
      (fromJSON (readFile ./vscode.json))
      {
        "java.configuration.runtimes" = [
          {
            name = "JavaSE-17";
            path = "${pkgs.jdk17}";
          }
        ];
      }

    ];

    extensions = (with pkgs.vscode-marketplace; [
      arrterian.nix-env-selector
      bbenoist.nix
      mkhl.direnv
      vscodevim.vim
      jarno-rajala.jslt-lang
      kevinrose.vsc-python-indent
      dgileadi.java-decompiler
      ms-vscode.remote-explorer
      jnoortheen.nix-ide
      gitworktrees.git-worktrees
      huizhou.githd
      ms-vscode-remote.remote-ssh-edit
      pinage404.nix-extension-pack
      gruntfuggly.todo-tree
      mhutchie.git-graph
      baileyfirman.vscode-back-forward-buttons
      ms-vscode-remote.remote-ssh
      ms-azuretools.vscode-docker
      (ms-vscode.cmake-tools.overrideAttrs (_: { sourceRoot = "extension"; }))
      dotjoshjohnson.xml
      thenuprojectcontributors.vscode-nushell-lang
      vscjava.vscode-maven
      vscjava.vscode-gradle
      dontshavetheyak.groovy-guru
      redhat.java
      ms-python.python
      ms-python.vscode-pylance
      ms-vscode-remote.remote-containers
      ms-vscode.remote-server
      github.vscode-github-actions

      kelvin.vscode-sshfs

      rust-lang.rust-analyzer
    ]) ++
    pkgs.lib.optionals isLinux (with pkgs.vscode-extensions; [
      ms-vscode.cpptools
    ]);

  };

  copilotConfig = {
    userSettings = with builtins; lib.foldl' lib.recursiveUpdate { } [
      (fromJSON (readFile ./vscode-copilot.json))
      (lib.listToAttrs
        (lib.forEach
          [ "code" "commitMessage" "pullRequestDescription" "test" ]
          (kind: {
            name = "github.copilot.chat.${kind}Generation.instructions";
            value = [
              { text = let path = ./ai/${kind}.md; in lib.optionalString (pathExists path) (readFile path); }
              { file = ".ai/instructions/${kind}.md"; }
            ];
          }
          )
        ))
    ];

    extensions = with pkgs.vscode-marketplace; [
      github.copilot-chat
      github.copilot
    ];
  };

  terminalConfig = let os = if isLinux then "linux" else "osx"; in {
    userSettings = {
      "terminal.integrated.profiles.${os}" = {
        zsh = {
          path = "${pkgs.zsh}/bin/zsh";
          args = [ "--login" ];
        };
      };
      "terminal.integrated.defaultProfile.${os}" = "zsh";
    };
  };
in
{

  imports = [ inputs.vscodes.modules.default ];

  config = {
    programs.vscodes.code-insiders = lib.mkMerge [
      baseVSConfig
      {
        package = if pkgs.stdenv.isLinux then myvscode else pkgs.nur.repos.jacekszymanski.vscode-insiders;
      }
      copilotConfig
      terminalConfig
    ];

    programs.vscodes.vscodium = lib.mkMerge [
      baseVSConfig
      terminalConfig
    ];

    programs.vscodes.code-server = lib.mkMerge [
      baseVSConfig
      {
        guiApplication = false;
      }
    ];

  };
}
