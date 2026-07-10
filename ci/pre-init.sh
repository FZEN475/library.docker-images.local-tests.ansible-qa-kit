source /ci/tbc/tbc-ansible.sh
cd "$ANSIBLE_PROJECT_DIR"

prescript="$ANSIBLE_SCRIPTS_DIR/pre-init.sh"
if [[ -f "$prescript" ]]; then
  log_info "--- \\e[32mpre-init\\e[0m hook (\\e[33;1m${prescript}\\e[0m) found: execute"
  exec_hook "$prescript"
else
  log_info "--- \\e[32mpre-init\\e[0m hook (\\e[33;1m${prescript}\\e[0m) not found: skip"
fi