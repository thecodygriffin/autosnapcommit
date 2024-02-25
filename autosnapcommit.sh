#!/bin/bash
#
# Performs the snapshot creation and blockcommit maintenance of virtual
# machines.

# Set constant variables for script.
VM_NAME="${1}"
VM_DIR="${2}/${VM_NAME}"
VM_FILE="${VM_DIR}/${VM_NAME}.qcow2"

SNAPSHOT_DIR="${VM_DIR}/snapshots"
SNAPSHOT_FREQ=${3}
SNAPSHOTS_TO_RETAIN=${4}

LOG_DIR="${VM_DIR}/logs"
LOG_FILE="${LOG_DIR}/${VM_NAME}$(date +%Y%m%d%H%M%S).txt"

# Ensures that the virtual machine and its file exist.
function validate_vm() {
  local vm_name_regex="\<${1}\>"
  local existing_vm=( $(virsh list --name --all) )
  if [[ ${existing_vm[@]} =~ ${vm_name_regex} && -f "${VM_FILE}" ]]; then
    logger "The ${VM_NAME} virtual machine and its ${VM_FILE} exist."
  else
    error_handler "The ${VM_NAME} virtual machine and/or its ${VM_FILE} do not exist."
  fi
}

# Aborts the process after sending message to log file.
function error_handler() {
  logger "${1}"
  logger "The process was aborted."
  exit 1
}

# Writes a message to log file.
function logger() {
  if [[ -d "${LOG_DIR}" ]]; then
    echo "$(date +%H%M%S) - ${1}" >> "${LOG_FILE}"
  else
    echo "${1}"
  fi
}

# Ensures that the directory exists.
function validate_dir () {
  if [[ -d "${1}" ]]; then
    logger "The ${1} directory exists."
  else
   create_dir "${1}"
  fi
}

# Creates a directory when it does not exist.
function create_dir() {
  mkdir "${1}"
  if [[ $? -ne 0 ]]; then
    error_handler "The ${1} directory could not be created"
  fi
  logger "The ${1} dir was created."
}

# Evalutes if virtual machine is in an expected state.
function determine_vm_state() {
  vm_state_current="$(virsh domstate ${VM_NAME})"
  case "${vm_state_current}" in
    "shut off" | "running")
      logger "The ${VM_NAME} virtual machine is in the ${vm_state_current} state."
      ;;
    *)
      error_handler "The ${VM_NAME} virtual machine is in an unexpected ${vm_state_current} state."
      ;;
  esac
}

# Starts the virtual machine.
function start_vm() {
  virsh start "${VM_NAME}"
  if [[ $? -ne 0 ]]; then
    error_handler "The ${VM_NAME} virtual machine could not be started."
  fi
  logger "The ${VM_NAME} virtual machine was started."
  sleep 90
}

# Ensures the virtual machine AppArmor Profile is disabled before creating
# a snapshot and performing a blockcommit.
function disable_apparmor() {
  aa-disable "/etc/apparmor.d/libvirt/libvirt-$(virsh domuuid $VM_NAME)"
  if [[ $? -eq 0 ]]; then
    logger "The ${VM_NAME} virtual machine AppArmor Profile is disabled."
  else
    logger  "The ${VM_NAME} virtual machine AppArmor Profile was already disabled."
  fi
}

