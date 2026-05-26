{ config, lib, pkgs, ... }:

let
  cfg     = config.clanarchy.consoleDesktop;
  cfgAerc = cfg.aerc;
in
{
  options.clanarchy.consoleDesktop = {
    enable     = (lib.mkEnableOption "console desktop tools (aerc, oama, w3m)") // { default = true; };
    aerc.enable = (lib.mkEnableOption "aerc TUI email client") // { default = true; };
  };

  config = lib.mkIf cfg.enable {

    home.packages = lib.mkIf cfgAerc.enable (with pkgs; [
      oama  # OAuth2 credential manager — used as aerc passwordCommand
      w3m   # HTML mail rendering (register as aerc [[ html ]] open handler)
    ]);

    # ~/.config/aerc is covered by the ".config" persist directory in
    # modules/users/lgo.nix — no extra impermanence entry needed.
    programs.aerc = lib.mkIf cfgAerc.enable {
      enable = true;

      extraConfig = {
        # HM writes accounts.conf to the Nix store (0444); aerc rejects
        # world-readable credentials unless this flag is set.  Safe when
        # credentials are supplied via passwordCommand (not inline).
        general.unsafe-accounts-conf = true;

        compose.editor = "nvim";
      };

      # Vim-style bindings (aerc ships these by default; explicit here to
      # confirm them and align j/k/g/G with lgo's helix/nvim muscle memory).
      extraBinds = {
        messages = {
          j         = ":next<Enter>";
          k         = ":prev<Enter>";
          g         = ":select 0<Enter>";
          G         = ":select -1<Enter>";
          "<Enter>" = ":view<Enter>";
          C         = ":compose<Enter>";
          r         = ":reply<Enter>";
          R         = ":reply -a<Enter>";
          D         = ":delete<Enter>";
          "/"       = ":search<space>";
          n         = ":next-result<Enter>";
          N         = ":prev-result<Enter>";
          q         = ":quit<Enter>";
        };
        view = {
          q = ":close<Enter>";
          r = ":reply<Enter>";
          R = ":reply -a<Enter>";
          f = ":forward<Enter>";
          D = ":delete<Enter>";
          H = ":toggle-headers<Enter>";
        };
      };
    };

    # TODO: Add email accounts here — see accounts.email.accounts.<name>.aerc.*
    # in the Home Manager option docs.  For Gmail OAuth2 via oama:
    #
    #   accounts.email.accounts.gmail = {
    #     primary  = true;
    #     address  = "user@gmail.com";
    #     realName = "Lutz Go";
    #     imap     = { host = "imap.gmail.com"; port = 993; tls.enable = true; };
    #     smtp     = { host = "smtp.gmail.com"; port = 465; tls.enable = true; };
    #     aerc = {
    #       enable  = true;
    #       extraAccounts = {
    #         source   = "imaps://user@gmail.com@imap.gmail.com:993/";
    #         outgoing = "smtps+oauthbearer://user@gmail.com@smtp.gmail.com:465";
    #       };
    #       passwordCommand = "oama access user@gmail.com";
    #     };
    #   };
    #
    # First-time OAuth2 setup: register a Google Cloud project, obtain
    # client-id and client-secret, then run:
    #   oama setup --client-id <id> --client-secret <secret> user@gmail.com
    # and follow the browser prompt to authorise IMAP/SMTP access.
  };
}
