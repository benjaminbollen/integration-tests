#!/bin/bash

# for booting new machines
MACHINE_INDEX=100 # TODO random string
SWARM="dca1"
MACHINE_NAME="eris-test-$SWARM-$MACHINE_INDEX"

# ----------------------------------------------------------------------------
# Functions we'll need for checking machines/swarms and running the tests

ifExit(){
	if [ $? -ne 0 ]; then
		echo "ifExit"
		echo "$1"
		exit 1
	fi
}


new_machine(){
	echo "Create new machine named $MACHINE_NAME"
	docker-machine create --driver amazonec2 $MACHINE_NAME
	#ifExit "failed to create new machine $MACHINE_NAME"

	echo "Machine started. Connecting ..."
	eval $(docker-machine env $MACHINE_NAME)
	#ifExit "failed to connect to $MACHINE_NAME"
}

connect() {
  echo "Starting Machine."
  docker-machine start $machine 1>/dev/null
  until [[ $(docker-machine status $machine) == "Running" ]] || [ $ping_times -eq 10 ]
  do
     ping_times=$[$ping_times +1]
     sleep 3
  done
  if [[ $(docker-machine status $machine) != "Running" ]]
  then
    echo "Could not start the machine. Exiting this test."
    exit 1
  else
    echo "Machine Started."
    # XXX: why?
    docker-machine regenerate-certs -f $machine 2>/dev/null
  fi
  sleep 5
  echo "Connecting to Machine."
  eval "$(docker-machine env $machine)" &>/dev/null
  echo "Connected to Machine."
  echo ""
  clear_stuff
}

clear_stuff() {
  echo "Clearing images and containers."
  set +e
  docker rm $(docker ps -a -q) &>/dev/null
  docker rmi $(docker images -q) &>/dev/null
  set -e
  echo ""
}


set_machine() {
  echo "eris-test-$swarm-$ver"
}

check_swarm() {
  machine=$(set_machine)

  if [[ $(docker-machine status $machine) == "Running" ]]
  then
    echo "Machine Running. Switching Swarm."
    if [[ "$swarm" == "$swarm_back" ]]
    then
      swarm=$swarm_prim
    else
      swarm=$swarm_back
    fi

    machine=$(set_machine)
    if [[ $(docker-machine status $machine) == "Running" ]]
    then
      echo "Backup Swarm Machine Also Running."
      return 1
    fi
  else
    echo "Machine not Running. Keeping Swarm."
    machine=$(set_machine)
  fi
}

reset_swarm() {
  swarm=$swarm_prim
}

log_results() {
  if [ "$test_exit" -eq 0 ]
  then
    machine_results+=("$machine is Green!")
  else
    machine_results+=("$machine is Red.  :(")
  fi
}

# ----------------------------------------------------------------------------
# Set Parameters

if [ "$#" -lt 1 ]; then
	    echo "Must provide at least the location of the test folder"
fi

test_folder=$1

source $test_folder/params.sh

# ----------------------------------------------------------------------------
# Set definitions and defaults

# Where are the Things 
if [ "$CIRCLE_BRANCH" ]
then
  repo=${GOPATH%%:*}/src/github.com/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}
  circle=true
else
  repo=$GOPATH/src/$base
  circle=false
fi
branch=${CIRCLE_BRANCH:=master}
branch=${branch/-/_}


# ---------------------------------------------------------------------------
# Get the machine definitions, connect to one, build the images

echo "Hello! I'm the testing suite for eris."


if [[ $2 == "" ]]; then
	NEW_MACHINE="true"
	new_machine
	echo "Sucessfully connected to new docker machine: $MACHINE_NAME"
elif [[ $2 != "local" ]]; then
	echo "Getting machine definition files sorted so we can connect to $2"
	if [ "$circle" = true ]; then
	  docker pull quay.io/eris/test_machines &>/dev/null
	  docker run --name $machine_definitions quay.io/eris/test_machines &>/dev/null
	  rm -rf .docker &>/dev/null
	  docker cp $machine_definitions:/home/eris/.docker $HOME &>/dev/null
	else
	  docker run --name $machine_definitions quay.io/eris/test_machines &>/dev/null
	fi

	MACHINE_NAME=$2
	eval $(docker-machine env $2)
fi

echo ""
echo "Building tests for $repo"
strt=`pwd`
cd $repo
export repo
$build_script 

# logging the exit code
test_exit=$(echo $?)
machine=$MACHINE_NAME
log_results

# ---------------------------------------------------------------------------
# Cleaning up

echo ""
echo ""
echo "Your summary good human...."
printf '%s\n' "${machine_results[@]}"
echo ""
echo ""
if [[ "$NEW_MACHINE" == "true" ]];
then
	echo "Removing $MACHINE_NAME"
	docker-machine rm $MACHINE_NAME
	ifExit "error removing machine $MACHINE_NAME"
	echo ""
	echo ""
fi
echo "Done. Exiting with code: $test_exit"
cd $strt
exit $test_exit
