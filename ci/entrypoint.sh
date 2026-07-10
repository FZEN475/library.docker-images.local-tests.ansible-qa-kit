#!/usr/bin/env ash

export ANSIBLE_HOME="$CI_PROJECT_DIR/$ANSIBLE_PROJECT_DIR/.ansible"

source /ci/tbc/tbc-ansible.sh

# Функция для запуска скрипта в подпроцессе с сохранением среды
run_subprocess() {
    local script="$1"
    /bin/ash -c "source /tmp/current_env.sh; source $script"
}

install_ca_certs "${CUSTOM_CA_CERTS:-$DEFAULT_CA_CERTS}"

export -p > /tmp/current_env.sh

log_info "---> pre-init <---"
if [ "$PRE_INIT_ENABLE" = "true" ]; then
    run_subprocess /ci/pre-init.sh
else
    log_info "Действие пропущено: PRE_INIT_ENABLE=${PRE_INIT_ENABLE}"
fi

log_info "---> ansible-lint <---"
if ! [ "$ANSIBLE_LINT_DISABLED" = "true" ]; then
    run_subprocess /ci/build/ansible-lint.sh
else
    log_info "Действие пропущено: ANSIBLE_LINT_DISABLED=${ANSIBLE_LINT_DISABLED}"
fi

log_info "---> ansible-checkov <---"
if ! [ "$ANSIBLE_CHECKOV_DISABLED" = "true" ]; then
    run_subprocess /ci/test/ansible-checkov.sh
else
    log_info "Действие пропущено: ANSIBLE_CHECKOV_DISABLED=${ANSIBLE_CHECKOV_DISABLED}"
fi

log_info "---> molecule test <---"
if ! [ "$ANSIBLE_MOLECULE_DISABLED" = "true" ]; then
    run_subprocess /ci/test/ansible-molecule.sh
else
    log_info "Действие пропущено: ANSIBLE_MOLECULE_DISABLED=${ANSIBLE_MOLECULE_DISABLED}"
fi

log_info "---> ansible-deploy <---"
if ! [ "$ANSIBLE_DEPLOY_DISABLED" = "true" ]; then
    run_subprocess /ci/deploy/ansible-deploy.sh
else
    log_info "Действие пропущено: ANSIBLE_DEPLOY_DISABLED=${ANSIBLE_DEPLOY_DISABLED}"
fi

log_info "---> ansible-cleanup <---"
if ! [ "$ANSIBLE_CLEANUP_DISABLED" = "true" ]; then
    run_subprocess /ci/deploy/ansible-cleanup.sh
else
    log_info "Действие пропущено: ANSIBLE_CLEANUP_DISABLED=${ANSIBLE_CLEANUP_DISABLED}"
fi
