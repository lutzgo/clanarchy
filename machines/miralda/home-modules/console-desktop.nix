{ config, lib, pkgs, osConfig, ... }:

let
  cfg     = config.clanarchy.consoleDesktop;
  cfgAerc = cfg.aerc;

  # M31.  lutz@goclan.org's password, staged by sops on THIS machine because
  # modules/users/lgo.nix imports modules/mail-accounts.nix — a clan var only
  # reaches machines whose configuration declares its generator.
  #
  # Reached through `osConfig` rather than re-derived, the same way
  # desktop/niri-hm.nix and desktop/labwc-hm.nix reach system options: the
  # path is a property of the deployment, not of the home.
  mailPasswordFile =
    osConfig.clan.core.vars.generators.mail-accounts.files."lutz.plain".path;
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

    # ── The household's own mailbox (M31) ────────────────────────────────
    #
    #   This replaces the commented-out Gmail-over-oama sketch that sat here
    #   from the day aerc was added and was never filled in.  oama and w3m
    #   stay in home.packages above — w3m because aerc still needs an HTML
    #   renderer, oama because a Gmail account may yet be added beside this
    #   one and removing a package to re-add it later is churn.
    #
    #   THE SERVER IS machines/ernst/containers/mail.nix.  Read that file's
    #   header before trusting outgoing mail: ernst sends from a residential
    #   Vodafone address whose PTR cannot be changed, so delivery to Outlook
    #   and the big German providers is a known problem with a documented fix
    #   path in docs/guides/mail.md.  Nothing about that is visible from here
    #   — aerc will report a cheerful 250 either way.
    accounts.email.accounts.goclan = lib.mkIf cfgAerc.enable {
      primary  = true;
      address  = "lutz@goclan.org";
      userName = "lutz@goclan.org";
      realName = "Lutz Go";

      # Implicit TLS on both, which is what the server offers: 993 for IMAP
      # and 465 for submission.  143 and 587 are switched OFF on ernst per
      # RFC 8314, so there is no STARTTLS port to fall back to and that is
      # deliberate — see the port note in containers/mail.nix.
      imap = { host = "mail.goclan.org"; port = 993; tls.enable = true; };
      smtp = { host = "mail.goclan.org"; port = 465; tls.enable = true; };

      # `cat` on a 0400 file owned by lgo.  aerc re-runs this on every start,
      # so rotating the clan var needs no daemon restart — only a restart of
      # aerc itself.
      #
      # THE FILE IS READABLE HERE BECAUSE modules/users/lgo.nix DECLARES THE
      # GENERATOR, not merely because ernst has it.  A clan var is deployed
      # to the machines that declare it; dropping that import would leave
      # this path pointing at nothing and aerc prompting on every start.
      passwordCommand = "${pkgs.coreutils}/bin/cat ${mailPasswordFile}";

      aerc = {
        enable = true;
        # The username is percent-encoded because it IS an email address and
        # the `@` would otherwise terminate the userinfo component early,
        # leaving aerc trying to reach a host called `goclan.org@mail...`.
        extraAccounts = {
          source   = "imaps://lutz%40goclan.org@mail.goclan.org:993";
          outgoing = "smtps://lutz%40goclan.org@mail.goclan.org:465";
        };
      };
    };
  };
}
