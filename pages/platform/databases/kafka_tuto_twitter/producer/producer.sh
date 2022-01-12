#!/bin/bash

# Pre-requisites:
# curl, jq, kcat

# Load Twitter API properties
. TWITTER_API_properties.sh

# Load this producer properties
#   query : the query you pass to the Twitter API
#   LOGLEVEL: If you want logs or not
. PRODUCER_properties.sh

# Log function
log() {
if [ "$LOGLEVEL" = "INFO" ];
then
	echo "INFO - $(date '+%Y-%m-%d|%H:%M:%S') - $1"
fi
}

# urldecode & urlencode functions
# Source : https://jonlabelle.com/snippets/view/shell/url-encode-and-decode-values-in-bash
urlencode() {
    # urlencode <string>
 
    old_lc_collate=$LC_COLLATE
    LC_COLLATE=C

    local length="${#1}"
    for (( i = 0; i < length; i++ )); do
        local c="${1:$i:1}"
        case $c in
            [a-zA-Z0-9.~_-]) printf '%s' "$c" ;;
            *) printf '%%%02X' "'$c" ;;
        esac
    done

    LC_COLLATE=$old_lc_collate
}
urldecode() {
    # urldecode <string>

    local url_encoded="${1//+/ }"
    printf '%b' "${url_encoded//%/\\x}"
}

# Query
urlEncodedQuery=$(urlencode "$query")

log "query: $query"

# datetimes limits (UTC, format +%Y-%m-%dT%H:%M:%SZ)
# start_time: now - 2 min / end_time:   now - 1 min
start_time=$(date -u -v-2M '+%Y-%m-%dT%H:%M:%SZ')
#start_time=$(date -u -v-1d '+%Y-%m-%dT%H:%M:%SZ')
end_time=$(date -u -v-1M '+%Y-%m-%dT%H:%M:%SZ')

log "start_time: $start_time"
log "end_time:   $end_time"
log "max_results: $max_results"

# Build Request
req="https://api.twitter.com/2/tweets/search/recent?query=$urlEncodedQuery&tweet.fields=created_at&max_results=100&start_time=$start_time&end_time=$end_time&expansions=author_id&user.fields=created_at"

# Response
resp=$(curl -s "$req" -H "Authorization: Bearer $BEARER_TOKEN")

# Result count
nb_result=$(echo $resp | jq '.meta|.result_count')

# If result
if [ $nb_result -gt 0 ] 
then

log "Request returns $nb_result Twits"

# Build one json per response and publish to Kafka
# Json format:
# {
#  "id": "",
#  "created_at": "",
#  "text": "",
#  "author": {
#    "username": "",
#    "created_at": "",
#    "name": "",
#    "id": ""
#  }
#} 
echo $resp |jq '.data[]|.id' | \
while read i;\
 do
 id="${i//\"/}";\
 author_id=$(echo $resp | jq --arg twid $id '.data[] | select(.id==($twid)) | .author_id');\
 created_at=$(echo $resp | jq --arg twid $id '.data[] | select(.id==($twid)) | .created_at');\
 text=$(echo $resp | jq --arg twid $id '.data[] | select(.id==($twid)) | .text');\
 user=$(echo $resp | jq --arg aid ${author_id//\"/} '.includes[][] | select(.id==($aid))');\
 json="$(echo "{\"id\":$i,\"created_at\":$created_at,\"text\":$text,\"author\":$user}" | jq )";\
 # Push json to kafka
 log "$json";\
 echo $json | kcat -v -F kafkacat.conf -P -t mytopic;\
 done

else
log "Request returns no response"
fi
