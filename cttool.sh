#!/bin/bash


container_tool=""
log_file=""

_con_name=""
_con_cid=""
_con_pid=""
_con_past_path=""
_con_path=""

function logger()
{
    [ $# -eq 3 ] || (logger "ERROR" "$LINENO" "Error in funtion logger for params number!" && return 1)
    declare -u exec_level="$1"
    declare exec_func="${FUNCNAME[1]}"
    declare exec_lineno="$2"
    declare exec_msg="$3"
    declare exec_time

    exec_time="$(date +"%Y-%m-%d %H:%M:%S")"
    if [ -n "$log_file" ]; then
        echo "|$exec_time|$exec_level|$exec_func|$exec_lineno|$exec_msg" | tee "$log_file"
        if [ "$exec_level" == "ERROR" ]; then
            echo "========== FUNCTION STACK ==========" | tee "$log_file"
            for func in "${FUNCNAME[@]:1}"; do
                echo "---------> $func <--------- " | tee "$log_file"
            done
            echo "========== FUNCTION STACK ==========" | tee "$log_file"
        fi
    else
        echo "|$exec_time|$exec_level|$exec_func|$exec_lineno|$exec_msg"
        if [ "$exec_level" == "ERROR" ]; then
            echo "========== FUNCTION STACK =========="
            for func in "${FUNCNAME[@]:1}"; do
                echo "---------> $func <--------- "
            done
            echo "========== FUNCTION STACK =========="
        fi
    fi

    return 0
}

function _check_container_tool()
{
    if [ -n "$(command -v crictl)" ]; then
        container_tool="crictl"
    elif [ -n "$(command -v docker)" ]; then
        container_tool="docker"
    else
        logger "ERROR" "$LINENO" "Not found container tool!"
        return 1
    fi

    return 0
}

function _get_container_id_from_exact_name()
{
    [ $# -eq 1 ] || (logger "ERROR" "$LINENO" "Error for params number!" && return 1)

    declare container_name="$1"
    declare container_id

    if [ "$container_tool" == "crictl" ]; then
        if [ "$(crictl ps | awk 'NR > 1 { if ($(NF-3) == "'"$container_name"'") print $1 }' | wc -l)" -ne 1 ]; then
            logger "ERROR" "$LINENO" "Failed to get container ID!"
            return 1
        fi
        container_id="$(crictl ps | awk 'NR > 1 { if ($(NF-3) == "'"$container_name"'") print $1 }')"
    elif [ "$container_tool" == "docker" ]; then
        if [ "$(docker container ls --format '{{.Names}} {{.ID}}' | awk '{if ($1 == "'"$container_name"'") print $1}' | wc -l)" -ne 1 ]; then
            logger "ERROR" "$LINENO" "Failed to get container ID!"
            return 1
        fi
        container_id="$(docker container ls --format '{{.Names}} {{.ID}}' | awk '{if ($1 == "'"$container_name"'") print $1}' | wc -l)"
    else
        logger "ERROR" "$LINENO" "Not supported container tool $container_tool!"
        return 1
    fi

    echo "$container_id"
}

function _get_container_pid()
{
    [ $# -eq 1 ] || (logger "ERROR" "$LINENO" "Error for params number!" && return 1)

    declare container_id="$1"
    declare container_pid

    if [ "$container_tool" == "crictl" ]; then
        container_pid="$(crictl inspect --output go-template --template '{{.info.pid}}' "$container_id")"
    elif [ "$container_tool" == "docker" ]; then
        container_pid="$(docker inspect --format '{{.State.Pid}}' "$container_id")"
    else
        logger "ERROR" "$LINENO" "Not supported container tool $container_tool!"
        return 1
    fi

    if [[ "$container_pid" =~ ^[0-9]+$ ]]; then
        echo "$container_pid"
    else
        logger "ERROR" "$LINENO" "Failed to get container PID!"
        return 1
    fi
}

function _get_absolutepath()
{
    [ $# -eq 1 ] || (logger "ERROR" "$LINENO" "Error for params number!" && return 1)

    declare in_path="$1"
    [ ! -f "$in_path" ] && [ ! -d "$in_path" ] && logger "ERROR" "$LINENO" "$in_path not found!" && return 1

    readlink -f "$in_path"
    return 0
}

function _cp_base()
{
    declare container_pid="$1"
    declare container_path="$2"
    declare node_path="$3"
    declare cp_mode="$4"

    case "$cp_mode" in
        "c2n")
            nsenter -t "$container_pid" -m --wd='/' -- sh -c "cp -a $container_path $node_path"
            ;;
        "n2c")
            nsenter -t "$container_pid" -m --wd='/' -- sh -c "cp -a $node_path $container_path"
            ;;
        *)
            echo "Error pattern!"
            return 1
            ;;
    esac
    return $?
}

function cinit()
{
    declare container_name="$1"
    declare container_path="$2"
    declare logger_switch="$3"

    if [ -z "$container_name" ]; then
        logger "ERROR" "$LINENO" "Incorrect pattern! Please container_name!"
        return 1
    fi

    if [ -n "$logger_switch" ]; then
        log_file="/tmp/cttool_$(date +"%Y%m%d%H%M%S").log"
    fi

    if [ -z "$container_path" ]; then
        container_path="/"
    fi

    _check_container_tool || return 1

    declare container_cid
    container_cid="$(_get_container_id_from_exact_name "$container_name")"
    [ -z "$container_cid" ] && return 1

    declare container_pid
    container_pid="$(_get_container_pid "$container_cid")"
    [ -z "$container_pid" ] && return 1

    if nsenter -t "$container_pid" -m --wd='/' -- sh -c "test -e $container_path"; then
        _con_path="$container_path"
        _con_name="$container_name"
        _con_cid="$container_cid"
        _con_pid="$container_pid"
        _con_last_path="$_con_path"

        export _con_path
        export _con_name
        export _con_cid
        export _con_pid
        export _con_last_path

        logger "INFO" "$LINENO" "Init success! cname: $_con_name; cid: $_con_cid; pid: $_con_pid; path: $_con_path"
    else
        logger "ERROR" "$LINENO" "The path $container_path does not exist in container $container_name!"
        return 1
    fi
}

function ccheck()
{
    echo "cname: $_con_name; cid: $_con_cid; pid: $_con_pid; path: $_con_path"
}

function _con_check_init()
{
    if [ -z "$_con_path" ] || [ -z "$_con_pid" ]; then
        logger "ERROR" "$LINENO" "Please use cinit first!"
        return 1
    fi
    return 0
}

function cls()
{
    _con_check_init || return 1
    nsenter -t "$_con_pid" -m --wd='/' -- sh -c "cd $_con_path; ls $*"
}

function ccd()
{
    _con_check_init || return 1
    declare chgpath="$1"

    if nsenter -t "$_con_pid" -m --wd='/' -- sh -c "cd $_con_path; test -d $chgpath" || { [ -n "$_con_last_path" ] && [ "$chgpath" == '-' ]; }; then
        if [ "$chgpath" == '-' ]; then
            declare tmp_path="$_con_last_path"
        fi
        _con_last_path="$_con_path"
        if [ "$chgpath" == '-' ]; then
            chgpath="$tmp_path"
        fi
        _con_path="$(nsenter -t "$_con_pid" -m --wd='/' -- sh -c "cd $_con_path; cd $chgpath; pwd")"
        export _con_path
        export _con_last_path
        logger "INFO" "$LINENO" "Change path to $_con_path"
    else
        logger "ERROR" "$LINENO" "Cannot access folder $chgpath in container $_con_name. Please check..."
        return 1
    fi
}

function cpwd()
{
    _con_check_init || return 1
    echo "$_con_path"
}

function cexec()
{
    _con_check_init || return 1
    nsenter -t "$_con_pid" -m --wd='/' -- sh -c "cd $_con_path; $*"
}

function ccp()
{
    _con_check_init || return 1

    [ $# -eq 2 ] || (logger "ERROR" "$LINENO" "Error for params number!" && return 1)

    declare from_path="$1"
    declare to_path="$2"

    declare cp_mode

    if [[ "$from_path" =~ ':' ]]; then
        cp_mode='c2n'
    elif [[ "$to_path" =~ ':' ]]; then
        cp_mode='n2c'
    else
        logger "ERROR" "$LINENO" "Error pattern in ccp!"
        return 1
    fi

    declare container_path
    declare node_path

    case "$cp_mode" in
        "c2n")
            container_path="$(echo "$from_path" | awk -F ':' '{print $2}')"
            node_path="$(echo "$to_path" | awk -F ':' '{print $1}')"
            ;;
        "n2c")
            container_path="$(echo "$to_path" | awk -F ':' '{print $2}')"
            node_path="$(echo "$from_path" | awk -F ':' '{print $1}')"
            ;;
        *)
            logger "ERROR" "$LINENO" "Error pattern in ccp!"
            return 1
            ;;
    esac
}

