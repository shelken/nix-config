{
  mylib,
  ...
}:
{
  options.shelken.dev.ide = {
    enable = mylib.mkBoolOpt false "Whether or not use to enable.";
  };
}
