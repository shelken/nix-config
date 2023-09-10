{
  username,
  useremail,
  ...
}: {
  # …

  programs.git = {
    enable = true;
    userName = username;
    userEmail = useremail;
    attributes = [
    ];
    extraConfig = {
      init.defaultBranch = "main";
    };
  };

  # …
}
