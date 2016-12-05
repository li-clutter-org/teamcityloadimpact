#!/bin/bash
# Run Load Impact test from bash

# Load Impact test id
testId="3557507"

# API_KEY from your Load Impact account
# Don't forget to keep the : at the end
API_KEY="5a437e1c5a78984e5da038bb0ab68438203d476849e96284bd5170c2450f798d"

uri="https://api.loadimpact.com/v2/test-configs/$testId/start"

echo "##teamcity[testStarted name='Load Impact performance test']"
echo "##teamcity[progressMessage 'Kickoff performance test']"

OUT=$(curl -qSfsw "\n%{http_code}" -u $API_KEY: -X POST https://api.loadimpact.com/v2/test-configs/$testId/start)

status=`echo  "${OUT}" | tail -n1`

# Status 201 expected, 200 is just a current running test id
if [[ $status -ne 201 ]] ; then
  perc="Could not start test $testId : $status \n $resp.Content"
  echo "##teamcity[buildProblem description='"${perc}"']"
  exit 0
else
  tid=`echo "${OUT}" | head -n1 | jq '.id'`
fi

# Until 5 minutes timout or status is running 

t=0
status_text="\"NOT_YET\""
until [ $status_text == "\"Running\"" ]; do
  sleep 10s
  OUT=$(curl -qSfsw '\n%{http_code}' -u $API_KEY: -X GET https://api.loadimpact.com/v2/tests/$tid/)
  status_text=`echo  "${OUT}" | head -n1 | jq '.status_text'`
  ((t=t+10))

  if [[ $t -gt 300 ]] ; then
    echo "##teamcity[buildProblem description='Timeout - test start > 5 min']" 
    exit 0
  fi
done

echo "##teamcity[progressMessage 'Performance test running']"

# wait until completed

maxVULoadTime=0
percentage=0
until [[ $(echo "$percentage==100" | bc -l) == 1 ]]; do
  sleep 30s

  # Get percent completed
  OUT=$(curl -qSfs -u $API_KEY: -X GET https://api.loadimpact.com/v2/tests/$tid/results?ids=__li_progress_percent_total)

  percentage=`echo "${OUT}" | jq '.__li_progress_percent_total | max_by(.value)| .value'`

  echo  "##teamcity[progressMessage 'Percentage completed $percentage']"

  # Get VU Load Time
  OUT=$(curl -qSfs -u $API_KEY: -X GET https://api.loadimpact.com/v2/tests/$tid/results?ids=__li_user_load_time)

  maxVULoadTime=`echo "${OUT}" | jq '.__li_user_load_time | max_by(.value) | .value'`

  if [[ $(echo "$maxVULoadTime>1000" | bc -l) == 1 ]] ; then 
    perc="VU Load Time exceeded limit of 1 sec: $maxVULoadTime"
    echo "##teamcity[buildProblem description='$perc']"
    exit 0
  fi
done

#show results
echo "##teamcity[progressMessage 'Show results']"
echo "Max VU Load Time: $maxVULoadTime"
echo "Full results at https://app.loadimpact.com/test-runs/$tid"

echo "##teamcity[testFinished name='Load Impact performance test']"