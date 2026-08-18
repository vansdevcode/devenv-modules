# devenv extensions

This repository exposes reusable devenv modules. Import the repository once,
then enable the modules needed by each project.

```yaml
# devenv.yaml
inputs:
  devenv-extensions:
    url: github:your-org/devenv-extensions
    flake: false

imports:
  - devenv-extensions
```

## Shared proxy

`services.sharedProxy` runs one Caddy instance per user. Enabled devenv
processes atomically add a project Caddyfile under the shared state directory;
the root Caddyfile imports every project file. When a project starts or stops,
the singleton starts, reloads, or stops Caddy as appropriate.

```nix
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

The virtual-host names are passed to Caddy unchanged; they are not limited to
`.localhost`. The singleton uses Caddy's internal CA, so it can issue local
certificates for every configured hostname. It owns ports 80 and 443, so a
project-local web server must use another port or socket.

Persistent Caddy state defaults to
`$XDG_STATE_HOME/devenv-shared-caddy`, falling back to
`~/.local/state/devenv-shared-caddy`. Project files live in its `sites/`
directory; runtime files, including the admin Unix socket, use
`$XDG_RUNTIME_DIR` or a short temporary-directory fallback.

## Laravel

`services.laravel` is a Laravel-focused module that expands simple site
definitions into shared-proxy virtual hosts.

```nix
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

Each Laravel site uses exactly one of `proxy` or `phpFpm`; PHP-FPM sites also
require `root`. For other Caddy directives, configure
`services.sharedProxy.virtualHosts` directly.
