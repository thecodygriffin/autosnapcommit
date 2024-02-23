#!/bin/bash
#
# Performs the snapshot creation and blockcommit maintenance of virtual
# machines.

# Set constant variables for script.
VM_NAME="${1}"
VM_DIR="${2}${VM_NAME}/"
VM_FILE="${VM_NAME}.qcow2"
VM_DISK=( $(virsh domblklist "${VM_NAME}" | grep "${VM_DIR}") )
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

# Evalutes and sets the current state of the virtual machine.
function evaluate_vm_state() {
  local vm_state="${1}"
  case "${vm_state}" in
    "shut off")
      local result_code=0
      vm_state_current="${vm_state}"
      ;;
    "running")
      local result_code=0
      vm_state_current="${vm_state}"
      ;;
    *)
      local result_code=1
      vm_state_current="${vm_state}"
      ;;
  esac
  result_handler \
    ${result_code} \
    "The ${VM_NAME} virtual machine is ${vm_state}." \
    "The ${VM_NAME} virtual machine is in an unexpected ${vm_state} state."
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

# Creates the external, disk-only snapshot without metadata.
function create_snapshot() {
  virsh snapshot-create-as \
    --domain "${VM_NAME}" "${new_snapshot_name}" \
    --diskspec "${VM_DISK[0]}",file="${SNAPSHOT_DIR}${new_snapshot_file}",snapshot=external \
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

# RESUME HERE
evaluate_vm_state "${VM_STATE_INITIAL}"

# temporarily disable AppArmor for the virtual machine

create_snapshot

# reenable AppArmor for the virtual machine

# shutdown virtual machine based on initial vm state


new_snapshot_name="${VM_NAME}$(date +%Y%m%d%H%M%S)"
new_snapshot_file="${new_snapshot_name}.qcow2"
existing_snapshot_files=( $(echo "${SNAPSHOT_DIR}${VM_NAME}*.qcow2") )
existing_snapshot_count=$(echo ${#existing_snapshot_files[@]})