function cin()
{
    _con_check_init || return 1
    declare shell_type="$1"
    declare in_path="$2"

    if [ -z "$shell_type" ]; then
        shell_type="/bin/sh"
    else
        case "$container_tool" in
            "crictl")
                if [ "$(crictl exec -it "$_con_cid" "$shell_type" -c "test -e $in_path" 2>/dev/null)" ]; then
                    crictl exec -it "$_con_cid" "$shell_type"
                else
                    logger "ERROR" "$LINENO" "Cannot access file $in_path in container $_con_name. Please check..."
                    return 1
                fi
                ;;
            "docker")
                if [ "$(docker exec -it "$_con_cid" "$shell_type" -c "test -e $in_path" 2>/dev/null)" ]; then
                    docker exec -it "$_con_cid" "$shell_type"
                else
                    logger "ERROR" "$LINENO" "Cannot access file $in_path in container $_con_name. Please check..."
                    return 1
                fi
                ;;
            *)
                logger "ERROR" "$LINENO" "Not supported container tool $container_tool!"
                return 1
                ;;
        esac
    fi

    in_path="$_con_path/$in_path"

    nsenter -t "$_con_pid" -m -u -i -n -p "$shell_type" -c "cd $in_path; $shell_type"
}

function __get_dirs()
{
    COMPREPLY=()
    declare cur="${COMP_WORDS[COMP_CWORD]}"
    declare opts

    [ -z "$cur" ] && cur='./'
    opts="$(nsenter -t "$_con_pid" -m --wd='/' -- sh -c 'cd '"$_con_path"'; ls -ald $(compgen -d '"$cur"')')" || return 1

    mapfile -t COMPREPLY < <(compgen -W "${opts}" -- "${cur}")
}