# Determine whether a blockcommit is necessary.
function determine_blockcommit() {
  local vm_disk=( $(virsh domblklist "${VM_NAME}" | grep "${VM_DIR}") )
  qemu-img info --force-share --backing-chain "${vm_disk[1]}"
  local backing_chain=( $(sudo qemu-img info \
    --force-share --backing-chain "${vm_disk[1]}" | \
    grep image | cut -d: -f2- | tr -d " " | tac) )
  local existing_snapshot_files=$((${#backing_chain[@]} - 1))
  logger "There were ${existing_snapshot_files} snapshots in the backing chain."
  logger "The number of snapshots to retain in the backing chain are ${SNAPSHOTS_TO_RETAIN}."
  if [[ ${existing_snapshot_files} -gt ${SNAPSHOTS_TO_RETAIN} ]]; then
    perform_blockcommit \
      "${vm_disk[0]}" \
      "${backing_chain[${existing_snapshot_files}-${SNAPSHOTS_TO_RETAIN}]}"
  else
    logger "The backing chain did not need to be reduced."
  fi
}

# Performs a blockcommit to reduce the backing chain.
function perform_blockcommit() {
  virsh blockcommit \
    --domain "${VM_NAME}" \
    --path "${1}" \
    --base "${VM_FILE}" \
    --top "${2}" \
    --delete \
    --verbose \
    --wait
  if [[ $? -eq 0 ]]; then
    logger "The blockcommit was successful."
    logger "The ${2} file was merged into the ${VM_FILE} base file."
    logger "The backing chain was reduced."
  else
    logger "The blockcommit failed."
    logger "The ${2} file was not merged into the ${VM_FILE} base file."
    logger "The backing chain was not reduced."
  fi
  sleep 10
}

# Creates the external, disk-only snapshot without metadata.
function create_snapshot() {
  case "${SNAPSHOT_FREQ}" in
    "secondly")
      timestamp="$(date +%Y%m%d%H%M%S)"
      ;;
    "minutely")
      timestamp="$(date +%Y%m%d%H%M)"
      ;;
    "hourly")
      timestamp="$(date +%Y%m%d%H)"
      ;;
    "daily" | "weekly")
      timestamp="$(date +%Y%m%d)"
      ;;
    "monthly")
      timestamp="$(date +%Y%m)"
      ;;
  esac
  local new_snapshot_name="${VM_NAME}${timestamp}"
  local new_snapshot_file="${SNAPSHOT_DIR}/${new_snapshot_name}.qcow2"
  local vm_disk=( $(virsh domblklist "${VM_NAME}" | grep "${VM_DIR}") )
  virsh snapshot-create-as \
    --domain "${VM_NAME}" \
    --name "${new_snapshot_name}" \
    --diskspec "${vm_disk[0]}",file="${new_snapshot_file}",snapshot=external \
    --disk-only \
    --atomic \
    --no-metadata
  if [[ $? -eq 0 ]]; then
    logger "The ${new_snapshot_name} snapshot was created."
  else
    logger "The ${new_snapshot_name} snapshot could not be created."
  fi
  sleep 10
}

# Shutdown the virtual machine.
function shutdown_vm() {
  virsh shutdown "${VM_NAME}"
  if [[ $? -ne 0 ]]; then
    error_handler "The ${VM_NAME} virtual machine could not be shutdown."
  fi
  logger "The ${VM_NAME} virtual machine was shutdown."
  sleep 90
}

# Call function to validate that the virtual machine parameters provided.
validate_vm "${VM_NAME}"

# Call function to validate logs directory exists and create it if it does not.
validate_dir "${LOG_DIR}"

# Call function to validate snapshots directory exists and create it if it
# does not.
validate_dir "${SNAPSHOT_DIR}"

# Call function to validate that the virtual machine is in an expected state.
determine_vm_state

# Store the intial virtual machine state for later reference.
readonly vm_state_initial="${vm_state_current}"

# Start the vitual machine if it was shut off.
if [[ "${vm_state_current}" == "shut off" ]]; then
  start_vm
  determine_vm_state
fi

# Call function to disable the virtual machine AppArmor Profile.
disable_apparmor
# TODO(codygriffin): Figure out AppArmor / libvirt issue and then remove.

# Call function to determine if a blockcommit is necessary and perform if so.
determine_blockcommit

# Call function to create the snapshot.
create_snapshot

# Call function to validate that the virtual machine is in an expected state
# after the blockcommit and snapshot have been completed.
determine_vm_state

# Shutdown the virtual machine if the initial state was shut off and
# send the final virtual machine state to the log once done.
if [[ "${vm_state_initial}" == "shut off" ]]; then
  shutdown_vm
  determine_vm_state
fi
