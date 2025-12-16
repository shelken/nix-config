{
  mylib,
  ...
}:
{
  options.shelken.dev.ai = {
    enable = mylib.mkBoolOpt false "Whether or not to enable.";
  };
  imports = (mylib.scanPaths ./.);
}