function __get_files()
{
    COMPREPLY=()
    declare cur="${COMP_WORDS[COMP_CWORD]}"
    declare opts

    [ -z "$cur" ] && cur='./'
    opts="$(nsenter -t "$_con_pid" -m --wd='/' -- sh -c 'cd '"$_con_path"'; ls -ald $(compgen -f '"$cur"')')" || return 1

    mapfile -t COMPREPLY < <(compgen -W "${opts}" -- "${cur}")
}

function __get_con_names()
{
    COMPREPLY=()
    declare cur="${COMP_WORDS[COMP_CWORD]}"
    declare pre="${COMP_WORDS[COMP_CWORD-1]}"
    declare opts

    _check_container_tool || return 1
    if [ "$pre" == 'cinit' ]; then
        case "$container_tool" in
            "crictl")
                opts="$(crictl ps | awk 'NR > 1 {print $(NF-3)}')" || return 1
                mapfile -t COMPREPLY < <(compgen -W "${opts}" -- "${cur}")
                ;;
            "docker")
                opts="$(docker container ls --format '{{.Names}}')" || return 1
                mapfile -t COMPREPLY < <(compgen -W "${opts}" -- "${cur}")
                ;;
            *)
                logger "ERROR" "$LINENO" "Not supported container tool $container_tool!"
                return 1
                ;;
        esac
        mapfile -t COMPREPLY < <(compgen -W "${opts}" -- "${cur}")
    fi
}

complete -o nospace -S '/' -F  __get_dirs ccd
complete -o nospace -S '/' -F __get_dirs cin
complete -F __get_files cls
complete -F __get_con_names cinit
