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
