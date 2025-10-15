#!/usr/bin/python3
import json, sys

def is_cluster_healthy(status_json):
    try:
        status = json.loads(status_json)
        apps = status.get("applications", {})
        if not apps:
            return False # Not healthy if there are no applications

        total_units_found = 0
        for app_data in apps.values():
            if not app_data.get("units"):
                continue # Skip apps with no unit section

            for unit_data in app_data["units"].values():
                total_units_found += 1
                workload_status = unit_data.get("workload-status", {}).get("current")
                agent_status = unit_data.get("juju-status", {}).get("current")

                if not (workload_status == "active" and agent_status == "idle"):
                    return False # Found a unit that is not ready
        
        # Healthy only if we found at least one unit and all were healthy
        return total_units_found > 0

    except (json.JSONDecodeError, KeyError):
        return False

if __name__ == "__main__":
    stdin_content = sys.stdin.read()
    if is_cluster_healthy(stdin_content):
        sys.exit(0) # Success
    else:
        sys.exit(1) # Failure