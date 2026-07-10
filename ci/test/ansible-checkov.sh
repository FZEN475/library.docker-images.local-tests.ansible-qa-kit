source /ci/tbc/tbc-ansible.sh
cd "$ANSIBLE_PROJECT_DIR"
mkdir -p -m 777 reports

if [[ "$TRACE" ]]; then
  checkov --version
  log_info "checkov --help"
  checkov --help
  log_info "checkov --soft-fail --output junitxml --directory . $ANSIBLE_CHECKOV_ARGS > \"reports/ansible-checkov.xunit.xml\""
fi
# checkov allows generating several report formats at once using multiple --output options
# and --output-file-path but the option defines an output directory, and report filenames
# can't be chosen ("results_junitxml.xml" and "results_cli.txt")
checkov --soft-fail --output junitxml --directory . $ANSIBLE_CHECKOV_ARGS > "reports/ansible-checkov.xunit.xml"
if [[ "$DEFECTDOJO_ANSIBLE_CHECKOV_REPORTS" ]]
then
  checkov --soft-fail --output json --directory . $ANSIBLE_CHECKOV_ARGS > "reports/ansible-checkov.native.json"
fi
checkov --directory . $ANSIBLE_CHECKOV_ARGS