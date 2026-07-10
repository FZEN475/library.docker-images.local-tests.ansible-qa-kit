source /ci/tbc/tbc-ansible.sh
cd "$ANSIBLE_PROJECT_DIR"
mkdir -p -m 777 reports

# Оставляем pipefail, чтобы функция run_and_report видела реальный статус Molecule, а не sed.
set +e
set -o pipefail

# Переменная-флаг. Если хоть один шаг упадет, мы переключим её в 1.
SCRIPT_FAILED=0

run_and_report() {
    local step_name="$1"
    shift
    local log_file="reports/molecule-${step_name}.log"

    # 1. Запускаем Molecule и пишем ВСЁ напрямую в файл (без промежуточных пайпов)
    "$@" > "$log_file" 2>&1
    local status=$?

    # 2. Выводим содержимое файла на экран терминала GitLab CI в реальном времени (со всеми цветами!)
    cat "$log_file"

    # 3. Очищаем сохраненный файл от ANSI-последовательностей для удобного чтения (создаем чистую копию)
    # Если BusyBox awk начнет капризничать, можно этот шаг сделать опциональным
    if [ -f "$log_file" ]; then
        awk '{gsub(/\x1b\[[0-9;]*m/, ""); print}' "$log_file" > "${log_file}.tmp" && mv "${log_file}.tmp" "$log_file"
    fi

    # 4. Проверяем статус
    if [ $status -ne 0 ]; then
        log_error "[ERROR] Шаг '${step_name}' завершился с ошибкой (код: $status)!"
        SCRIPT_FAILED=1
    fi
    return $status
}

log_info "Проверка доступности удаленного Docker-хоста: ${DOCKER_HOST}"
if ! docker ps > /dev/null 2>&1; then
    log_error "Ошибка: Не удалось подключиться к удаленному Docker по адресу ${DOCKER_HOST}"
    exit 1
fi

log_info "Запуск полного цикла тестирования Molecule (test sequence)..."

log_info "Очистка окружения..."
run_and_report "destroy-init" /opt/venv/bin/molecule destroy
log_info "Загрузка зависимостей..."
/opt/venv/bin/molecule dependency

if [ "$MOLECULE_ENABLE_SYNTAX" = "true" ]; then
  log_info "Запуск syntax..."
  run_and_report "syntax" /opt/venv/bin/molecule syntax
fi

log_info "Создание контейнеров..."
run_and_report "create" /opt/venv/bin/molecule create

if [ -f "molecule/default/prepare.yml" ]; then
  log_info "Подготовка окружения..."
  run_and_report "prepare" /opt/venv/bin/molecule prepare
fi

if [ "$MOLECULE_DEPLOY_ENABLE" = "true" ]; then
  log_info "Выполнение конфигурации (DEPLOY)..."
  run_and_report "converge-deploy" /opt/venv/bin/molecule converge ${ANSIBLE_DEFAULT_TAGS:+-- --tags="$ANSIBLE_DEFAULT_TAGS"}

  if [ "$MOLECULE_DEPLOY_ENABLE_IDEMPOTENCE" = "true" ]; then
    log_info "Проверка idempotence (DEPLOY)..."
    run_and_report "idempotence-deploy" /opt/venv/bin/molecule idempotence ${ANSIBLE_DEFAULT_TAGS:+-- --tags="$ANSIBLE_DEFAULT_TAGS"}
  fi

  if [ "$MOLECULE_DEPLOY_ENABLE_SIDE_EFFECT" = "true" ]; then
    log_info "Проверка side-effect (DEPLOY)..."
    run_and_report "side-effect-deploy" /opt/venv/bin/molecule side-effect --
  fi

  if [ "$MOLECULE_DEPLOY_ENABLE_VERIFY" = "true" ]; then
    log_info "Проверка verify (DEPLOY)..."
    run_and_report "verify-deploy" /opt/venv/bin/molecule verify --
  fi
fi

if [ "$MOLECULE_CLEANUP_ENABLE" = "true" ] && [ -n "$ENV_CLEANUP_TAGS" ]; then
  log_info "Выполнение конфигурации (CLEANUP)..."
  run_and_report "verify-cleanup" /opt/venv/bin/molecule converge -- --tags="$ENV_CLEANUP_TAGS"

  if [ "$MOLECULE_CLEANUP_ENABLE_IDEMPOTENCE" = "true" ]; then
    log_info "Проверка idempotence (CLEANUP)..."
    run_and_report "idempotence-cleanup" /opt/venv/bin/molecule idempotence -- --tags="$ENV_CLEANUP_TAGS"
  fi

  if [ "$MOLECULE_CLEANUP_ENABLE_SIDE_EFFECT" = "true" ]; then
    log_info "Проверка side-effect (CLEANUP)..."
    run_and_report "side-effect-cleanup" /opt/venv/bin/molecule side-effect --
  fi

  if [ "$MOLECULE_CLEANUP_ENABLE_VERIFY" = "true" ]; then
    log_info "Проверка verify (CLEANUP)..."
    run_and_report "verify-cleanup" /opt/venv/bin/molecule verify --
  fi
fi

if [ "$MOLECULE_SKIP_DESTROY" != "true" ]; then
    log_info "Очистка инфраструктуры..."
    run_and_report "destroy" /opt/venv/bin/molecule destroy
else
    log_warn "Контейнеры оставлены на хосте для отладки!"
fi

log_info "Тестирование Molecule успешно завершено!"