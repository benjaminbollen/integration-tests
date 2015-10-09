#! /bin/bash

# we only run integrations tests when we push to INTEGRATIONS_TEST_BRANCH
INTEGRATIONS_TEST_BRANCH="staging"
BRANCH=`git rev-parse --abbrev-ref HEAD`
if [ "$BRANCH" != "$INTEGRATIONS_TEST_BRANCH" ]; then
	echo "BRANCH=$BRANCH. We only run integrations tests for BRANCH=$INTEGRATIONS_TEST_BRANCH"
        exit 0
fi

if [ "$REPO_TO_TEST" == "" ]; then
       echo "must specify a $REPO_TO_TEST"
       exit 1
fi

if [ "$TEST_AGAINST_BRANCH" == "" ]; then
        echo "must specify a $TEST_AGAINST_BRANCH (this is the branch to be built for other dependencies of the tests, typically master or develop)$"
       exit 1
fi


REPOS=("eris-cli" "mint-client" "eris-db" "eris-db.js" "eris-contracts.js")

# grab all the repos except the one we're testing
for repo in "${REPOS[@]}"
do
	if [ "$repo" != "$REPO_TO_TEST" ];  then
		wd=$GOPATH/src/github.com/eris-ltd/$repo
		git clone https://github.com/eris-ltd/$repo $wd
		cd $wd; git checkout TEST_AGAINST_BRANCH
	fi
done


# do any preliminary setup
case $REPO_TO_TEST in
"eris-cli" )  # installed already by circle
	;;
"mint-client" )  cd $GOPATH/src/github.com/eris-ltd/eris-db; docker build -t eris/erisdb:$ERIS_VERISON -f ./DOCKER/Dockerfile .
	;; 
"eris-db" )  cd $GOPATH/src/github.com/eris-ltd/eris-db; docker build -t eris/erisdb:$ERIS_VERISON -f ./DOCKER/Dockerfile .
	;;
"eris-db.js" )  # ?
	;;  
"eris-contracts.js" )  # ?
	;;
*) 	echo "must specify a valid REPO_TO_TEST. Got: $REPO_TO_TEST."
	;;
esac

# now we can run integration tests.

# 1) mint-client
cd $GOPATH/src/github.com/eris-ltd/mint-client/DOCKER/eris-cli
./build.sh

# 2) mindy
cd $GOPATH/src/github.com/eris-ltd/mindy/test/porcelain
./build.sh


