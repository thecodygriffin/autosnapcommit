# Description
A bash shell script that takes and maintains a set number of external virtual machine snapshots using virsh snapshot and blockcommit.

# Input Parameters
The script was written to require the 4 following input parameters so the same script can be used with multiple virtual machines:
1. virtual machine name / domain
2. root directory containing subdirectories for each virtual machine
3. the frequency of snapshots
4. the number of snapshots to retain

There are 6 options for the frequency of snapshots: secondly, minutely, hourly, daily, weekly, and monthly. These options do not schedule the script, but only define a timestamp variable that is used for naming the new snapshot files so that conflicts are avoided.

The following example command assumes these input parameter values:
1. the virtual machine name / domain is "debiantest"
2. the base image file is located at "/mnt/Home/VirtualMachines/debiantest"
3. the script will be triggered by a systemd service / timer to run "weekly"
4. the desire is to have 3 snapshots, plus the base image file, at all times, so 2 snapshots will be retained

`./autosnapcommit.sh "debiantest" "/mnt/Home/VirtualMachines" "weekly" 2`

# Features
- Validate the virtual machine name / domain and file location
- Recognize errors and provide an exit path
- Create a log file and log messages throughout the process
- Validate and, if necessary, create the logs and snapshots directories
- Determine the virtual machine state
- Start the virtual machine, if it was not running
- Disable the virtual machine's AppArmor profile so that a blockcommit can be performed
- Determine whether a blockcommit to shorten the backing chain needs to be performed, and if necessary, perform it
- Create a new snapshot
- Shut down the virtual machine, if the initial state was shut off
