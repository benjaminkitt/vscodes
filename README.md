This is an experimental Home Manager module to enable management of several
Visual Studio Code(-ish) editors with shared configs, extensions etc.

The code is adapted from Home Managers' `vscode.nix` to support multiple
instances; it should work for any VSCode-derived editor that supports
``--user-data-dir`` and ``--extensions-dir`` arguments.

It works by creating a derivation consisting of an executable wrapper script
calling the original program with the above arguments (and also by default on
Linux a desktop item; if/when I find out how to make a Mac app bundle I'll do it
as well), and exposing this derivation in `home.packages` instead of the editor
package.

To use it, just add this flake to your Home Manager configuration's flake inputs,
preferably configure appropriate follows, import and configure your instances.

For an example of how to configure the editors, look into `example/vscode.nix`,
this is my configuration (somewhat censored).

I didn't really test mutable extensions nor profiles; they should work with one
big caveat: some options are available both in main instance configuration and
in profiles; if a profile named default exists, all of these options in main
configuration will be silently ignored. Home Manager's `vscode` module uses
renamed options, but these are not available in submodules (see https://github.com/NixOS/nixpkgs/issues/96006).
