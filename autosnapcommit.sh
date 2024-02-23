#!/bin/bash
#
# Performs the snapshot creation and blockcommit maintenance of virtual
# machines.
set -x
# Set constant variables for script.
VM_NAME="${1}"
VM_DIR="${2}${VM_NAME}/"
VM_FILE="${VM_DIR}${VM_NAME}.qcow2"
VM_STATE_INITIAL="$(virsh domstate ${VM_NAME})"

SNAPSHOT_DIR="${VM_DIR}snapshots/"
SNAPSHOTS_TO_RETAIN=${3}

LOG_DIR="${VM_DIR}logs/"
LOG_FILE="${VM_NAME}$(date +%Y%m%d%H%M%S).txt"

# Ensures that the virtual machine and its file exist.
function validate_vm() {
  local vm_name_regex="\<${1}\>"
  local existing_vm=( $(virsh list --name --all) )
  if [[ ${existing_vm[@]} =~ ${vm_name_regex} && -f "${VM_FILE}" ]]; then
    local result_code=0
  else
    local result_code=1
  fi
  result_handler \
    ${result_code} \
    "The ${VM_NAME} virtual machine and its ${VM_FILE} exist." \
    "The ${VM_NAME} virtual machine and/or its ${VM_FILE} do not exist."
}

# Evaluates an exit code and sends corresponding message to be written to the
# log file.
function result_handler() {
  local result_code=${1}
  local success_message="${2}"
  local fail_message="${3}"
  if [[ ${result_code} -eq 0 ]]; then
    logger "${success_message}"
  else
    logger "${fail_message}"
    logger "The process was aborted."
    exit 1
  fi
}

# Writes a message to log file.
function logger() {
  local message="${1}"
  if [ -d "${LOG_DIR}" ]; then
    # Writes message to log file in the logs directory.
    echo "$(date +%H%M%S) - ${message}" >> "${LOG_DIR}/${LOG_FILE}"
  else
    # Sends message to script output since it cannot be written to a log file
    echo "${message}"
  fi
}

# Ensures that the directory exists.
function validate_dir() {
  local dir="${1}"
  if [[ -d "${dir}" ]]; then
    local result_code=0
  elif [[ -f "${dir}" ]]; then
    local result_code=1
  else
    create_dir "${dir}"
    local result_code=0
  fi
  result_handler \
    ${result_code} \
   "The ${dir} directory exists." \
   "The ${dir} is a file."
}

# Creates a directory when it does not exist.
function create_dir() {
  local dir="${1}"
  mkdir "${dir}"
  local result_code=$?
  result_handler \
    ${result_code} \
    "The ${dir} directory was created." \
    "The ${dir} directory could not be created."
}

# Evalutes if virtual machine is in an expected state.
function determine_vm_state() {
  vm_state_current="$(virsh domstate ${VM_NAME})"
  if [[ "${vm_state_current}" == "shut off" || \
  "${vm_state_current}" == "running" ]]; then
    local result_code=0
  else
    local result_code=1
  fi
  result_handler \
    ${result_code} \
    "The ${VM_NAME} virtual machine is in the ${vm_state_current} state." \
    "The ${VM_NAME} virtual machine is in an unexpected ${vm_state_current} state."
}

# Starts the virtual machines.
function start_vm() {
  virsh start "${VM_NAME}"
  local result_code=$?
  result_handler \
    ${result_code} \
    "The ${VM_NAME} virtual machine was started." \
    "The ${VM_NAME} virtual machine could not be started."
  sleep 10 # TODO(codygriffin): Change to 60 after development
}

# Ensures the virtual machine AppArmor Profile is disabled before performing \
# a blockcommit.
function disable_apparmor() {
  aa-disable "/etc/apparmor.d/libvirt/libvirt-$(virsh domuuid $VM_NAME)"
  logger "The ${VM_NAME} virtual machine AppArmor Profile is disabled."
}

# Creates the external, disk-only snapshot without metadata.
function create_snapshot() {
  local vm_disk=( $(virsh domblklist "${VM_NAME}" | grep "${VM_DIR}") )
  local new_snapshot_name="${VM_NAME}$(date +%Y%m%d%H%M%S)"
  local new_snapshot_file="${new_snapshot_name}.qcow2"
  virsh snapshot-create-as \
    --domain "${VM_NAME}" \
    --name "${new_snapshot_name}" \
    --diskspec "${vm_disk[0]}",file="${SNAPSHOT_DIR}${new_snapshot_file}",snapshot=external \
    --disk-only \
    --atomic \
    --no-metadata
  local result_code=$?
  result_handler \
    ${result_code} \
    "The ${new_snapshot_name} snapshot was created." \
    "The ${new_snapshot_name} snapshot could not be created."
}


validate_vm "${VM_NAME}"

validate_dir "${LOG_DIR}"

validate_dir "${SNAPSHOT_DIR}"

determine_vm_state 

if [[ "${vm_state_current}" == "shut off" ]]; then
  start_vm
fi

disable_apparmor

create_snapshot

# perform blockcommit
vm_disk_2=( $(virsh domblklist "${VM_NAME}" | grep "${VM_DIR}") )
qemu-img info --force-share --backing-chain "${vm_disk_2[1]}"
existing_snapshot_files=( $(echo "${SNAPSHOT_DIR}*") )
if [[ ${#existing_snapshot_files[@]} -gt ${SNAPSHOTS_TO_RETAIN} ]]; then
  virsh blockcommit \
    --domain "${VM_NAME}" \
    --path "${vm_disk_2[0]}" \
    --base "${VM_FILE}" \
    --top "${existing_snapshot_files[0]}" \
    --delete \
    --verbose \
    --wait
fi

# shutdown virtual machine based on initial vm state
