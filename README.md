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

To store the proxy's persistent data in a specific location, set
`stateDirectory` to an absolute path:

```nix
services.sharedProxy.stateDirectory = "/path/to/caddy-state";
```

## Laravel

Use `services.laravel` to configure Laravel sites through the shared proxy.
Set each site's domains and choose either a reverse proxy or PHP-FPM:

```nix
# devenv.nix
services.laravel = {
  enable = true;
  sharedProxy.sites = [
    {
      domains = [ "frontend.app.localhost" ];
      proxy = "127.0.0.1:3000";
    }
    {
      domains = [ "api.app.localhost" ];
      phpFpm = "unix//${config.devenv.root}/.devenv/run/php-fpm.sock";
      root = "${config.devenv.root}/public";
    }
  ];
};
```

For each site, set exactly one of:

- `proxy` for an application server address such as `127.0.0.1:3000`.
- `phpFpm` for a PHP-FPM address. Also set `root` to the Laravel `public`
  directory.

`services.laravel` enables the shared proxy automatically. Use
`services.sharedProxy.virtualHosts` directly when a site needs Caddy directives
that are not covered by these Laravel options.
