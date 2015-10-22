#! /bin/bash

# this exists as its own script because it needs isolated environment variables for connecting to docker


# runIntegrationTest(machine, repo, build_script, log folder)
runIntegrationTest(){
    machine=$1
    thisRepo=$2
    build_script=$3
    log_folder=$4
    base=$(basename $thisRepo)
    echo "* integration test $thisRepo ($build_script) on machine $machine"
    if [[ "$INTEGRATION_TESTS_CONCURRENT" == "true" ]]; then
	    connect_machine $machine
	    if [[ "$INTEGRATION_TESTS_REGENERATE_CERTS" == "true" ]]; then
		yes | docker-machine regenerate-certs $1
	    fi

	    echo "... run pre events for $base"
	    setupForTests > "$log_folder/$base-setup"
    fi

    echo ""
    echo "... building/running tests for $thisRepo using $build_script"
    strt=`pwd`
    cd $GOPATH/src/$thisRepo
    # build and run the tests
    $build_script > $log_folder/$base

    # logging the exit code
    test_exit=$?
    log_results "$thisRepo ($build_script)" $test_exit

    echo " ... done tests for $thisRepo ($build_script) !"
    if [[ "$test_exit" == 0 ]]; then 
	echo "****** PASS ******"
    else
	echo "****** FAIL ******"
    fi
}

# runLocalTest(machine, build_script, logFolder)
runLocalTest(){
    mach=$1
    bscript=$2
    logFolder=$3
    echo "* local test on $1"
    if [[ "$INTEGRATION_TESTS_CONCURRENT" == "true" ]]; then
	    connect_machine $mach
	    if [[ "$INTEGRATION_TESTS_REGENERATE_CERTS" == "true" ]]; then
		yes | docker-machine regenerate-certs $mach
	    fi

	    echo "... run pre events for $TOOL (local)"
	    setupForTests > "$logFolder/$TOOL-local-setup"
    fi

    echo "... building/running tests for $TOOL (local) using $bscript"
    $bscript > "$logFolder/$TOOL-local"
    test_exit=$?
    log_results "$TOOL (local)" $test_exit
    echo " ... done tests for $TOOL (local)"
    if [[ "$test_exit" == 0 ]]; then 
	echo "****** PASS ******"
    else
	echo "****** FAIL ******"
    fi
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
