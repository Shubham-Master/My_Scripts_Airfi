#!/bin/bash
iata=$1
while read -r box; do
  echo $box
done < <(curl -s "https://${API_USER}:${API_PASS}@airfi-disco.herokuapp.com/api/devices/customerCode/$iata" | jq -r '.[] | select((.isSuperProxy == true or .mode.name == "PROXY") and .purpose.name == "Production") | .serial')
