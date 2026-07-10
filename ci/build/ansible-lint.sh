source /ci/tbc/tbc-ansible.sh
cd "$ANSIBLE_PROJECT_DIR"
maybe_install_requirements
mkdir -p -m 777 reports

if [[ "$TRACE" ]]; then
  ansible-lint --version
  ansible --version
  log_info "ansible-lint --help"
  ansible-lint --help
  log_info "ansible-lint "$ENV_PLAYBOOK_FILE" -f codeclimate > reports/ansible-lint-$ENV_TYPE.codeclimate.json || true"
fi

ansible-lint "$ENV_PLAYBOOK_FILE" -f codeclimate > reports/ansible-lint-$ENV_TYPE.codeclimate.json || true
ansible-lint "$ENV_PLAYBOOK_FILE" $ANSIBLE_LINT_EXTRA_ARGS
