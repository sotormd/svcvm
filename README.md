# svcvm

Service virtual machines for NixOS (stripped down from
[microvm.nix](https://github.com/microvm-nix/microvm.nix)).

# Notice

For all practical purposes, svcvm is simply a stripped-down version of
[microvm.nix](https://github.com/microvm-nix/microvm.nix) containing only the
features that I personally require. Changes upstream may or may not be
backported.

svcvm contains substantial portions of code derived from the microvm.nix
project. A copy of the original MIT license is available in
[`LICENSES/MIT-microvm-nix`](./LICENSES/MIT-microvm-nix). Additional changes
introduced here, are licensed under [GPLv3](./LICENSE).

# Usage

If you wish to use svcvm for your own purposes, **please don't**. Consider using
[microvm.nix](https://github.com/microvm-nix/microvm.nix) instead, since it is
much more generic and intended for a wider range of use cases.

The documentation here is written only for my personal usage. This flake has no
tests or checks because the only configuration that matters is the one I
actually use in my [NixOS configuration](https://github.com/sotormd/nixos).
