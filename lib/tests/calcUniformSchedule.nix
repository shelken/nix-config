{
  lib,
  mylib,
}:

let
  fixedHostnames = [
    "ling"
    "mio"
    "nano"
    "pve155"
    "pve156"
    "sakamoto"
    "vm"
    "yuuko"
  ];

  sortedHostnames =
    let
      hostnameHashes = map (h: {
        name = h;
        hash = builtins.hashString "sha1" h;
      }) fixedHostnames;
      sortedByHash = lib.sort (a: b: a.hash < b.hash) hostnameHashes;
    in
    map (x: x.name) sortedByHash;

  calculateExpected =
    hostname: startHour: endHour:
    let
      hostnameIndex = lib.lists.findFirstIndex (x: x == hostname) null sortedHostnames;
      totalHours = endHour - startHour;
      baseHour =
        if hostnameIndex != null then startHour + lib.mod hostnameIndex totalHours else startHour;
      baseMinute = lib.mod (builtins.stringLength hostname * 13) 60;
    in
    {
      hour = baseHour;
      minute = baseMinute;
    };

  testCases = [
    {
      name = "mio";
      hostname = "mio";
      startHour = 2;
      endHour = 8;
      hostnames = fixedHostnames;
    }
    {
      name = "sakamoto";
      hostname = "sakamoto";
      startHour = 2;
      endHour = 8;
      hostnames = fixedHostnames;
    }
    {
      name = "none";
      hostname = "";
      startHour = 2;
      endHour = 8;
      hostnames = fixedHostnames;
    }
    {
      name = "unknown";
      hostname = "shit";
      startHour = 2;
      endHour = 8;
      hostnames = fixedHostnames;
    }
  ];

  runTest =
    testCase:
    let
      result = mylib.calcUniformSchedule {
        hostname = testCase.hostname;
        startHour = testCase.startHour;
        endHour = testCase.endHour;
        hostnames = testCase.hostnames;
      };

      expected = calculateExpected testCase.hostname testCase.startHour testCase.endHour;
      hourMatch = result.hour == expected.hour;
      minuteMatch = result.minute == expected.minute;
      valid = hourMatch && minuteMatch;
    in
    {
      name = testCase.name;
      input = {
        hostname = testCase.hostname;
        startHour = testCase.startHour;
        endHour = testCase.endHour;
        hostnames = testCase.hostnames;
      };
      expected = expected;
      actual = result;
      valid = valid;
      details = {
        hourMatch = hourMatch;
        minuteMatch = minuteMatch;
      };
    };

  testResults = map runTest testCases;
  allPassed = builtins.all (test: test.valid) testResults;

  testsByName = builtins.listToAttrs (
    map (test: {
      name = test.name;
      value = {
        expected = test.expected;
        actual = test.actual;
        valid = test.valid;
      };
    }) testResults
  );

in
{
  tests = testsByName;
  allPassed = allPassed;
  summary = if allPassed then "✅ All tests passed!" else "❌ Some tests failed";

  debug = {
    fixedHostnames = fixedHostnames;
    sortedHostnames = sortedHostnames;
  };
}
