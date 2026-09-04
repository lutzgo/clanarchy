# The theme registry — the *data* half of modules/themes.
#
# One entry per known-good theme. Adding a theme is a single entry here; a
# machine then selects it by name with `clanarchy.theme = "<key>";` in its
# machines/<name>/configuration.nix. Nothing else changes, and switching back
# to a theme that used to work is a one-word edit rather than an archaeology
# expedition through flake.nix imports.
#
# The key is what machines type, so it is also the enum the option validates
# against: a typo fails evaluation with the full list of valid names rather
# than silently falling through to a default.
#
# Fields
#   scheme    (required) base16/base24 scheme name, without the .yaml suffix,
#             as found in ${pkgs.base16-schemes}/share/themes/.
#             Browse them at https://tinted-theming.github.io/tinted-gallery/.
#   polarity  (required) "light" | "dark". Must match the scheme — this is not
#             a preference, it is a statement about base00. Stylix uses it to
#             pick app variants (GTK/Qt/Plymouth/regreet), modules/icon-theme.nix
#             reads it to choose the Papirus source variant, and
#             modules/desktop/noctalia-hm.nix feeds it to gsettings.
#   fontSizes (optional) overrides the shared default in ./default.nix, for a
#             scheme whose contrast wants a different size. Merged, not
#             replaced, so an entry may set just one key.
{
  selenized-black = {
    scheme = "selenized-black";
    polarity = "dark";
  };

  gruvbox-light-hard = {
    scheme = "gruvbox-light-hard";
    polarity = "light";
  };
}
