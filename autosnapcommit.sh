#!/bin/bash

# variables for virtual machine file and location
vm_name="${1}"
vm_dir="${2}${vm_name}/"
vm_file="${vm_name}.qcow2"
vm_disk=( $(virsh domblklist "${vm_name}" | grep "${vm_dir}") )

# variables for snapshot files and location
snapshot_dir="${vm_dir}snapshots/"
new_snapshot_name="${vm_name}$(date +%Y%m%d%H%M%S)"
new_snapshot_file="${new_snapshot_name}.qcow2"
existing_snapshot_files=( $(echo "${snapshot_dir}${vm_name}*.qcow2") )
existing_snapshot_count=$(echo ${#existing_snapshot_files[@]})

# the minimum number of snapshots to retain
snapshots_to_retain=3

# variables for log files and location
log_dir="${vm_dir}logs/"
log_file="${new_snapshot_name}.txt"

# writes to log file
function write_to_log() {
  local message="${1}"
  if [ -d "${log_dir}" ]; then
    echo "$(date +%H%M%S) - ${message}" >> "${log_dir}/${log_file}"
  else
    echo "$(date +%H%M%S) - ${message}" >> "${vm_dir}/${log_file}"
  fi
}

# evaluates the exit code of the prevous command and exit script upon failure
function evaluate_outcome() {
  if [ $? -eq 0 ]; then
    write_to_log "${1}"
  else
    write_to_log "${2}"
    exit 1
  fi
}

# creates a directory if it does not already exist
function create_directory() {
  local dir_name="${1}"
  if [ ! -d "${dir_name}" ]; then
    mkdir "${dir_name}"
    evaluate_outcome \
      "The ${dir_name} directory was created." \
      "The ${dir_name} directory could not be created."
  else
    write_to_log "The ${dir_name} directory exists."
  fi
}

# starts the virtual machine
function start_vm() {
  virsh start "${vm_name}"
  evaluate_outcome \
    "The ${vm_name} virtual machine was started." \
    "The ${vm_name} virtual machine could not be started."
}

# evaluates the virtual machine state
function evaluate_vm_state() {
  vm_state="$(virsh domstate ${vm_name})"
  write_to_log "The ${vm_name} virtual machine state is: ${vm_state}."
  case "${vm_state}" in
    "shut off")
      start_vm
      sleep 10 # change to 60 after development
      evaluate_vm_state
      ;;
    "running")
      write_to_log "The ${vm_name} virtual machine is ready..."
      ;;
    *)
      write_to_log "Aborted the process due to unexpected ${vm_name} virtual machine state."
      exit 1
      ;;
  esac
}

# ensure the logs directory exists
create_directory "${log_dir}"

# ensure the virtual machine is ready
evaluate_vm_state

# temporarily disable AppArmor for the virtual machine

# ensure the snapshots directory exists
create_directory "${snapshot_dir}"

# create the new snapshot
virsh snapshot-create-as \
  --domain "${vm_name}" "${new_snapshot_name}" \
  --diskspec "${vm_disk[0]}",file="${snapshot_dir}${new_snapshot_file}",snapshot=external \
  --disk-only \
  --atomic \
  --no-metadata
evaluate_outcome \
  "The ${new_snapshot_name} snapshot was created." \
  "The ${new_snapshot_name} snapshot could not be created."
