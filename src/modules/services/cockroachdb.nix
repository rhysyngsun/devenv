{ pkgs, lib, config, ... }:

with lib;

let
  cfg = config.services.cockroachdb;

  setupScript = pkgs.writeShellScriptBin "setup-cockroachdb" ''
    set -euo pipefail

    mkdir -p "$COCKROACH_DATA_DIR"
    mkdir -p "$COCKROACH_CERTS_DIR"
  
    if [[ ! -f "$COCKROACH_CA_KEY" ]]; then
      ${cfg.package}/bin/cockroach cert create-ca \
        --certs-dir=$COCKROACH_CERTS_DIR
    fi

    if [[ ! -f "$COCKROACH_CERTS_DIR/node.key" ]]; then
      ${cfg.package}/bin/cockroach cert create-node \
        localhost \
        ${cfg.bind} \
        --certs-dir=$COCKROACH_CERTS_DIR \
        --overwrite
    fi

    if [[ ! -f "$COCKROACH_CERTS_DIR/client.$COCKROACH_USER.key" ]]; then
      ${cfg.package}/bin/cockroach cert create-client \
        $COCKROACH_USER \
        --certs-dir=$COCKROACH_CERTS_DIR \
        --overwrite
    fi
  '';

  startScript = pkgs.writeShellScriptBin "start-cockroachdb" ''
    set -euo pipefail

    ${setupScript}/bin/setup-cockroachdb

    exec ${cfg.package}/bin/cockroach start-single-node \
      --listen-addr=${toString cfg.bind}:${toString cfg.port} \
      --http-addr=${toString cfg.bind}:${toString cfg.httpPort} \
      --certs-dir=$COCKROACH_CERTS_DIR \
      --store=${cfg.store}
      ${concatStringsSep " " cfg.startArgs}
  '';
in
{
  imports = [
    (mkRenamedOptionModule [ "cockroachdb" "enable" ] [ "services" "cockroachdb" "enable" ])
  ];

  options.services.cockroachdb = {
    enable = mkEnableOption "CockroachDB process and expose utilities.";

    package = mkOption {
      type = types.package;
      description = "Which package of CockroachDB to use.";
      default = pkgs.cockroachdb;
      defaultText = literalExpression "pkgs.cockroachdb";
    };

    bind = mkOption {
      type = types.nullOr types.str;
      default = "127.0.0.1";
      description = ''
        The IP interface to bind to.
        `null` means "all interfaces".
      '';
      example = "127.0.0.1";
    };

    port = mkOption {
      type = types.port;
      default = 26257;
      description = ''
        The TCP port to accept inter-node and client-node connections.
      '';
    };

    httpPort = mkOption {
      type = types.port;
      default = 8080;
      description = ''
        The HTTP port to accept connections for the DB Console.
      '';
    };

    user = mkOption {
      type = types.str;
      default = "root";
      description = ''
        The user to create client certificates for.
      '';
    };

    store = mkOption {
      type = types.str;
      default = "path=${config.env.COCKROACH_DATA_DIR}/store/";
      description = ''
        The store settings to pass to CockroachDB.
      '';
    };

    startArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "--cache=1GB" ];
      description = ''
        Additional arguments passed to CockroachDB during startup.
      '';
    };
  };

  config = mkIf cfg.enable {
    packages = [
      cfg.package
      setupScript
      startScript
    ];

    processes.cockroachdb.exec = "${startScript}/bin/start-cockroachdb";

    env.COCKROACH_HOST = cfg.bind;
    env.COCKROACH_PORT = cfg.port;
    env.COCKROACH_USER = cfg.user;
    env.COCKROACH_DATA_DIR = "${config.env.DEVENV_STATE}/cockroachdb";
    env.COCKROACH_CERTS_DIR = "${config.env.COCKROACH_DATA_DIR}/certs";
    env.COCKROACH_CA_KEY = "${config.env.COCKROACH_DATA_DIR}/ca.key";
  };
}
