{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./shared-proxy
    ./laravel
  ];
}
