#!/bin/bash

if [ $# != 3 ]; then
  echo "usage: $0 <cache-drive> <backing-pool> <percentage>"
  exit 1
fi

CACHE="${1}"
BACKING="${2}"
PERCENTAGE=${3}
PERCENT_END=$((100-$PERCENTAGE))

echo "FROM ($CACHE) TO ($BACKING) TIL $PERCENTAGE%"

set -o errexit
while [ $(df --output=pcent "${CACHE}" | grep -v Use | cut -d'%' -f1) -gt ${PERCENTAGE} ]
do
    FILE=$(find "${CACHE}" -type f -printf '%A@ %P\n' | \
                  sort | \
                  head -n 1 | \
                  cut -d' ' -f2-)
    test -n "${FILE}"
		PCT_REMAIN=$(df --output=pcent "${CACHE}" | grep -v Use | cut -d'%' -f1)
		PCT_PROG=$((100-$PCT_REMAIN))
		echo "MOVING ($PCT_PROG% OF $PERCENT_END%): ${FILE}"
    rsync -axqHAXWESR --preallocate --remove-source-files "${CACHE}/./${FILE}" "${BACKING}/"
done