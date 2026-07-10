# BEGSCRIPT

set -eo pipefail

function log_info() {
    echo -e "[\\e[1;94mINFO\\e[0m] $*"
}

function log_warn() {
    echo -e "[\\e[1;93mWARN\\e[0m] $*"
}

function log_error() {
    echo -e "[\\e[1;91mERROR\\e[0m] $*"
}

function fail() {
  log_error "$*"
  exit 1
}

function assert_defined() {
  if [[ -z "$1" ]]
  then
    log_error "$2"
    exit 1
  fi
}

function as_content() {
  file_or_content=$1
  if [[ -f "${file_or_content}" ]]; then
    cat "${file_or_content}"
  else
    echo "${file_or_content}"
  fi
}

function install_ca_certs() {
  certs=$1
  if [[ -z "$certs" ]]
  then
    return
  fi

  # import in system
  if as_content "$certs" >> /etc/ssl/certs/ca-certificates.crt
  then
    log_info "CA certificates imported in \\e[33;1m/etc/ssl/certs/ca-certificates.crt\\e[0m"
  fi
  if as_content "$certs" >> /etc/ssl/cert.pem
  then
    log_info "CA certificates imported in \\e[33;1m/etc/ssl/cert.pem\\e[0m"
  fi
}

function unscope_variables() {
  _scoped_vars=$(env | awk -F '=' "/^scoped__[a-zA-Z0-9_]+=/ {print \$1}" | sort)
  if [[ -z "$_scoped_vars" ]]; then return; fi
  log_info "Processing scoped variables..."
  for _scoped_var in $_scoped_vars
  do
    _fields=${_scoped_var//__/:}
    _condition=$(echo "$_fields" | cut -d: -f3)
    case "$_condition" in
    if) _not="";;
    ifnot) _not=1;;
    *)
      log_warn "... unrecognized condition \\e[1;91m$_condition\\e[0m in \\e[33;1m${_scoped_var}\\e[0m"
      continue
    ;;
    esac
    _target_var=$(echo "$_fields" | cut -d: -f2)
    _cond_var=$(echo "$_fields" | cut -d: -f4)
    _cond_val=$(eval echo "\$${_cond_var}")
    _test_op=$(echo "$_fields" | cut -d: -f5)
    case "$_test_op" in
    defined)
      if [[ -z "$_not" ]] && [[ -z "$_cond_val" ]]; then continue;
      elif [[ "$_not" ]] && [[ "$_cond_val" ]]; then continue;
      fi
      ;;
    equals|startswith|endswith|contains|in|equals_ic|startswith_ic|endswith_ic|contains_ic|in_ic)
      # comparison operator
      # sluggify actual value
      _cond_val=$(echo "$_cond_val" | tr '[:punct:]' '_')
      # retrieve comparison value
      _cmp_val_prefix="scoped__${_target_var}__${_condition}__${_cond_var}__${_test_op}__"
      _cmp_val=${_scoped_var#"$_cmp_val_prefix"}
      # manage 'ignore case'
      if [[ "$_test_op" =~ _ic$ ]]
      then
        # lowercase everything
        _cond_val=$(echo "$_cond_val" | tr '[:upper:]' '[:lower:]')
        _cmp_val=$(echo "$_cmp_val" | tr '[:upper:]' '[:lower:]')
      fi
      case "$_test_op" in
      equals*)
        if [[ -z "$_not" ]] && [[ "$_cond_val" != "$_cmp_val" ]]; then continue;
        elif [[ "$_not" ]] && [[ "$_cond_val" == "$_cmp_val" ]]; then continue;
        fi
        ;;
      startswith*)
        if [[ -z "$_not" ]] && [[ ! "$_cond_val" =~ ^"$_cmp_val" ]]; then continue;
        elif [[ "$_not" ]] && [[ "$_cond_val" =~ ^"$_cmp_val" ]]; then continue;
        fi
        ;;
      endswith*)
        if [[ -z "$_not" ]] && [[ ! "$_cond_val" =~ "$_cmp_val"$ ]]; then continue;
        elif [[ "$_not" ]] && [[ "$_cond_val" =~ "$_cmp_val"$ ]]; then continue;
        fi
        ;;
      contains*)
        # shellcheck disable=SC2076
        if [[ -z "$_not" ]] && [[ ! "$_cond_val" =~ "$_cmp_val" ]]; then continue;
        elif [[ "$_not" ]] && [[ "$_cond_val" =~ "$_cmp_val" ]]; then continue;
        fi
        ;;
      in*)
        if [[ -z "$_not" ]] && [[ ! __"$_cmp_val"__ =~ __"$_cond_val"__ ]]; then continue;
        elif [[ "$_not" ]] && [[ __"$_cmp_val"__ =~ __"$_cond_val"__ ]]; then continue;
        fi
        ;;
      esac
      ;;
    *)
      log_warn "... unrecognized test operator \\e[1;91m${_test_op}\\e[0m in \\e[33;1m${_scoped_var}\\e[0m"
      continue
      ;;
    esac
    # matches
    _val=$(eval echo "\$${_target_var}")
    log_info "... apply \\e[32m${_target_var}\\e[0m from \\e[32m\$${_scoped_var}\\e[0m"
    _val=$(eval echo "\$${_scoped_var}")
    export "${_target_var}"="${_val}"
  done
  log_info "... done"
}

