# vsock, for ssh from host to guest

{ config, ... }:

{
  # final vsock cid
  _internal.vsock-cid = config.svcvm.vsock-cid;
}
