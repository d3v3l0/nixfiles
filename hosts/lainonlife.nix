{ config, pkgs, lib, ... }:

let
  radio = import ./hosts/lainonlife/radio.nix { inherit lib pkgs; };

  radioChannels = [
    { channel = "everything"; port = 6600; description = "all the music, all the time";                        password = import /etc/nixos/secrets/everything-password.nix; }
    { channel = "cyberia";    port = 6601; description = "classic lainchan radio: electronic, chiptune, weeb"; password = import /etc/nixos/secrets/cyberia-password.nix; }
    { channel = "swing";      port = 6602; description = "swing, electroswing, and jazz";                      password = import /etc/nixos/secrets/swing-password.nix; }
    { channel = "cafe";       port = 6603; description = "music to drink tea to";                              password = import /etc/nixos/secrets/cafe-password.nix; }
  ];
in

{
  networking.hostName = "lainonlife";

  imports = [
    ./common.nix
    ./hardware-configuration.nix
  ];

  # Bootloader
  boot.loader.grub.enable  = true;
  boot.loader.grub.version = 2;
  boot.loader.grub.device  = "/dev/sda";

  # OVH network set up
  networking.interfaces.eno1 = {
    ip4 = [ { address = "91.121.0.148";           prefixLength = 24;  } ];
    ip6 = [ { address = "2001:41d0:0001:5394::1"; prefixLength = 128; } ];
  };

  networking.defaultGateway  = "91.121.0.254";
  networking.defaultGateway6 = "2001:41d0:0001:53ff:ff:ff:ff:ff";

  networking.nameservers = [ "213.186.33.99" "2001:41d0:3:1c7::1" ];

  # No syncthing
  services.syncthing.enable = lib.mkForce false;

  # Firewall
  networking.firewall.allowPing = true;
  networking.firewall.allowedTCPPorts = [ 80 443 8000 ];
  networking.firewall.allowedTCPPortRanges = [ { from = 60000; to = 63000; } ];
  networking.firewall.allowedUDPPortRanges = [ { from = 60000; to = 63000; } ];

  # Web server
  services.nginx.enable = true;
  services.nginx.recommendedGzipSettings  = true;
  services.nginx.recommendedOptimisation  = true;
  services.nginx.recommendedProxySettings = true;
  services.nginx.recommendedTlsSettings   = true;
  services.nginx.virtualHosts."lainon.life" = {
    serverAliases = [ "www.lainon.life" ];
    enableACME = true;
    forceSSL = true;
    default = true;
    root = "/srv/http";
    locations."/".extraConfig = "try_files $uri $uri/ @script;";
    locations."/radio/".proxyPass  = "http://localhost:8000/";
    locations."/graphs/".proxyPass = "http://localhost:8001/";
    locations."@script".proxyPass = "http://localhost:8002";
    extraConfig = ''
      add_header 'Access-Control-Allow-Origin' '*';
      add_header 'Referrer-Policy' 'strict-origin-when-cross-origin';
      proxy_max_temp_file_size 0;
    '';
  };

  services.logrotate.enable = true;
  services.logrotate.config = ''
/var/spool/nginx/logs/access.log /var/spool/nginx/logs/error.log {
    daily
    copytruncate
    rotate 1
    compress
    postrotate
        systemctl kill nginx.service --signal=USR1
    endscript
}
/var/log/icecast/access.log /var/log/icecast/error.log {
    daily
    copytruncate
    rotate 1
    compress
    postrotate
        systemctl kill icecast.service --signal=HUP
    endscript
}
  '';

  # Radio
  users.extraUsers."${radio.username}" = radio.userSettings;
  services.icecast = radio.icecastSettingsFor radioChannels;
  systemd.services =
    let service = {user, description, execstart, ...}: {
          after         = [ "network.target" ];
          description   = description;
          wantedBy      = [ "multi-user.target" ];
          serviceConfig = { User = user; ExecStart = execstart; Restart = "on-failure"; };
        };
    in lib.mkMerge
      [ (lib.listToAttrs (map (c@{channel, ...}: lib.nameValuePair "mpd-${channel}"       (radio.mpdServiceFor         c)) radioChannels))
        (lib.listToAttrs (map (c@{channel, ...}: lib.nameValuePair "programme-${channel}" (radio.programmingServiceFor c)) radioChannels))

      # Because I am defining systemd.services in its entirety here, all services defined in this
      # file need to live in this list too.
      { metrics = service {
          # This needs to run as root so that `du` can measure everything.
          user = "root";
          description = "Report metrics";
          execstart = "${pkgs.python3}/bin/python3 /srv/radio/scripts/metrics.py";
        };
      }

      { "http-backend" = service {
          user = config.services.nginx.user;
          description = "HTTP backend service";
          execstart = "${pkgs.bash}/bin/bash -l -c '/srv/radio/backend/run.sh serve --channels=/srv/radio/channels.json 8002'";
        };
      }
    ];
  environment.systemPackages = with pkgs; [ flac id3v2 ncmpcpp python35Packages.virtualenv ];

  nixpkgs.config.packageOverrides = pkgs: {
    # Build MPD with libmp3lame support, so shoutcast output can do mp3.
    mpd = pkgs.mpd.overrideAttrs (oldAttrs: rec {
      buildInputs = oldAttrs.buildInputs ++ [ pkgs.lame ];
    });

    # Set up the Python 3 environment we want for the systemd services.
    python3 = pkgs.python35.withPackages (p: [p.docopt p.influxdb p.mpd2 p.psutil]);
  };

  # Fancy graphs
  services.influxdb.enable = true;

  services.grafana = {
    enable = true;
    port = 8001;
    domain = "lainon.life";
    rootUrl = "https://lainon.life/graphs/";
    security.adminPassword = import /etc/nixos/secrets/grafana-admin-password.nix;
    security.secretKey = import /etc/nixos/secrets/grafana-key.nix;
    auth.anonymous.enable = true;
    auth.anonymous.org_name = "lainon.life";
  };

  # Extra users
  users.extraUsers.appleman1234 = {
    uid = 1001;
    description = "Appleman1234 <admin@lainchan.org>";
    isNormalUser = true;
    group = "users";
  };
  users.extraUsers.yuuko = {
    uid = 1002;
    description = "Yuuko";
    isNormalUser = true;
    group = "users";
    extraGroups = [ "audio" ];
  };
}
