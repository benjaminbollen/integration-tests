
# ----------------------------------------------------------------------------
# Functions we'll need for checking machines/swarms and running the tests

rand8(){
	# NOTE: names starting with an integer cause trouble
	cat /dev/urandom | tr -dc 'a-zA-Z' | fold -w 8 | head -n 1
}
export -f rand8

ifExit(){
	if [ $? -ne 0 ]; then
		echo "ifExit"
		echo "$1"
		exit 1
	fi
}

export -f ifExit

clear_stuff() {
  echo "Clearing images and containers."
  set +e
  docker rm $(docker ps -a -q) &>/dev/null
  docker rmi $(docker images -q) &>/dev/null
  set -e
  echo ""
}

export -f clear_stuff

# create_connect_machine(machine_name)
create_connect_machine(){
	create_machine $1
	connect_machine $1
}

export -f create_connect_machine

connect_machine(){
	echo "* connecting to machine $1"
	eval $(docker-machine env $1)
	ifExit "failed to connect to $1"
}

export -f connect_machine

create_machine(){
	docker-machine create --driver amazonec2 $1
	ifExit "failed to create new machine $1"
}

export -f create_machine

start_connect_machine() {
  echo "Starting Machine: $1"
  docker-machine start $1 1>/dev/null
  until [[ $(docker-machine status $1) == "Running" ]] || [ $ping_times -eq 10 ]
  do
     ping_times=$[$ping_times +1]
     sleep 3
  done
  if [[ $(docker-machine status $1) != "Running" ]]
  then
    echo "Could not start the machine. Exiting this test."
    exit 1
  else
    echo "Machine Started."
    # docker-machine regenerate-certs -f $1 
  fi
  sleep 5
  echo "Connecting to Machine."
  eval $(docker-machine env $1)
  echo "Connected to Machine."
  echo ""
  clear_stuff
}



export -f start_connect_machine

# params (machine, test_exit)
log_results() {
  if [[ "$2" == "0" ]]
  then
    echo "$1 is Green!" >> $RESULTS_FILE
  else
    echo "$1 is Red. :(" >> $RESULTS_FILE
  fi
}

export -f log_results

