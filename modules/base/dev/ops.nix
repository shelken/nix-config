{
  mylib,
  ...
}:
{
  options.shelken.dev.ops = {
    enable = mylib.mkBoolOpt false "Whether or not use to enable.";
  };
}
