# devenv modules

Add this repository to a devenv project, then configure the modules you need.

```yaml
# devenv.yaml
inputs:
  devenv-modules:
    url: github:vansdevcode/devenv-modules
    flake: false

imports:
  - devenv-modules
```

## Shared proxy

Use `services.sharedProxy` to serve a local development application over HTTPS.
Configure a hostname and the Caddy directives that handle requests for it:

```nix
# devenv.nix
services.sharedProxy = {
  enable = true;
  virtualHosts."app.localhost" = {
    serverAliases = [ "www.app.localhost" ];
    extraConfig = ''
      reverse_proxy 127.0.0.1:3000
    '';
  };
};
```

Start your devenv environment, then open
[`https://app.localhost`](https://app.localhost). `serverAliases` lets the
same virtual host respond to additional names. `extraConfig` accepts Caddyfile
directives, so it can proxy to a local server, serve static files, or use other
Caddy handlers.

Hostnames are passed to Caddy unchanged; they do not need a `.localhost`
suffix. The proxy uses Caddy's local CA for certificates. It uses ports 80 and
443, so configure the application server on another port or a Unix socket.
The management command keeps Caddy's admin API on a private Unix socket and
uses that socket for startup trust installation, reloads, and shutdown.

Caddy's local root certificate is available to project configuration as
`config.services.sharedProxy.rootCA`. For example, PHP's cURL extension can use
it for local HTTPS requests:

```nix
{ config, ... }:

{
  languages.php.ini = ''
    curl.cainfo = "${config.services.sharedProxy.rootCA}"
  '';
}
```

The file is created when the shared proxy first starts. `curl.cainfo` replaces
libcurl's default CA bundle, so combine the root certificate with the usual CA
bundle if the same PHP process also calls public HTTPS endpoints. There is no
portable PHP setting that makes libcurl use the operating-system trust store
on both Linux and macOS; that behavior depends on libcurl's TLS backend.
