{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05-small";
    elixir-overlay.url = "github:zoedsoupe/elixir-overlay";
  };

  outputs = {
    nixpkgs,
    elixir-overlay,
    ...
  }: let
    inherit (nixpkgs.lib) genAttrs;
    inherit (nixpkgs.lib.systems) flakeExposed;
    forAllSystems = f:
      genAttrs flakeExposed (system:
        f (import nixpkgs {
          inherit system;
          overlays = [elixir-overlay.overlays.default];
        }));
  in {
    devShells = forAllSystems (pkgs: let
      inherit (pkgs) mkShell;
      inherit (pkgs.beam.interpreters) erlang_28;
    in {
      default = mkShell {
        name = "aike";
        packages = with pkgs;
          [(elixir-with-otp erlang_28).latest postgresql_18 docker-compose curl jq]
          ++ lib.optionals stdenv.isLinux [inotify-tools]
          ++ lib.optionals stdenv.isDarwin [
            darwin.apple_sdk.frameworks.CoreServices
            darwin.apple_sdk.frameworks.CoreFoundation
          ];
      };
    });
  };
}