# evaluate and export a secret
# - $1: secret variable name
function eval_secret() {
  name=$1
  value=$(eval echo "\$${name}")
  case "$value" in
  @b64@*)
    decoded=$(mktemp)
    errors=$(mktemp)
    if echo "$value" | cut -c6- | base64 -d > "${decoded}" 2> "${errors}"
    then
      # shellcheck disable=SC2086
      export ${name}="$(cat ${decoded})"
      log_info "Successfully decoded base64 secret \\e[33;1m${name}\\e[0m"
    else
      fail "Failed decoding base64 secret \\e[33;1m${name}\\e[0m:\\n$(sed 's/^/... /g' "${errors}")"
    fi
    ;;
  @hex@*)
    decoded=$(mktemp)
    errors=$(mktemp)
    if echo "$value" | cut -c6- | sed 's/\([0-9A-F]\{2\}\)/\\\\x\1/gI' | xargs printf > "${decoded}" 2> "${errors}"
    then
      # shellcheck disable=SC2086
      export ${name}="$(cat ${decoded})"
      log_info "Successfully decoded hexadecimal secret \\e[33;1m${name}\\e[0m"
    else
      fail "Failed decoding hexadecimal secret \\e[33;1m${name}\\e[0m:\\n$(sed 's/^/... /g' "${errors}")"
    fi
    ;;
  @url@*)
    url=$(echo "$value" | cut -c6-)
    if command -v curl > /dev/null
    then
      decoded=$(mktemp)
      errors=$(mktemp)
      if curl -s -S -f --connect-timeout "${TBC_SECRET_URL_TIMEOUT:-5}" -o "${decoded}" "$url" 2> "${errors}"
      then
        # shellcheck disable=SC2086
        export ${name}="$(cat ${decoded})"
        log_info "Successfully curl'd secret \\e[33;1m${name}\\e[0m"
      else
        log_warn "Failed getting secret \\e[33;1m${name}\\e[0m:\\n$(sed 's/^/... /g' "${errors}")"
      fi
    elif command -v wget > /dev/null
    then
      decoded=$(mktemp)
      errors=$(mktemp)
      if wget -T "${TBC_SECRET_URL_TIMEOUT:-5}" -O "${decoded}" "$url" 2> "${errors}"
      then
        # shellcheck disable=SC2086
        export ${name}="$(cat ${decoded})"
        log_info "Successfully wget'd secret \\e[33;1m${name}\\e[0m"
      else
        log_warn "Failed getting secret \\e[33;1m${name}\\e[0m:\\n$(sed 's/^/... /g' "${errors}")"
      fi
    else
      log_warn "Couldn't get secret \\e[33;1m${name}\\e[0m: no http client found"
    fi
    ;;
  esac
}

function eval_all_secrets() {
  # exclude scoped variables and their copies passed to container services (`<service_name>_ENV_scoped__xxx`)
  encoded_vars=$(env | awk -F '=' '$1 !~ /(^|_ENV_)scoped__/ && $2 ~ /^@(b64|hex|url)@/ {print $1}')
  for var in $encoded_vars
  do
    eval_secret "$var"
  done
}

