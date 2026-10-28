# PROTOTYPE：整个 sandbox 的共享声明。只有这里读取 Home Manager config。
{
  profile,
  stateRoot ? "/tmp/sbp-${profile.home.username}",
}:
{
  paths = {
    root = stateRoot;
    vm = "${stateRoot}/msb";
    cache = "${stateRoot}/cache";
    published = "${stateRoot}/config";
    mise = "${stateRoot}/mise";
    approvals = "${stateRoot}/approvals";
  };

  policy = ../sb.yaml;
  gitUser = profile.programs.git.settings.user;
  microsandboxVersion = profile.programs.mise.globalConfig.tools.microsandbox;

  tools = profile.shelken.dev.tools;
  miseTools = profile.shelken.dev.miseTools;
  writableRoots = profile.shelken.dev.sandbox.writableRoots;
  hostCommands = profile.shelken.dev.sandbox.hostCommands;
}
