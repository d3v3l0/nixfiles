{ config, pkgs, lib, ... }:

let
  radio = import ./service-radio.nix { inherit lib pkgs; };

  radioChannels = [
    { channel = "everything"; port = 6600; description = "all the music, all the time"
    ; mpdPassword  = import /etc/nixos/secrets/everything-password-mpd.nix
    ; livePassword = import /etc/nixos/secrets/everything-password-live.nix
    ; }
    { channel = "cyberia"; port = 6601; description = "classic lainchan radio: electronic, chiptune, weeb"
    ; mpdPassword  = import /etc/nixos/secrets/cyberia-password-mpd.nix
    ; livePassword = import /etc/nixos/secrets/cyberia-password-live.nix
    ; }
    { channel = "swing"; port = 6602; description = "swing, electroswing, and jazz"
    ; mpdPassword  = import /etc/nixos/secrets/swing-password-mpd.nix
    ; livePassword = import /etc/nixos/secrets/swing-password-live.nix
    ; }
    { channel = "cafe"; port = 6603; description = "music to drink tea to"
    ; mpdPassword  = import /etc/nixos/secrets/cafe-password-mpd.nix
    ; livePassword = import /etc/nixos/secrets/cafe-password-live.nix
    ; }
  ];
in

{
  networking.hostName = "lainonlife";

  # Bootloader
  boot.loader.grub.enable  = true;
  boot.loader.grub.version = 2;
  boot.loader.grub.device  = "/dev/sda";

  # OVH network set up
  networking.interfaces.eno1 = {
    ipv4.addresses = [ { address = "91.121.0.148";           prefixLength = 24;  } ];
    ipv6.addresses = [ { address = "2001:41d0:0001:5394::1"; prefixLength = 128; } ];
  };

  networking.defaultGateway  = "91.121.0.254";
  networking.defaultGateway6 = "2001:41d0:0001:53ff:ff:ff:ff:ff";

  networking.nameservers = [ "213.186.33.99" "2001:41d0:3:1c7::1" ];

  # No syncthing
  services.syncthing.enable = lib.mkForce false;

  # Firewall
  networking.firewall.allowedTCPPorts = [ 80 443 8000 ];
  networking.firewall.allowedTCPPortRanges = [ { from = 62001; to = 63000; } ];
  networking.firewall.allowedUDPPortRanges = [ { from = 62001; to = 63000; } ];

  # Web server
  services.caddy.enable = true;
  services.caddy.config = ''
    www.lainon.life {
      redir https://lainon.life{uri}
    }

    lainon.life {
      log / stdout "{host} {combined}"
      gzip

      root /srv/http/www

      proxy /radio/ http://localhost:8000 {
        without /radio
        transparent
      }

      proxy /graphs/ http://localhost:8001 {
        without /graphs
      }

      proxy /background http://localhost:8002
      proxy /upload     http://localhost:8002
      proxy /playlist   http://localhost:8002
      proxy /dj         http://localhost:8002
      proxy /admin      http://localhost:8002
    }

    social.lainon.life {
      log / stdout "{host} {combined}"
      gzip

      proxy / http://127.0.0.1:${toString config.services.pleroma.port} {
        websocket
        transparent
      }
    }
  '';

  services.logrotate.enable = true;
  services.logrotate.config = ''
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
    let service = {user, description, execstart, environment ? {}, ...}: {
          inherit environment description;
          after         = [ "network.target" ];
          wantedBy      = [ "multi-user.target" ];
          serviceConfig = { User = user; ExecStart = execstart; Restart = "on-failure"; };
        };
    in lib.mkMerge
      [ (lib.listToAttrs (map (c@{channel, ...}: lib.nameValuePair "mpd-${channel}"       (radio.mpdServiceFor         c)) radioChannels))
        (lib.listToAttrs (map (c@{channel, ...}: lib.nameValuePair "programme-${channel}" (radio.programmingServiceFor c)) radioChannels))

      { fallback-mp3 = radio.fallbackServiceForMP3 "/srv/radio/music/fallback.mp3"; }
      { fallback-ogg = radio.fallbackServiceForOgg "/srv/radio/music/fallback.ogg"; }

      # Because I am defining systemd.services in its entirety here, all services defined in this
      # file need to live in this list too.
      { metrics =
          let penv = pkgs.python3.buildEnv.override {
                extraLibs = with pkgs.python3Packages; [docopt influxdb psutil];
              };
          in service {
            # This needs to run as root so that `du` can measure everything.
            user = "root";
            description = "Report metrics";
            execstart = "${pkgs.python3}/bin/python3 /srv/radio/scripts/metrics.py";
            environment = {
              PYTHONPATH = "${penv}/${pkgs.python3.sitePackages}/";
            };
          };
      }

      { "http-backend" = service {
          user = "${radio.username}";
          description = "HTTP backend service";
          execstart = "${pkgs.bash}/bin/bash -l -c '/srv/radio/backend/run.sh serve --config=/srv/radio/config.json 8002'";
        };
      }
    ];

  environment.systemPackages = with pkgs; [ flac id3v2 ncmpcpp openssl python3Packages.virtualenv ];

  nixpkgs.config.packageOverrides = pkgs: {
    # Build MPD with libmp3lame support, so shoutcast output can do mp3.
    mpd = pkgs.mpd.overrideAttrs (oldAttrs: rec {
      buildInputs = oldAttrs.buildInputs ++ [ pkgs.lame ];
    });
  };

  # Pleroma
  services.pleroma.enable = true;

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

  # barrucadu.dev concourse access
  users.extraUsers.concourse-deploy-robot = {
    home = "/home/system/concourse-deploy-robot";
    createHome = true;
    isSystemUser = true;
    openssh.authorizedKeys.keys =
      [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBkO09nIUCsg9gy6+qZan/r6fkUpwlsvLUeSwJMLO6X3 concourse-worker@cd.barrucadu.dev" ];
    shell = pkgs.bashInteractive;
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
