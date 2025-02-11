# analyze_sarif
This tool converts the output of `dart analyze --format=json` to [SARIF](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html).

```
Usage: analyze_sarif <flags>
Converts the output of "dart analyze --format=json" to SARIF.
-h, --help       Print this usage information.
-V, --version    Print the tool version.
-s, --srcroot    Use this directory as the SRCROOT. All paths in the report will be relative to this directory.
-i, --input      Read the dart analyzer JSON output from this file. If not given, it is read from stdin.
-o, --output     Write the SARIF report to this file. If not given, the report is written to stdout.
```
