{ config, lib, ... }:

let
  cfg = config.services.laravel;

  siteOptions = {
    options = {
      domains = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "Hostnames served by this Laravel site.";
      };

      proxy = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Caddy reverse_proxy dial address for this site.";
      };

      phpFpm = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Caddy php_fastcgi dial address for this site.";
      };

      root = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Document root required when phpFpm is set.";
      };
    };
  };

  toVirtualHosts =
    site:
    let
      phpFpmRoot = if site.root == null then "/" else site.root;
      extraConfig =
        if site.proxy != null then
          ''
            reverse_proxy ${site.proxy}
          ''
        else
          ''
            root * ${phpFpmRoot}
            php_fastcgi ${site.phpFpm}
            file_server
          '';
    in
    lib.listToAttrs (
      map (domain: {
        name = domain;
        value = {
          serverAliases = [ ];
          inherit extraConfig;
        };
      }) site.domains
    );

  siteDomains = lib.concatMap (site: site.domains) cfg.sharedProxy.sites;
in
{
  options.services.laravel = {
    enable = lib.mkEnableOption "Laravel development support";

    sharedProxy.sites = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule siteOptions);
      default = [ ];
      example = lib.literalExpression ''
        [
          {
            domains = [ "app.localhost" ];
            proxy = "127.0.0.1:3000";
          }
          {
            domains = [ "api.localhost" ];
            phpFpm = "unix//''${config.devenv.root}/.devenv/run/php-fpm.sock";
            root = "''${config.devenv.root}/public";
          }
        ]
      '';
      description = ''
        Laravel sites exposed through services.sharedProxy. A site uses either
        proxy or phpFpm; PHP-FPM sites also require root.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (site: site.domains != [ ]) cfg.sharedProxy.sites;
        message = "services.laravel.sharedProxy.sites entries require at least one domain.";
      }
      {
        assertion = lib.all (site: (site.proxy == null) != (site.phpFpm == null)) cfg.sharedProxy.sites;
        message = "services.laravel.sharedProxy.sites entries require exactly one of proxy or phpFpm.";
      }
      {
        assertion = lib.all (
          site: site.phpFpm == null || (site.root != null && site.root != "")
        ) cfg.sharedProxy.sites;
        message = "services.laravel.sharedProxy.sites PHP-FPM entries require root.";
      }
      {
        assertion = builtins.length siteDomains == builtins.length (lib.unique siteDomains);
        message = "services.laravel.sharedProxy.sites domains must be unique.";
      }
    ];

    services.sharedProxy = {
      enable = true;
      virtualHosts = lib.mkMerge (map toVirtualHosts cfg.sharedProxy.sites);
    };
  };
}
