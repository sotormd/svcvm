# secrets and credentials shared with the svcvm guest using io.systemd.credentials

{ config, ... }:

{
  # final list of creds
  _internal.creds = config.svcvm.creds;
}
