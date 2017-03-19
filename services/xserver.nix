{ pkgs, ... }:

{
  services.xserver.enable = true;

  # Set the default x session to herbstluftwm
  services.xserver.windowManager.herbstluftwm.enable = true;

  # Enable C-M-Bksp to kill X
  services.xserver.enableCtrlAltBackspace = true;

  # Use lightdm instead of slim
  services.xserver.displayManager.lightdm.enable = true;
  environment.systemPackages = [ pkgs.lightdm ];

  # Enable redshift
  services.redshift = {
    enable = true;
    # York
    latitude  = "53.953";
    longitude = "-1.0391";
  };

  # Sane font defaults
  fonts = {
    enableFontDir = true;
    enableGhostscriptFonts = true;
    fontconfig.cache32Bit = true;
    fontconfig.ultimate.preset = "osx";

    fonts = with pkgs; [
      terminus_font
      source-code-pro
    ];
  };
}
