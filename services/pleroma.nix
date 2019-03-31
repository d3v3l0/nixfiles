{ config, lib, pkgs, ...}:

with lib;

{
  options.services.pleroma = {
    virtualhost = mkOption { type = types.str; };
    port        = mkOption { type = types.int; default = 4000; };
  };

  config = {
    environment.systemPackages = with pkgs; [ elixir erlang ];

    systemd.services.pleroma = {
      after         = [ "network.target" "postgresql.service" ];
      description   = "Pleroma social network";
      wantedBy      = [ "multi-user.target" ];
      path          = with pkgs; [ elixir git openssl ];
      environment   = {
        HOME    = config.users.extraUsers.pleroma.home;
        MIX_ENV = "prod";
      };
      serviceConfig = {
        WorkingDirectory = "${config.users.extraUsers.pleroma.home}/pleroma";
        User       = "pleroma";
        ExecStart  = "${pkgs.elixir}/bin/mix phx.server";
        ExecReload = "${pkgs.coreutils}/bin/kill $MAINPID";
        KillMode   = "process";
        Restart    = "on-failure";
      };
    };

    services.postgresql.enable = true;
    services.postgresql.package = pkgs.postgresql96;

    # https://git.pleroma.social/pleroma/pleroma/blob/develop/installation/pleroma.nginx
    services.nginx.virtualHosts."${config.services.pleroma.virtualhost}" = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString config.services.pleroma.port}/";
        proxyWebsockets = true;
        extraConfig = "client_max_body_size 16m;";
      };
      locations."/proxy".proxyPass = "http://localhost:${toString config.services.pleroma.port}/";
    };

    users.extraUsers.pleroma = {
      home = "/srv/pleroma";
      createHome = true;
      isSystemUser = true;
    };
  };
}
