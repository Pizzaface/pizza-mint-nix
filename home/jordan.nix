{ config, pkgs, ... }:
{
  home.username = "jordan";
  home.homeDirectory = "/home/jordan";
  home.stateVersion = "25.05";

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    initExtra = ''
      eval "$(direnv hook zsh)"
    '';
  };

  programs.git = {
    enable = true;
    userName = "Jordan Pizza";
    userEmail = "10016234+Pizzaface@users.noreply.github.com";
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = false;
    };
  };

  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "ssh"; # or "https" if you prefer
    };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  home.packages = with pkgs; [
    # Search & utilities
    ripgrep
    direnv
    btop
    p7zip
    imagemagick

    # Media
    ffmpeg

    # Languages & runtimes
    go
    nodejs
    python311

    # Dev tools
    mise
    temporal-cli
    git-lfs

    # Cloud & networking
    awscli2
    cloudflared
    nmap

    # Core CLI
    git
    curl
    jq
  ];

  xdg.enable = true;
}
