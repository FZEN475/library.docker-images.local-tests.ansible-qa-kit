source /ci/tbc/tbc-ansible.sh
cd "$ANSIBLE_PROJECT_DIR"
mkdir -p -m 777 reports

assert_defined "${ENV_INVENTORY:-${ANSIBLE_DEFAULT_INVENTORY}}" 'Missing required Ansible inventory'
assert_defined "${ENV_CLEANUP_PLAYBOOK_FILE:-${ENV_PLAYBOOK_FILE}}" 'Missing required Ansible playbook'
assert_defined "$ENV_CLEANUP_TAGS" 'Missing required Ansible cleanup tags'

run_ansible "${ENV_INVENTORY:-${ANSIBLE_DEFAULT_INVENTORY}}" "$ENV_CLEANUP_TAGS" "${ENV_EXTRA_ARGS:-${ANSIBLE_DEFAULT_EXTRA_ARGS}}" "${ENV_CLEANUP_PLAYBOOK_FILE:-${ENV_PLAYBOOK_FILE}}"

cp "$dotenvfile" reports/
cp ./environment_url.txt reports/
