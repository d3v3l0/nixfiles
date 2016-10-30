{ config, pkgs, lib, ... }:

with lib;

let
  acmedir = "/var/acme-challenges";

  acmeconf = ''
    location '/.well-known/acme-challenge' {
      default_type "text/plain";
      root ${acmedir};
    }
  '';

  wwwRedirect = domain:
    { hostname = domain
    ; certname = domain
    ; to = "https://www.${domain}"
    ; config = acmeconf
    ; httpAlso = true
    ; };

  cert = extras:
    { webroot = acmedir
    ; extraDomains = genAttrs extras (name: null)
    ; email = "mike@barrucadu.co.uk"
    ; user = "nginx"
    ; group = "nginx"
    ; allowKeysForGroup = true
    ; };

  container = num: config:
    { autoStart      = true
    ; privateNetwork = true
    ; hostAddress    = "192.168.254.${toString num}"
    ; localAddress   = "192.168.255.${toString num}"
    ; config         = config
    ; };

  nginxContainer = num: domain: ''
    server {
      listen  443       ssl  spdy;
      listen  [::]:443  ssl  spdy;

      server_name  ${domain}, *.${domain};

      ssl_certificate      ${config.security.acme.directory}/${domain}/fullchain.pem;
      ssl_certificate_key  ${config.security.acme.directory}/${domain}/key.pem;

      location / {
        proxy_pass        http://192.168.255.${toString num};
        proxy_redirect    off;
        proxy_set_header  Host             $host;
        proxy_set_header  X-Real-IP        $remote_addr;
        proxy_set_header  X-Forwarded-For  $proxy_add_x_forwarded_for;
      }
    }
    '';

in

{
  networking.hostName = "innsmouth";

  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix

      # Include the standard configuration.
      ./base/default.nix

      # Include other configuration.
      ./services/nginx.nix
      ./services/openssh.nix
    ];

  # Bootloader
  boot.loader.grub.enable  = true;
  boot.loader.grub.version = 2;
  boot.loader.grub.device  = "/dev/sda";

  # Use the serial console (required for lish)
  boot.kernelParams = [ "console=ttyS0" ];
  boot.loader.grub.extraConfig = "serial; terminal_input serial; terminal_output serial";

  # Firewall and container NAT
  networking.firewall.allowPing = true;
  networking.firewall.allowedTCPPorts = [ 21 70 80 443 873 ];
  networking.firewall.allowedUDPPortRanges = [ { from = 60000; to = 61000; } ];

  networking.nat.enable = true;
  networking.nat.internalInterfaces = ["ve-+"];
  networking.nat.externalInterface = "enp0s4";
  networking.nat.forwardPorts =
    [ { sourcePort = 21;  destination = "192.168.255.1:21"; }
      { sourcePort = 873; destination = "192.168.255.1:873"; }
      { sourcePort = 70;  destination = "192.168.255.2:70"; }
    ];

  # Container configuration
  containers.archhurd  = container 1 (import ./containers/innsmouth-archhurd.nix);
  containers.barrucadu = container 2 (import ./containers/innsmouth-barrucadu.nix);
  containers.mawalker  = container 3 (import ./containers/innsmouth-mawalker.nix);
  containers.uzbl      = container 4 (import ./containers/innsmouth-uzbl.nix);

  # Web server
  services.nginx.enablePHP = true;

  services.nginx.extraConfig = ''
    ${nginxContainer 1 "archhurd.org"}
    ${nginxContainer 2 "barrucadu.co.uk"}
    ${nginxContainer 3 "mawalker.me.uk"}
    ${nginxContainer 4 "uzbl.org"}
  '';

  services.nginx.redirects =
    [ # Redirect http{s,}://foo to https://www.foo
      (wwwRedirect "barrucadu.co.uk")
      (wwwRedirect "mawalker.me.uk")
      (wwwRedirect "archhurd.org")
      (wwwRedirect "uzbl.org")

      # Redirect barrucadu.com to barrucadu.co.uk
      { hostname = "barrucadu.com"
      ; certname = "barrucadu.com"
      ; to = "https://www.barrucadu.co.uk"
      ; config = acmeconf
      ; httpAlso = true
      ; }

      # Redirects http to https
      { hostname = "docs.barrucadu.co.uk"; config = acmeconf; }
      { hostname = "go.barrucadu.co.uk";   config = acmeconf; }
      { hostname = "misc.barrucadu.co.uk"; config = acmeconf; }
      { hostname = "wiki.barrucadu.co.uk"; config = acmeconf; }
      { hostname = "aur.archhurd.org";     config = acmeconf; }
      { hostname = "bugs.archhurd.org";    config = acmeconf; }
      { hostname = "files.archhurd.org";   config = acmeconf; }
      { hostname = "lists.archhurd.org";   config = acmeconf; }
      { hostname = "wiki.archhurd.org";    config = acmeconf; }
    ];

  # SSL certificates
  security.acme.certs =
    { "barrucadu.co.uk" = cert [ "www.barrucadu.co.uk" "docs.barrucadu.co.uk" "go.barrucadu.co.uk" "misc.barrucadu.co.uk" "wiki.barrucadu.co.uk" ]
    ; "barrucadu.com"   = cert [ "www.barrucadu.com" ]
    ; "mawalker.me.uk"  = cert [ "www.mawalker.me.uk" ]
    ; "archhurd.org"    = cert [ "www.archhurd.org" "aur.archhurd.org" "bugs.archhurd.org" "files.archhurd.org" "lists.archhurd.org" "wiki.archhurd.org" ]
    ; "uzbl.org"        = cert [ "www.uzbl.org" ]
    ; };

  # Databases
  services.mongodb =
    { enable = true
    ; };

  # Gitolite
  services.gitolite =
    { enable = true
    ; user = "git"
    ; dataDir = "/srv/git"
    ; adminPubkey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDILnZ0gRTqD6QnPMs99717N+j00IEESLRYQJ33bJ8mn8kjfStwFYFhXvnVg7iLV1toJ/AeSV9jkCY/nVSSA00n2gg82jNPyNtKl5LJG7T5gCD+QaIbrJ7Vzc90wJ2CVHOE9Yk+2lpEWMRdCBLRa38fp3/XCapXnt++ej71WOP3YjweB45RATM30vjoZvgw4w486OOqhoCcBlqtiZ47oKTZZ7I2VcFJA0pzx2sbArDlWZwmyA4C0d+kQLH2+rAcoId8R6CE/8gsMUp8xdjg5r0ZxETKwhlwWaMxICcowDniExFQkBo98VbpdE/5BfAUDj4fZLgs/WRGXZwYWRCtJfrL barrucadu@azathoth"
    ; };

  # Extra packages
  environment.systemPackages = with pkgs; [
    irssi
    perl
    (texlive.combine
      { inherit (texlive) scheme-medium; })
  ];
}
