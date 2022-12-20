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

CACHE="${1}"
BACKING="${2}"

if [ ! -d "$CACHE" ]; then
  echo "\"$CACHE\" is not a valid directory!"
	exit 1
fi

if [ ! -d "$BACKING" ]; then
  echo "\"$BACKING\" is not a valid directory!"
	exit 1
fi

# TODO: make argument?
NUM_JOBS=16

PERCENTAGE=${3}
PCT_USED=$(df --output=pcent "${CACHE}" | grep -v Use | cut -d'%' -f1 | xargs)
if [[ PCT_USED -le ${PERCENTAGE} ]]; then
	echo "Already at or below $PERCENTAGE%, exiting."
	exit 0
fi

echo "Moving from ($CACHE) to ($BACKING) til usage <= $PERCENTAGE% (cur usage: $PCT_USED%)"


# FILE_LIST=$(find ${CACHE} -printf '%A@ %P\n' 2>/dev/null | sort -n |  cut -d' ' -f2-)
# Dump list to disk
find ${CACHE} -printf '%A@ %P\n' 2>/dev/null | sort -n |  cut -d' ' -f2- > mover_files.tmp

# Args:
# $1 - file to move
# $2 - cache dir
# $3 - backing dir
run_move() {
	# echo "Moving \"$1\" from \"$2\" to \"$3\"
	# PCT_USED=$(df --output=pcent "${2}" | grep -v Use | cut -d'%' -f1)
	# if [[ PCT_USED -le ${4} ]]; then
	# 	exit 1 # fail job, already complete
	# fi
	rsync -axqHAXWESR --preallocate --remove-source-files "$2$1" "$3"
}

# Args:
# $1 - cache dir
# $2 - usage percentage to stop at
#
# Exiting non-zero signals to 'parallel' to stop creating jobs.
# To let remaining jobs continue running, use 'exit 1'
# To kill remaining jobs, use 'exit 2'
percentage_reached() {
	PCT_USED=$(df --output=pcent "${1}" | grep -v Use | cut -d'%' -f1)
	if [[ PCT_USED -le ${2} ]]; then
		exit 2 # set per above to change job behavior
	fi
	exit 0
}

export -f percentage_reached
export -f run_move

### Notes ###
# Progress isn't too useful as it won't count forward. It only knows about jobs it has started.
# the '--limit'

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