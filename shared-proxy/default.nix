{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.sharedProxy;

  defaultStateDirectory =
    let
      home = builtins.getEnv "HOME";
    in
    if home == "" then
      throw "services.sharedProxy.stateDirectory requires HOME during evaluation or an explicit value"
    else
      "${home}/.local/state/devenv-shared-caddy";

  vhostOptions = {
    options = {
      serverAliases = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "www.example.test" ];
        description = "Additional names served by this virtual host.";
      };

      extraConfig = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Caddyfile directives for this virtual host.";
      };
    };
  };

  vhostToConfig = vhostName: vhostAttrs: ''
    ${vhostName} ${builtins.concatStringsSep " " vhostAttrs.serverAliases} {
    ${vhostAttrs.extraConfig}
    }
  '';

  projectCaddyfile = lib.concatStringsSep "\n" (lib.mapAttrsToList vhostToConfig cfg.virtualHosts);

  stateDirectoryPrelude = ''
    export DEVENV_SHARED_PROXY_STATE_DIR=${lib.escapeShellArg cfg.stateDirectory}
  '';

  defaultCliPackage = pkgs.writeShellApplication {
    name = "shared-proxy";
    runtimeInputs = [
      cfg.package
      pkgs.coreutils
      pkgs.lsof
    ];
    text = stateDirectoryPrelude + builtins.readFile ./shared-proxy.sh;
  };

  registrarCommand =
    "DEVENV_SHARED_PROXY_STATE_DIR=${lib.escapeShellArg cfg.stateDirectory} "
    + "printf %s ${lib.escapeShellArg projectCaddyfile} | "
    + "${cfg.cliPackage}/bin/shared-proxy registrar "
    + lib.escapeShellArg cfg.projectId;

  configuredNames = lib.concatMap (
    vhostName: [ vhostName ] ++ cfg.virtualHosts.${vhostName}.serverAliases
  ) (lib.attrNames cfg.virtualHosts);
in
{
  options.services.sharedProxy = {
    enable = lib.mkEnableOption "the shared local Caddy proxy";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.caddy;
      defaultText = lib.literalExpression "pkgs.caddy";
      description = "Caddy package used by the singleton proxy.";
    };

    cliPackage = lib.mkOption {
      type = lib.types.package;
      default = defaultCliPackage;
      defaultText = lib.literalExpression "the shared-proxy management package";
      description = "Management package added to enabled project shells.";
      internal = true;
    };

    stateDirectory = lib.mkOption {
      type = lib.types.str;
      default = defaultStateDirectory;
      defaultText = lib.literalExpression ''"$HOME/.local/state/devenv-shared-caddy"'';
      description = "Shared persistent state directory.";
    };

    rootCA = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${cfg.stateDirectory}/data/caddy/pki/authorities/local/root.crt";
      defaultText = lib.literalExpression ''
        "<stateDirectory>/data/caddy/pki/authorities/local/root.crt"
      '';
      description = ''
        Path to Caddy's local root CA certificate. The certificate is created
        after the shared proxy starts.
      '';
    };

    projectId = lib.mkOption {
      type = lib.types.str;
      default = builtins.substring 0 16 (builtins.hashString "sha256" config.devenv.root);
      defaultText = lib.literalExpression "a stable hash of config.devenv.root";
      description = "Stable identifier used to own this project's active routes.";
    };

    virtualHosts = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule vhostOptions);
      default = { };
      example = lib.literalExpression ''
        {
          "app.localhost" = {
            serverAliases = [ "www.app.localhost" ];
            extraConfig = "reverse_proxy 127.0.0.1:3000";
          };
        }
      '';
      description = ''
        Virtual hosts added to the shared Caddy instance while this devenv
        process is running. The contents are Caddyfile directives and may use
        any handler supported by the configured Caddy package.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.match "^[A-Za-z0-9._-]+$" cfg.projectId != null;
        message = "services.sharedProxy.projectId may contain only letters, numbers, dots, underscores, and hyphens.";
      }
      {
        assertion = cfg.stateDirectory != "" && lib.hasPrefix "/" cfg.stateDirectory;
        message = "services.sharedProxy.stateDirectory must be an absolute path.";
      }
      {
        assertion = lib.all (name: name != "") configuredNames;
        message = "services.sharedProxy virtual host names and aliases must not be empty.";
      }
      {
        assertion = builtins.length configuredNames == builtins.length (lib.unique configuredNames);
        message = "services.sharedProxy virtual host names and aliases must be unique within a project.";
      }
    ];

    packages = [ cfg.cliPackage ];

    processes = lib.mkIf (cfg.virtualHosts != { }) {
      shared-proxy = {
        exec = registrarCommand;
        restart.on = "never";
        linux.capabilities = [ "net_bind_service" ];
      };
    };
  };
}
