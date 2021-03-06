#!/bin/bash

# source variables values
# get target variables
# get target variable types
vault=vault.yml
target=target.yml
src=source.yml

to_property_paths() {
  spruce json ${1} | jq -r '
    def leaves: if type == "array" or type == "object" then .[] | leaves else . end;

    .instance_groups + .addons | map(.jobs | map(.name as $n | (.properties | (path(leaves) as $p | [{
      key: ([$n] + ($p | [.[]|tostring])|join("/")),
      value: (getpath($p) | tostring | sub("\n"; ""; "g"))
      }])
      ))) | flatten | from_entries
  '
}

to_vault_paths() {
    spruce json ${1} | jq -r '
    def leaves: if type == "array" or type == "object" then .[] | leaves else . end;

    to_entries | map(.key as $n | (.value | (path(leaves) as $p | [{
      key: ([$n] + ($p | [.[]|tostring])|join(":")),
      value: (getpath($p) | tostring | sub("\n"; ""; "g"))
      }])
      )) | flatten | from_entries
  '
}

source_paths=$(to_property_paths ${src})
target_paths=$(to_property_paths ${target} |
                   jq 'to_entries | map(select((.value | type == "string") and (.value | contains("((")))) | from_entries')
vault_paths=$(to_vault_paths ${vault} | sed 's@secret/ci/baseline/cf/@@g')

get_path_for_value() {
    jq -r --arg v "${1}" --arg i "${2}" 'to_entries | map(select(.value == $v)) |
       sort_by(.key | test("/d+/")) | reverse [$i|tonumber].key'
}

get_value_for_path() {
    jq -r --arg p "${1}" '.[$p]'
}

get_src_path() {
    i=0
    while true; do
        path=$(echo ${target_paths} | get_path_for_value "${1}" "${i}")
        if [[ "${path}" == "null" ]]; then
            echo "TODO"
            break
        fi
        value=$(echo ${source_paths} | get_value_for_path "${path}")
        src_path=$(echo ${vault_paths} | get_path_for_value "${value}" "0")
        if [[ "${src_path}" != "null" ]]; then
            echo "${src_path}"
            break
        fi
        ((i++))
    done

}

echo 'vault_prefix: (( grab $VAULT_PREFIX ))'
echo 'credhub_prefix: (( grab $CREDHUB_PREFIX ))'
echo "credentials:"
for variable in $(spruce json ${target} | jq -r -c '.variables[] | @base64'); do
    _jq() {
        echo ${variable} | base64 --decode | jq -r ${1}
    }
    name=$(_jq '.name')
    case $(_jq '.type') in
        password)
            path=$(get_src_path "((${name}))")
            echo "- name: (( concat credhub_prefix \"/${name}\" ))"
            echo "  type: password"
            echo "  value: ((vault vault_prefix \"${path}\"))"
            ;;

        certificate)
            cert_path=$(get_src_path "((${name}.certificate))")
            key_path=$(get_src_path "((${name}.private_key))")
            ca="    ca_name: (( concat credhub_prefix \"/$(_jq '.options.ca')\" ))"
            if [[ "$(_jq .options.is_ca)" == "true" ]]; then
                scope="$(echo ${name} | sed -e 's/_ca$//g' -e 's/^service_//g')"
                cert_path="${scope}/certs/ca:certificate"
                key_path="${scope}/certs/ca:key"
                options_ca="$(_jq .options.ca)"
                if [[ "${options_ca}" != "null" ]]; then
                    ca="    ca_name: (( concat credhub_prefix \"/${options_ca}\" ))"
                else
                    ca="    ca: ((vault vault_prefix \"${cert_path}\" ))"
                fi
            fi
            echo "- name: (( concat credhub_prefix \"/${name}\" ))"
            echo "  type: certificate"
            echo "  value:"
            echo "    certificate: ((vault vault_prefix \"${cert_path}\"))"
            echo "    private_key: ((vault vault_prefix \"${key_path}\"))"
            echo "${ca}"
            ;;

        rsa)
            key_path=$(get_src_path "((${name}.private_key))")
            pub_path=$(echo "${key_path}" | sed -e 's/private$/public/g')
            echo "- name: (( concat credhub_prefix \"/${name}\" ))"
            echo "  type: rsa"
            echo "  value:"
            echo "    public_key: ((vault vault_prefix \"${pub_path}\"))"
            echo "    private_key: ((vault vault_prefix \"${key_path}\"))"
            ;;

        ssh)
            key_path=$(get_src_path "((${name}.private_key))")
            pub_path=$(echo "${key_path}" | sed -e 's/private$/public/g')
            echo "- name: (( concat credhub_prefix \"/${name}\" ))"
            echo "  type: ssh"
            echo "  value:"
            echo "    public_key: ((vault vault_prefix \"${pub_path}\"))"
            echo "    private_key: ((vault vault_prefix \"${key_path}\"))"
            ;;
    esac
done
