{ config, pkgs, ... }:

{
  imports = [ ../../services/nginx-phpfpm.nix ];

  networking.firewall.enable = false;

  services.nginx.enable = true;
  services.nginx.virtualHosts = {
    "mawalker.me.uk".globalRedirect = "www.mawalker.me.uk";

    "www.mawalker.me.uk" = {
      root = "/srv/http/www";
      locations."~ \.php$".extraConfig = ''
        include ${pkgs.nginx}/conf/fastcgi_params;
        fastcgi_pass  unix:/run/phpfpm/phpfpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root/$fastcgi_script_name;
      '';
      extraConfig = ''
        index index.php;
        access_log /dev/null;
        error_log  /var/spool/nginx/logs/www.error.log;
      '';
    };
  };

  services.logrotate.enable = true;
  services.logrotate.config = ''
/var/spool/nginx/logs/www.error.log {
    weekly
    copytruncate
    rotate 1
    compress
    postrotate
        systemctl kill nginx.service --signal=USR1
    endscript
}
  '';
}
