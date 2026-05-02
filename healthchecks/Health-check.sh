#!/bin/bash
set -euo pipefail  #This command is used to Exit immediately if a command fails, treat unset variables as error and catch fail in piped commands

echo "This is a bash script used to check the health status of the docker containers"
# variables to be used
expected=$(docker compose config --services | wc -l)
running=$(docker compose ps --status running -q | wc -l)

echo "─────────────────────────────────────────"
# First we check the running containers before the checking the health status
runningChecks(){
  if [ "$expected" -eq "$running" ]; then
        echo "THESE ARE THE RUNNING CONTAINERS"
        docker compose ps --status running
        echo "ALL DOCKER CONTAINERS ARE RUNNING"
  else 
    echo "NOT ALL CONTAINERS ARE RUNNING......"
    echo "LOOKING FOR EXITED CONTAINERS....."
    docker compose ps --status exited
    echo "LOOKING FOR DEAD CONTAINERS....."
    docker compose ps --status dead
    echo "LOOKING FOR PAUSED CONTAINERS....."
    docker compose ps --status paused
    echo "LOOKING FOR RESTARTING CONTAINERS....."
    docker compose ps --status restarting

    fi
    echo "─────────────────────────────────────────"
}
echo " " #this is used for spacing 

# After checking the running containers we check the health status of each container
healthChecks(){
    echo "THE HEALTH CHECKS FOR EACH CONTAINER......"
    for container_id in $(docker compose ps -q); do
        info=$(docker inspect --format='{{.Name}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' $container_id)
        read name status <<< "$info" #This is used to iterate and check the health status of each container showing the name and container
        if [ "$status" == "healthy" ]; then 
            echo "THE CONTAINER $name ($container_id) is healthy"
        elif [ "$status" == "unhealthy" ]; then
            echo "THE CONTAINER $name ($container_id) is unhealthy"
        else #This is used to check if the container health status is empty 
            echo "THE CONTAINER $name ($container_id) has no health checks"

        fi
    done
    echo "─────────────────────────────────────────"
}


runningChecks
healthChecks
 