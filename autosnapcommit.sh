#!/bin/bash

vm_name="${1}"
vm_dir="${2}${vm_name}/"
vm_file="${vm_name}.qcow2"
vm_disk=( $(virsh domblklist "${vm_name}" | grep "${vm_dir}") )
vm_state_initial="$(virsh domstate ${vm_name})"

snapshot_dir="${vm_dir}snapshots/"
new_snapshot_name="${vm_name}$(date +%Y%m%d%H%M%S)"
new_snapshot_file="${new_snapshot_name}.qcow2"
existing_snapshot_files=( $(echo "${snapshot_dir}${vm_name}*.qcow2") )
existing_snapshot_count=$(echo ${#existing_snapshot_files[@]})

snapshots_to_retain=3

log_dir="${vm_dir}logs/"
log_file="${new_snapshot_name}.txt"

function logger() {
  local message="${1}"
  if [ -d "${log_dir}" ]; then
    echo "$(date +%H%M%S) - ${message}" >> "${log_dir}/${log_file}"
  else
    echo "$(date +%H%M%S) - ${message}" >> "${vm_dir}/${log_file}"
  fi
}

function exit_code_handler() {
  local exit_code=${1}
  local success_message="${2}"
  local fail_message="${3}"
  if [ ${exit_code} -eq 0 ]; then
    logger "${success_message}"
  else
    logger "${fail_message}"
    exit 1
  fi
}

function create_directory() {
  local dir_name="${1}"
  if [ ! -d "${dir_name}" ]; then
    mkdir "${dir_name}"
    local exit_code=$?
    exit_code_handler \
      ${exit_code} \
      "The ${dir_name} directory was created." \
      "The ${dir_name} directory could not be created."
  else
    logger "The ${dir_name} directory exists."
  fi
}

function start_vm() {
  virsh start "${vm_name}"
  local exit_code=$?
  exit_code_handler \
    ${exit_code} \
    "The ${vm_name} virtual machine was started." \
    "The ${vm_name} virtual machine could not be started."
}

function evaluate_vm_state() {
  local vm_state="${1}"
  case "${vm_state}" in
    "shut off")
      logger "The ${vm_name} virtual machine is shut off."      
      start_vm
      sleep 10 # change to 60 after development
      evaluate_vm_state "$(virsh domstate ${vm_name})"
      ;;
    "running")
      logger "The ${vm_name} virtual machine is running."
      ;;
    *)
      logger "Aborted the process due to an unexpected ${vm_name} virtual machine state."
      exit 1
      ;;
  esac
}

function create_snapshot() {
  virsh snapshot-create-as \
    --domain "${vm_name}" "${new_snapshot_name}" \
    --diskspec "${vm_disk[0]}",file="${snapshot_dir}${new_snapshot_file}",snapshot=external \
    --disk-only \
    --atomic \
    --no-metadata
  local exit_code=$?
  exit_code_handler \
    ${exit_code} \
    "The ${new_snapshot_name} snapshot was created." \
    "The ${new_snapshot_name} snapshot could not be created."
}

create_directory "${log_dir}"

evaluate_vm_state "${vm_state_initial}"

create_directory "${snapshot_dir}"

# temporarily disable AppArmor for the virtual machine

create_snapshot

# reenable AppArmor for the virtual machine

# shutdown virtual machine based on initial vm state