function tbc_envsubst() {
  awk '
    BEGIN {
      count_replaced_lines = 0
      # ASCII codes
      for (i=0; i<=255; i++)
        char2code[sprintf("%c", i)] = i
    }
    # determine encoding (from env or from file extension)
    function encoding() {
      enc = ENVIRON["TBC_ENVSUBST_ENCODING"]
      if (enc != "")
        return enc
      if (match(FILENAME, /\.(json|yaml|yml)$/))
        return "jsonstr"
      return "raw"
    }
    # see: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/encodeURIComponent
    function uriencode(str) {
      len = length(str)
      enc = ""
      for (i=1; i<=len; i++) {
        c = substr(str, i, 1);
        if (index("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.!~*'\''()", c))
          enc = enc c
        else
          enc = enc "%" sprintf("%02X", char2code[c])
      }
      return enc
    }
    /# *nosubst/ {
      print $0
      next
    }
    {
      orig_line = $0
      line = $0
      count_repl_in_line = 0
      # /!\ 3rd arg (match) not supported in BusyBox awk
      while (match(line, /[$%]\{([[:alnum:]_]+)\}/)) {
        expr_start = RSTART
        expr_len = RLENGTH
        # get var name
        var = substr(line, expr_start+2, expr_len-3)
        # get var value (from env)
        val = ENVIRON[var]
        # check variable is set
        if (val == "") {
          printf("[\033[1;93mWARN\033[0m] Environment variable \033[33;1m%s\033[0m is not set or empty\n", var) > "/dev/stderr"
        } else {
          enc = encoding()
          if (enc == "jsonstr") {
            gsub(/["\\]/, "\\\\&", val)
            gsub("\n", "\\n", val)
            gsub("\r", "\\r", val)
            gsub("\t", "\\t", val)
          } else if (enc == "uricomp") {
            val = uriencode(val)
          } else if (enc == "raw") {
          } else {
            printf("[\033[1;93mWARN\033[0m] Unsupported encoding \033[33;1m%s\033[0m: ignored\n", enc) > "/dev/stderr"
          }
        }
        # replace expression in line
        line = substr(line, 1, expr_start - 1) val substr(line, expr_start + expr_len)
        count_repl_in_line++
      }
      if (count_repl_in_line) {
        if (count_replaced_lines == 0)
          printf("[\033[1;94mINFO\033[0m] Variable expansion occurred in file \033[33;1m%s\033[0m:\n", FILENAME) > "/dev/stderr"
        count_replaced_lines++
        printf("> line %s: %s\n", NR, orig_line) > "/dev/stderr"
      }
      print line
    }
  ' "$@"
}

function exec_hook() {
  if [[ ! -x "$1" ]] && ! chmod +x "$1"
  then
    log_warn "... could not make \\e[33;1m${1}\\e[0m executable: please do it (chmod +x)"
    # fallback technique
    sh "$1"
  else
    "$1"
  fi
}

function configure_netrc() {
  # maybe install .netrc
  if [[ -f ".netrc" ]]; then
    log_info "--- \\e[32m.netrc\\e[0m file found: envsubst and install"
    tbc_envsubst .netrc > ~/.netrc
  else
    # Use CI job token to authenticate
    log_info "--- configure \\e[32m.netrc\\e[0m with CI job token"
    echo -e "machine ${CI_SERVER_HOST}\nlogin ${CI_JOB_USER}\npassword ${CI_JOB_TOKEN}" >> ~/.netrc
  fi
  chmod 0600 ~/.netrc
}

function maybe_install_requirements() {
  configure_netrc

  # maybe execute pre ansible-galaxy script
  prescript="$ANSIBLE_SCRIPTS_DIR/pre-ansible-galaxy.sh"
  if [[ -f "$prescript" ]]; then
    log_info "--- \\e[32mpre-ansible-galaxy\\e[0m hook (\\e[33;1m${prescript}\\e[0m) found: execute"
    exec_hook "$prescript"
  else
    log_info "--- \\e[32mpre-ansible-galaxy\\e[0m hook (\\e[33;1m${prescript}\\e[0m) not found: skip"
  fi

  if [ -f "$ANSIBLE_REQUIREMENTS_FILE" ]
  then
    log_info "--- \\e[32mrequirements\\e[0m file (\\e[33;1m${ANSIBLE_REQUIREMENTS_FILE}\\e[0m) found: running \\e[33;1mansible-galaxy install\\e[0m"
    # roles and collections are downloaded relatively to ANSIBLE_HOME (cached dir)
    # shellcheck disable=SC2086
    ansible-galaxy install -r "$ANSIBLE_REQUIREMENTS_FILE" $ANSIBLE_GALAXY_EXTRA_ARGS
  fi
}

function run_ansible() {
  inventory=$1
  tags=$2
  extra_opts=$3
  playbook_file=$4

  export environment_type=$ENV_TYPE
  export environment_name=${ENV_APP_NAME:-${ANSIBLE_BASE_APP_NAME}${ENV_APP_SUFFIX}}
  export environment_url=${ENV_URL:-${ANSIBLE_ENVIRONMENT_URL:-$CI_ENVIRONMENT_URL}}
  environment_namespace=$(echo "$ANSIBLE_ENVIRONMENT_NAMESPACE" | tr -d '[:punct:]' | tr '[:upper:]' '[:lower:]')
  export environment_namespace
  private_key=${ENV_PRIVATE_KEY:-${ANSIBLE_DEFAULT_PRIVATE_KEY:-$ANSIBLE_PRIVATE_KEY}}
  public_key=${ENV_PUBLIC_KEY:-${ANSIBLE_DEFAULT_PUBLIC_KEY:-$ANSIBLE_PUBLIC_KEY}}
  vault_password=${ENV_VAULT_PASSWORD:-$ANSIBLE_VAULT_PASSWORD}

  # variables expansion in $environment_url
  environment_url=$(echo "$environment_url" | TBC_ENVSUBST_ENCODING=uricomp tbc_envsubst)
  export environment_url
  # extract hostname from $environment_url
  hostname=$(echo "$environment_url" | awk -F[/:] '{print $4}')
  export hostname

  log_info "--- \\e[32mrun_ansible\\e[0m"
  # shellcheck disable=SC2154
  log_info "--- \$environment_type: \\e[33;1m${environment_type}\\e[0m"
  # shellcheck disable=SC2154
  log_info "--- \$environment_name: \\e[33;1m${environment_name}\\e[0m"

  # unset any upstream deployment env & artifacts
  rm -f ansible.env*
  rm -f environment_url.txt

  maybe_install_requirements

  # maybe execute pre ansible-playbook script
  prescript="$ANSIBLE_SCRIPTS_DIR/pre-ansible-playbook.sh"
  if [[ -f "$prescript" ]]; then
    log_info "--- \\e[32mpre-ansible-playbook\\e[0m hook (\\e[33;1m${prescript}\\e[0m) found: execute"
    exec_hook "$prescript"
  else
    log_info "--- \\e[32mpre-ansible-playbook\\e[0m hook (\\e[33;1m${prescript}\\e[0m) not found: skip"
  fi


  # extra var environment_type & environment_name
  ansible_opts="-e environment_type=$environment_type -e environment_name=$environment_name -e environment_namespace=$environment_namespace"

  if [ -n "$vault_password" ]; then
    log_info "--- \\e[32mvault password\\e[0m found"
    echo "$vault_password" > .ansible_vault_password
    ansible_opts="$ansible_opts --vault-password-file .ansible_vault_password"
  fi

  if [ -n "$private_key" ]; then
    log_info "--- \\e[32mprivate key\\e[0m found"
    if [ -n "$ANSIBLE_PRIVATE_KEY" ]; then
      log_warn "ANSIBLE_PRIVATE_KEY conflicts with ansible 2.9+ ssh configuration. Use ANSIBLE_DEFAULT_PRIVATE_KEY instead"
    fi
    if [ -f "$private_key" ]; then
      # chmod to prevent SSH client from complaining
      chmod 0600 "$private_key" || true
      ansible_opts="$ansible_opts --private-key=$private_key -e ssh_private_key_file=$private_key -e ANSIBLE_SSH_PRIVATE_KEY_FILE=$private_key"
    else
      echo "$private_key" > .ansible_private_key
      chmod 0600 .ansible_private_key
      ansible_opts="$ansible_opts --private-key=.ansible_private_key -e ssh_private_key_file=.ansible_private_key -e ANSIBLE_SSH_PRIVATE_KEY_FILE=.ansible_private_key"
    fi
  fi

  if [ -n "$public_key" ]; then
    log_info "--- \\e[32mpublic key\\e[0m found"
    if [ -n "$ANSIBLE_PUBLIC_KEY" ]; then
      log_warn "ANSIBLE_PUBLIC_KEY is deprecated. Use ANSIBLE_DEFAULT_PUBLIC_KEY instead"
    fi
    if [ -f "$public_key" ]; then
      ansible_opts="$ansible_opts -e ssh_public_key_file=$public_key -e ANSIBLE_SSH_PUBLIC_KEY_FILE=$public_key"
    else
      echo "$public_key" > .ansible_public_key
      chmod 0600 .ansible_public_key
      ansible_opts="$ansible_opts -e ssh_public_key_file=.ansible_public_key -e ANSIBLE_SSH_PUBLIC_KEY_FILE=.ansible_public_key"
    fi
  fi

  log_info "--- using \\e[32mplaybook\\e[0m file: \\e[33;1m${playbook_file}\\e[0m"

  if [ -n "$inventory" ]; then
    log_info "--- using \\e[32minventory\\e[0m file: \\e[33;1m${inventory}\\e[0m"
    ansible_opts="$ansible_opts --inventory $inventory"
  fi

  if [ -n "$tags" ]; then
    log_info "--- using \\e[32mtags\\e[0m list: \\e[33;1m${tags}\\e[0m"
    ansible_opts="$ansible_opts --tags $tags"
  fi

  if [ -n "$extra_opts" ]; then
    log_info "--- using \\e[32mextra options\\e[0m: \\e[33;1m${extra_opts}\\e[0m"
  fi

  log_info "--- using \\e[32mansible-playbook\\e[0m version: \\n\\e[33;1m$(ansible-playbook --version)\\e[0m"
  log_info "--- run \\e[32mplaybook\\e[0m"

  # shellcheck disable=SC2086
  ansible-playbook $ansible_opts $extra_opts "$playbook_file"

  # maybe execute post ansible-playbook script
  postscript="$ANSIBLE_SCRIPTS_DIR/post-ansible-playbook.sh"
  if [[ -f "$postscript" ]]; then
    log_info "--- \\e[32mpost-ansible-playbook\\e[0m hook (\\e[33;1m${postscript}\\e[0m) found: execute"
    exec_hook "$postscript"
  else
    log_info "--- \\e[32mpost-ansible-playbook\\e[0m hook (\\e[33;1m${postscript}\\e[0m) not found: skip"
  fi

  if [[ -f environment_url.txt ]]
  then
    environment_url=$(cat environment_url.txt)
    export environment_url
    log_info "--- dynamic environment url found: (\\e[33;1m$environment_url\\e[0m)"
  else
    echo "$environment_url" > environment_url.txt
  fi
  # var prefix ('_' if namespace)
  prefix="${environment_namespace:+${environment_namespace}_}"
  dotenvfile="ansible.env${environment_namespace:+.${environment_namespace}}"
  {
    echo "${prefix}environment_type=${environment_type}"
    echo "${prefix}environment_name=${environment_name}"
    echo "${prefix}environment_url=${environment_url}"
    # '$environment_url' is required by GitLab (dynamic env URL)
    if [[ "$environment_namespace" ]]; then echo "environment_url=${environment_url}"; fi
  } >> "$dotenvfile"
  chmod 644 environment_url.txt "$dotenvfile"
}

function cleanup_secrets() {
   if [ -f ".ansible_private_key" ]; then
     rm -rf .ansible_private_key
     log_info "--- \\e[32mprivate key\\e[0m removed from temporary files"
   fi

   if [ -f ".ansible_vault_password" ]; then
     rm -rf .ansible_vault_password
     log_info "--- \\e[32mvault password\\e[0m removed from temporary files"
   fi
}

unscope_variables
eval_all_secrets

# ENDSCRIPT