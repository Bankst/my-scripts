#!/bin/bash

# Takes advantage of GNU Parallel
# https://www.gnu.org/software/parallel/man.html

if [ $# != 3 ]; then
  echo "Usage: $0 <cache mount> <backing mount> <end usage percentage>"
  exit 1
fi

if [ -z "$1" ]; then
	echo "No cache mount argument supplied!"
	echo "Usage: $0 <cache mount> <backing mount> <end usage percentage>"
	exit 1
fi

if [ -z "$2" ]; then
	echo "No backing mount argument supplied!"
	echo "Usage: $0 <cache mount> <backing mount> <end usage percentage>"
	exit 1
fi

if [ -z "$3" ]; then
	echo "No usage percentage argument supplied!"
	echo "Usage: $0 <cache mount> <backing mount> <end usage percentage>"
	exit 1
fi

CACHE="${1%/}"
BACKING="${2%/}"

if [ ! -d "$CACHE" ]; then
  echo "\"$CACHE\" is not a valid directory!"
	exit 1
fi

if [ ! -d "$BACKING" ]; then
  echo "\"$BACKING\" is not a valid directory!"
	exit 1
fi

CACHE=$(realpath $CACHE)
BACKING=$(realpath $BACKING)

# TODO: make argument?
NUM_JOBS=16

PERCENTAGE=${3}
PCT_USED=$(df --output=pcent "${CACHE}" | grep -v Use | cut -d'%' -f1 | xargs)

if [[ PERCENTAGE -eq 0 ]]; then
	echo "Moving everything from ($CACHE) to ($BACKING)"
else
	if [[ PCT_USED -le ${PERCENTAGE} ]]; then
		echo "Already at or below $PERCENTAGE%, exiting."
		exit 0
	fi
	echo "Moving from ($CACHE) to ($BACKING) til usage <= $PERCENTAGE% (cur usage: $PCT_USED%)"
fi

# FILE_LIST=$(find ${CACHE} -printf '%A@ %P\n' 2>/dev/null | sort -n |  cut -d' ' -f2-)
# Dump list to disk
find ${CACHE} -printf '%A@ %P\n' 2>/dev/null | sort -n |  cut -d' ' -f2- > mover_files.tmp

# Args:
# $1 - file to move
# $2 - cache dir
# $3 - backing dir
run_move() {
	local FILE=$1
	local CACHE=$2
	local BACKING=$3
	# echo "Moving \"$FILE\" from \"$CACHE\" to \"$BACKING\""
	# echo "Calling rsync -axqHAXWESR --preallocate --remove-source-files \"${CACHE}/./${FILE}\" \"${BACKING}/\""
	rsync -axqHAXWESR --preallocate --remove-source-files "${CACHE}/./${FILE}" "${BACKING}/"
}

# Args:
# $1 - cache dir
# $2 - usage percentage to stop at
#
# Exiting non-zero signals to 'parallel' to stop creating jobs.
# To let remaining jobs continue running, use 'exit 1'
# To kill remaining jobs, use 'exit 2'
percentage_reached() {
	local TARGET_PCT=$1
	PCT_USED=$(df --output=pcent "${TARGET_PCT}" | grep -v Use | cut -d'%' -f1)
	if [[ PCT_USED -le ${2} && TARGET_PCT -ne 0 ]]; then
		exit 2 # set per above to change job behavior
	fi
	exit 0
}

export -f percentage_reached
export -f run_move

### Notes ###
# Progress isn't too useful as it won't count forward. It only knows about jobs it has started.

parallel \
  --progress \
	-a mover_files.tmp \
	--limit "percentage_reached $CACHE $PERCENTAGE" \
	--halt soon,fail=5 \
	-j $NUM_JOBS \
	run_move {} $CACHE $BACKING $PERCENTAGE \
	3> >(perl -ne '$|=1;chomp;printf"%.'$COLUMNS's\r",$_." "x100')

echo "Reached target percentage, exiting."
rm mover_files.tmp
