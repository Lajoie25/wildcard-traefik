#!/bin/bash

# reads the acme.json file
json=$(cat /app/acme.json)
array=()
star_array=()
wildcard=$(echo "$json" | jq -r '.[].Certificates[].domain.main' | grep '*')
folder_cert=/app/certificates

if [ -d "$folder_cert" ]; then
  echo "$folder_cert directory exists."
  rm -R $folder_cert && echo "Old $folder_cert is removed"
else
  echo "$folder_cert directory does not exist."
fi

mkdir -p $folder_cert && echo "$folder_cert is created"

# generer les certs et keys
export_cer_key() {
  echo "$json" | jq -r '.[].Certificates[] | select(.domain.main == "'$1'") | .certificate' | base64 -d >certificates/$2.cer
  echo "$json" | jq -r '.[].Certificates[] | select(.domain.main == "'$1'") | .key' | base64 -d >certificates/$2.key
}

# On génère le pfx
export_pfx() {
  openssl pkcs12 -export -out certificates/$1.pfx -inkey certificates/$1.key -in certificates/$1.cer -passout pass:
}

# On supprime les vieux certificat
remove_old_cert() {
  echo "$json" | jq 'del(.[].Certificates[] | select(.domain.main == "'$1'"))' >acme.json
  echo "$1 removed"
}

waiting() {
  count=0
  total="$1"
  start=$(date +%s)
  while [ $count -lt $total ]; do
    sleep 0.5
    cur=$(date +%s)
    count=$(($count + 1))
    pd=$(($count * 73 / $total))
    runtime=$(($cur - $start))
    estremain=$((($runtime * $total / $count) - $runtime))
    printf "\r%d.%d%% complete ($count of $total) - est %d:%0.2d remaining!\e[K" $(($count * 100 / $total)) $((($count * 1000 / $total) % 10)) $(($estremain / 60)) $(($estremain % 60))
  done
  echo '   '
}

get_wildcard_cert() {
  for domain in $(echo "$json" | jq -r '.[].Certificates[].domain.main' | grep '*'); do
    star="${domain/'*.'/star_}"
    array+=("$domain; ")
    star_array+=("$star")
  done
}

if [[ $wildcard ]]; then
  get_wildcard_cert

  for domain in $(echo "$json" | jq -r '.[].Certificates[].domain.main' | grep '*'); do
    remove_old_cert "$domain"
  done
  docker restart traefik >> /dev/null
  echo 'regenerate new certificates, Please wait!'
  sleep 7 &
  PID=$!
  waiting 10
  wait $PID

  for domain in $(echo "$json" | jq -r '.[].Certificates[].domain.main' | grep '*'); do
    star="${domain/'*.'/star_}"
    export_cer_key "$domain" "$star"
    export_pfx "$star"
  done
  # shellcheck disable=SC2145
  echo "Done, you can download your wildcard certificates: ${star_array[@]}"
else
  echo 'No Wildcard certificates detected'
fi
