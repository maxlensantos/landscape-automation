#!/usr/bin/env python3
import subprocess
import json
import sys

# ANSI color codes
COLOR_GREEN = "\033[92m"
COLOR_RED = "\033[91m"
COLOR_YELLOW = "\033[93m"
COLOR_END = "\033[0m"

def print_status(message, success):
    """Prints a status message with appropriate color."""
    color = COLOR_GREEN if success else COLOR_RED
    status_text = "PASS" if success else "FAIL"
    print(f"[{color}{status_text}{COLOR_END}] {message}")

def run_command(command):
    """Runs a shell command and returns its output and exit code."""
    try:
        result = subprocess.run(
            command,
            shell=True,
            capture_output=True,
            text=True,
            check=False,
            timeout=60
        )
        return result.stdout.strip(), result.stderr.strip(), result.returncode
    except subprocess.TimeoutExpired:
        return "", "Command timed out", 1

def check_tool_installed(tool):
    """Checks if a command-line tool is installed."""
    stdout, stderr, code = run_command(f"command -v {tool}")
    success = code == 0
    print_status(f"Tool '{tool}' is installed.", success)
    if not success:
        print(f"  └─> Error: '{tool}' not found in PATH. Please install it.")
    return success

def check_juju_version():
    """Checks if Juju version is 3.0 or higher."""
    stdout, stderr, code = run_command("juju version")
    if code != 0:
        print_status("Could not determine Juju version.", False)
        return False
    
    version_str = stdout.split('-')[0] # e.g., "3.6.0-ubuntu-amd64" -> "3.6.0"
    major_version = int(version_str.split('.')[0])
    
    success = major_version >= 3
    print_status(f"Juju version is {version_str} (>= 3.x).", success)
    if not success:
        print(f"  └─> Error: Juju version is too old. Please upgrade to 3.x or newer.")
    return success

def check_juju_login():
    """Checks if we are logged into a Juju controller."""
    stdout, stderr, code = run_command("juju whoami")
    success = code == 0 and "Not logged in" not in stderr
    print_status("Logged into a Juju controller.", success)
    if not success:
        print(f"  └─> {COLOR_YELLOW}WARN: Not logged into a Juju controller. Some checks will be skipped.{COLOR_END}")
    return success

def main():
    """Runs all pre-flight checks."""
    print("--- Running Pre-flight Deployment Validation Script ---")
    all_checks_passed = True
    
    # --- Tooling Checks ---
    if not check_tool_installed("ansible"): all_checks_passed = False
    if not check_tool_installed("juju"): all_checks_passed = False
    if not check_tool_installed("lxd"): all_checks_passed = False
    
    # --- Juju Specific Checks ---
    if 'juju' in sys.argv or all_checks_passed:
        if not check_juju_version(): all_checks_passed = False
        check_juju_login() # This is a warning, not a failure

    # --- Final Summary ---
    print("--- Validation Summary ---")
    if all_checks_passed:
        print(f"{COLOR_GREEN}All essential pre-flight checks passed.{COLOR_END}")
        print("You can proceed with the Ansible deployment.")
        sys.exit(0)
    else:
        print(f"{COLOR_RED}One or more critical pre-flight checks failed.{COLOR_END}")
        print("Please review the errors above before proceeding.")
        sys.exit(1)

if __name__ == "__main__":
    main()
