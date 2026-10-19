"""Sample program that gets packaged into hello.exe by build.bat."""
import platform
import sys

VERSION = "__VERSION__"  # replaced by build.bat with the commit/pipeline


def main():
    print(f"Hello from helloooooo.exe, build {VERSION}")
    print(f"Python {platform.python_version()} on {platform.system()} {platform.release()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
