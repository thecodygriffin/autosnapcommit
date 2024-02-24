#!/bin/bash
#
# Performs the snapshot creation and blockcommit maintenance of virtual
# machines.
set -x
# Set constant variables for script.
VM_NAME="${1}"
VM_DIR="${2}${VM_NAME}"
VM_FILE="${VM_DIR}/${VM_NAME}.qcow2"

SNAPSHOT_DIR="${VM_DIR}/snapshots"
SNAPSHOTS_TO_RETAIN=${3}

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

# Determines whether or not to abort based command outcome.
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
  if [[ "${vm_state_current}" == "shut off" || \
  "${vm_state_current}" == "running" ]]; then
    logger "The ${VM_NAME} virtual machine is in the ${vm_state_current} state."
  else
    error_handler "The ${VM_NAME} virtual machine is in an unexpected ${vm_state_current} state."
  fi
}

# Starts the virtual machines.
function start_vm() {
  virsh start "${VM_NAME}"
  if [[ $? -ne 0 ]]; then
    error_handler "The ${VM_NAME} virtual machine could not be started."
  fi
  logger "The ${VM_NAME} virtual machine was started."
  sleep 10 # TODO(codygriffin): Change to 60 after development
}

# Ensures the virtual machine AppArmor Profile is disabled before creating \
# a snapshot and performing a blockcommit.
function disable_apparmor() {
  aa-disable "/etc/apparmor.d/libvirt/libvirt-$(virsh domuuid $VM_NAME)"
  if [[ $? -ne 0 ]]; then
    logger  "The ${VM_NAME} virtual machine AppArmor Profile was already disabled."
  else
    logger "The ${VM_NAME} virtual machine AppArmor Profile is disabled."
  fi
}

# Performs a blockcommit to reduce backing chain.
function perform_blockcommit() {
  local vm_disk=( $(virsh domblklist "${VM_NAME}" | grep "${VM_DIR}") )
  qemu-img info --force-share --backing-chain "${vm_disk[1]}"
  # TODO(codygriffin): Determine existing snapshots from backing chain instead of directory.
  existing_snapshot_files=( $(echo "${SNAPSHOT_DIR}/*") )
  logger "There are ${#existing_snapshot_files[@]} snapshots in the backing chain."
  logger "The number of snapshots to retain the backing chain is ${SNAPSHOTS_TO_RETAIN}".
  if [[ ${#existing_snapshot_files[@]} -gt ${SNAPSHOTS_TO_RETAIN} ]]; then
    virsh blockcommit \
      --domain "${VM_NAME}" \
      --path "${vm_disk[0]}" \
      --base "${VM_FILE}" \
      --top "${existing_snapshot_files[0]}" \
      --delete \
      --verbose \
      --wait
  fi
  if [[ $? -ne 0 ]]; then
    logger "The number of existing snapshots were less than or equal to the number to retain."
    logger "The backing chain was not reduced." # TODO(codygriffin): Better message
  else
    logger "The number of existing snapshots were greater than the number to retain."
    logger "The backing chain was reduced." # TODO(codygriffin): Better message
  fi
}

# Creates the external, disk-only snapshot without metadata.
function create_snapshot() {
  local vm_disk=( $(virsh domblklist "${VM_NAME}" | grep "${VM_DIR}") )
  local new_snapshot_name="${VM_NAME}$(date +%Y%m%d%H%M%S)"
  local new_snapshot_file="${SNAPSHOT_DIR}/${new_snapshot_name}.qcow2"
  virsh snapshot-create-as \
    --domain "${VM_NAME}" \
    --name "${new_snapshot_name}" \
    --diskspec "${vm_disk[0]}",file="${new_snapshot_file}",snapshot=external \
    --disk-only \
    --atomic \
    --no-metadata
  if [[ $? -ne 0 ]]; then
    logger "The ${new_snapshot_name} snapshot could not be created."
  else
    logger "The ${new_snapshot_name} snapshot was created."
  fi
}


# Call function to validate that the provided virtual machine parameters are
# valid.
validate_vm "${VM_NAME}"

# Call function to validate logs directory exists and creat it if it does not.
validate_dir "${LOG_DIR}"

# Call function to validate snapshot directory exists and create it if i
# does not.
validate_dir "${SNAPSHOT_DIR}"

# Determine the current state of the vitual machine.
readonly vm_state_initial="$(virsh domstate ${VM_NAME})"
logger "The initial state of the ${VM_NAME} virtual machine is ${vm_state_initial}."

# Call function to validate that the virtual machine is in an expected state.
determine_vm_state

# Start the vitual machine if it is not running.
if [[ "${vm_state_current}" == "shut off" ]]; then
  start_vm
fi

# Call function to disable the virtual machine AppArmor Profile.
disable_apparmor

# Call function to perform a blockcommit.
perform_blockcommit

# Call function to create the snapshot.
create_snapshot

# TODO(codygriffin): Shutdown virtual machine based on initial vm state
