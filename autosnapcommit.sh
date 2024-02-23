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
    logger "The ${VM_NAME} virtual machine and its ${VM_FILE} exist."
  else
    local exit_code=1
    exit_code_handler \
      ${exit_code} \
      "The ${VM_NAME} virtual machine and/or its ${VM_FILE} do not exist."
  fi
}

# Ensures that the directory exists.
function validate_dir() {
  local dir="${1}"
  if [[ -d "${dir}" ]]; then
    logger "The ${dir} directory exists."
  else
    create_dir "${dir}"
  fi
}

# Writes a message to log file.
function logger() {
  local message="${1}"
  if [ -d "${LOG_DIR}" ]; then
    # Writes message to log file in the logs directory.
    echo "$(date +%H%M%S) - ${message}" >> "${LOG_DIR}/${LOG_FILE}"
  else
    # Sets message to script output since it cannot be written to a log file
    echo "${message}"
  fi
}

# Creates a directory when it does not exist.
function create_dir() {
  local dir="${1}"
  mkdir "${dir_name}"
  local exit_code=$?
  exit_code_handler \
    ${exit_code} \
    "The ${dir_name} directory could not be created." \
    "The ${dir_name} directory was created."
}

# Evaluates an exit code and sends corresponding message to be written to the
# log file.
function exit_code_handler() {
  local exit_code=${1}
  local fail_message="${2}"
  local success_message="${3}"
  if [[ ${exit_code} -ne 0 ]]; then
    logger "${fail_message}"
  else
    logger "${success_message}"
    exit 1
  fi
}

# Starts the virtual machines.
function start_vm() {
  virsh start "${VM_NAME}"
  local exit_code=$?
  exit_code_handler \
    ${exit_code} \
    "The ${VM_NAME} virtual machine could not be started." \
    "The ${VM_NAME} virtual machine was started."
  sleep 10 # TODO(codygriffin): Change to 60 after development
}

# Evalutes and sets the current state of the virtual machine.
function evaluate_vm_state() {
  local vm_state="${1}"
  case "${vm_state}" in
    "shut off")
      logger "The ${VM_NAME} virtual machine is ${vm_state}."
      vm_state_current="${vm_state}"
      ;;
    "running")
      logger "The ${VM_NAME} virtual machine is ${vm_state}."
      vm_state_current="${vm_state}"
      ;;
    *)
      logger "The ${VM_NAME} virtual machine is in an unexpected ${vm_state} state."
      vm_state_current="${vm_state}"
      local exit_code=1
      exit_code_handler \
        ${exit_code} \
        "The process was aborted. Check journalctl logs for more information."
      ;;
  esac
}

# Creates the external, disk-only snapshot without metadata.
function create_snapshot() {
  virsh snapshot-create-as \
    --domain "${VM_NAME}" "${new_snapshot_name}" \
    --diskspec "${VM_DISK[0]}",file="${SNAPSHOT_DIR}${new_snapshot_file}",snapshot=external \
    --disk-only \
    --atomic \
    --no-metadata
  local exit_code=$?
  exit_code_handler \
    ${exit_code} \
    "The ${new_snapshot_name} snapshot could not be created." \
    "The ${new_snapshot_name} snapshot was created."
}


validate_vm "${VM_NAME}"

validate_dir "${LOG_DIR}"

validate_dir "${SNAPSHOT_DIR}"

evaluate_vm_state "${VM_STATE_INITIAL}"

# temporarily disable AppArmor for the virtual machine

create_snapshot

# reenable AppArmor for the virtual machine

# shutdown virtual machine based on initial vm state


new_snapshot_name="${VM_NAME}$(date +%Y%m%d%H%M%S)"
new_snapshot_file="${new_snapshot_name}.qcow2"
existing_snapshot_files=( $(echo "${SNAPSHOT_DIR}${VM_NAME}*.qcow2") )
existing_snapshot_count=$(echo ${#existing_snapshot_files[@]})
