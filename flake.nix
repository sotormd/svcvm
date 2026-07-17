{
  description = "service virtual machines for NixOS, derived from microvm.nix; https://github.com/microvm-nix/microvm.nix.";
  outputs = _: { nixosModules.host = ./module; };
}
