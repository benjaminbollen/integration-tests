#! /bin/bash

# this exists as its own script because it needs isolated environment variables for connecting to docker


# runIntegrationTest(machine, repo, build_script, log folder)
runIntegrationTest(){
    machine=$1
    thisRepo=$2
    build_script=$3
    log_folder=$4
    echo "* integration test $thisRepo ($build_script) on machine $machine"
    connect_machine $machine

    base=$(basename $thisRepo)

    echo "... run pre events for $base"
    setupForTests > "$log_folder/$base-setup"

    echo ""
    echo "... building/running tests for $thisRepo using $build_script"
    strt=`pwd`
    cd $GOPATH/src/$thisRepo
    # build and run the tests
    $build_script > $log_folder/$base

    # logging the exit code
    test_exit=$(echo $?)
    log_results $machine $test_exit

    echo " ... done tests for $thisRepo ($build_script) !"
}

# runLocalTest(machine, build_script, logFolder)
runLocalTest(){
    echo "* local test on $1"
    connect_machine $1

    echo "... run pre events for $TOOL (local)"
    setupForTests > "$3/$TOOL-local-setup"

    echo "... building/running tests for $TOOL (local) using $2"
    $2 > "$3/$TOOL-local"
    test_exit=$(echo $?)
    log_results $1 $test_exit

    echo " ... done tests for $TOOL (local)"
}

# params
# ("integration", <machine>, <repo>, <build_script>, <logFolder>)
# or ("local", <machine>, <path to build script>)

if [[ "$1" == "integration" ]]; then
	runIntegrationTest $2 $3 $4 $5
elif [[ "$1" == "local" ]]; then
	runLocalTest $2 $3 $4
else
	echo "unknown test type: $1. must be 'integration' or 'local'"
	exit 1
fi
