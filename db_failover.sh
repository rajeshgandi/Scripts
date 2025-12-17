#!  /bin/bash

usage()
{
echo
cat << EOF
   Usage: $0  <parameter and values are specified below>
   Options:
        -s swich desc (failover-us-east, failover-us-central)
        -h help
Example: ./failover -s failover-eu-central
Example: ./failover -s failover-us-east

EOF
exit 1
}

while getopts s:h: param ; do
   case $param in
        s) SWITCH=$OPTARG;;
        :) usage;;
        h) usage;;
   \?) usage;;
        esac
done

if [ $# -eq 0 ]; then
  usage;
fi
export NOW=$(date +"%m%d%Y%H%M")
export BASE=$(pwd)


echo " --------"
#. ${BASE}/.aws_configure
aws sts get-caller-identity
if [ $? -ne 0 ]; then
  echo "INFO::::... the aws credentials are not found. Please use awslogin to set the credentials"
  exit 1
else
  echo "INFO::::....aws_configure found"
fi

case "${SWITCH}" in
   failover-eu-central) export SEC_CLUSTER="clitest-eu-cluster"
                     export GLOBAL="clitest-global"
                     export SEC_REGION="eu-central-1"
                     export PRI_REGION="us-east-1"
                     export PRI_CLUSTER="clitest-cluster";;
   failover-us-east) export SEC_CLUSTER="clitest-cluster"
                     export GLOBAL="clitest-global"
                     export SEC_REGION="us-east-1"
                     export PRI_REGION="eu-central-1"
                     export PRI_CLUSTER="clitest-eu-cluster";;
    *)  echo " Invalid input ${SWITCH} " ;;
esac

export AWS_DEFAULT_REGION=${PRI_REGION}
echo "INFO::::...Running prefailover snapshot for ${PRI_CLUSTER} cluster"
aws rds create-db-cluster-snapshot --db-cluster-identifier ${PRI_CLUSTER} --db-cluster-snapshot-identifier ${PRI_CLUSTER}-prefailover-snapshot-${NOW}
echo "INFO::::...checking if cluster is available"

time=0
sleep 30
CLUSTER_STATUS=$(aws rds describe-db-clusters --db-cluster-identifier ${PRI_CLUSTER} --query DBClusters[*].Status  --output text)
while [ "${CLUSTER_STATUS}" != "available" ]
do
    CLUSTER_STATUS=$(aws rds describe-db-clusters --db-cluster-identifier ${PRI_CLUSTER} --query DBClusters[*].Status  --output text)
    if [ $CLUSTER_STATUS = "available" ]; then
                echo "INFO::::...RDS cluster is available"
    else
                echo "INFO::::...Waiting for prefailover backup to complete"
                sleep 30
                echo $time  "second(s) Elapsed"
                time=$((time + 30))
    fi
done

echo "INFO::::...prefailover backup finished"

export AWS_DEFAULT_REGION=${SEC_REGION}
export ARN=$(aws rds describe-db-clusters --db-cluster-identifier ${SEC_CLUSTER} --query DBClusters[*].DBClusterArn  --output text)
echo "INFO::::...checking if the cluster health-status"
 STATUS=$(aws rds describe-db-clusters --db-cluster-identifier ${SEC_CLUSTER} --query DBClusters[*].Status  --output text)

if [ ${STATUS} = 'available' ]; then
    echo  "${SEC_CLUSTER} cluster is AVAILABLE"
 else
    echo  "ERROR: the ${SEC_CLUSTER}is not avaliable for this operation"
        exit 1
fi
echo "INFO::::...starting failover ( ${SEC_CLUSTER} )  in $REGION"
  aws rds failover-global-cluster \
           --region ${SEC_REGION} \
           --global-cluster-identifier ${GLOBAL} \
           --target-db-cluster-identifier ${ARN}

sleep 30
time=0
CLUSTER_STATUS=$(aws rds describe-db-clusters --db-cluster-identifier ${SEC_CLUSTER} --query DBClusters[*].Status  --output text)
while [ "${CLUSTER_STATUS}" != "available" ]
do
    CLUSTER_STATUS=$(aws rds describe-db-clusters --db-cluster-identifier ${SEC_CLUSTER} --query DBClusters[*].Status  --output text)
    if [ $CLUSTER_STATUS = "available" ]; then
    echo "INFO::::...cluster failover successful...... cluster is available"
    else
    echo "INFO::::...waiting for cluster to failover "
    sleep 30
    echo $time  "second(s) Elapsed"
    time=$((time + 30))
    fi
done

 echo "INFO::::...${SEC_CLUSTER} has been successfully failover to ${SEC_REGION}"
 echo "INFO::::...failover job completed."

exit 0
