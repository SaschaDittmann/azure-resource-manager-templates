# Install a Kafka cluster on RedHat Virtual Machines using Custom Script Linux Extension

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FSaschaDittmann%2Fazure-resource-manager-templates%2Fmaster%2Fkafka-on-redhat%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>
<a href="http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2FSaschaDittmann%2Fazure-resource-manager-templates%2Fmaster%2Fkafka-on-redhat%2Fazuredeploy.json" target="_blank">
    <img src="http://armviz.io/visualizebutton.png"/>
</a>

Apache Kafka is publish-subscribe messaging rethought as a distributed commit log.

Kafka is designed to allow a single cluster to serve as the central data backbone for a large organization. It can be elastically and transparently expanded without downtime. Data streams are partitioned and spread over a cluster of machines to allow data streams larger than the capability of any single machine and to allow clusters of co-ordinated consumers

Kafka has a modern cluster-centric design that offers strong durability and fault-tolerance guarantees.

This template deploys a Kafka cluster on the RedHat virtual machines. This template also provisions a storage account, virtual network, availability sets, public IP addresses and network interfaces required by the installation.
The template might also creates 1 publicly accessible VM acting as a "jumpbox" and allowing to ssh into the Kafka nodes for diagnostics or troubleshooting purposes, if not disabled.

How to Run the scripts
----------------------

You can use the Deploy to Azure button or use the below methor with powershell

Creating a new deployment with powershell:

Remember to set your Username, Password and Unique Storage Account name in azuredeploy-parameters.json

Create a resource group:

    PS C:\Users\azureuser1> New-AzureResourceGroup -Name "kafka-demo" -Location 'WestEurope'

Start deployment

    PS C:\Users\azureuser1> New-AzureResourceGroupDeployment -Name kafkademo-deployment -ResourceGroupName "kafka-demo" -TemplateFile C:\gitsrc\azure-resource-manager-templates\kafka-on-redhat\azuredeploy.json -TemplateParameterFile C:\gitsrc\azure-resource-manager-templates\kafka-on-redhat\azuredeploy-parameters.json -Verbose
    
Check Deployment
----------------

To access the individual Kafka and Zookeeper nodes, you need to use the publicly accessible jumpbox VM and ssh from it into the VM instances running Kafka or Zookeeper.

To get started connect to the public ip of Jumpbox with username and password provided during deployment.

From the jumpbox connect to any of the Zookeeper nodes, e.g. ssh 10.0.0.40 ,ssh 10.0.0.41, etc.
Run this command to check that kafka process is running ok: 

	ps -ef | grep zookeeper 

After that, you can connect to the Zookeeper cluster running:

	cd /var/lib/zookeeper/zookeeper-3.4.8/

    bin/zkCli.sh -server 127.0.0.1:2181

From the jumpbox connect to any of the Kafka brokers, e.g. ssh 10.0.0.10 ,ssh 10.0.0.11, etc.
Run this command to check that kafka process is running ok: 

	ps -ef | grep kafka 

After that, you can run the kafka commands:

	cd /usr/local/kafka/kafka_2.10-0.10.0.0/

	bin/kafka-topics.sh --create --zookeeper 10.0.0.40:2181  --replication-factor 2 --partitions 1 --topic my-replicated-topic1

	bin/kafka-topics.sh --describe --zookeeper 10.0.0.40:2181  --topic my-replicated-topic1

	bin/kafka-console-producer.sh --broker-list localhost:9092 --topic my-replicated-topic1
	
	bin/kafka-console-consumer.sh --zookeeper 10.0.0.40:2181 --topic my-replicated-topic1 --from-beginning

Topology
--------

The deployment topology is comprised of Kafka Brokers and Zookeeper nodes running in the cluster mode.
Kafka version 0.10.0.0 is the default version and can be changed to any pre-built binaries avaiable on Kafka repo.
A static IP address will be assigned to each Kafka node in order to work around the current limitation of not being able to dynamically compose a list of IP addresses from within the template (by default, the first node will be assigned the private IP of 10.0.0.10, the second node - 10.0.0.11, and so on)
A static IP address will be assigned to each Zookeeper node in order to work around the current limitation of not being able to dynamically compose a list of IP addresses from within the template (by default, the first node will be assigned the private IP of 10.0.0.40, the second node - 10.0.0.41, and so on)

To check deployment errors go to the new azure portal and look under Resource Group -> Last deployment -> Check Operation Details

##Known Issues and Limitations
- The deployment script is not yet handling data disks and using local storage.
- There will be a separate checkin for persistant disks.
- Health monitoring of the Kafka instances is not currently enabled
- SSH key is not yet implemented and the template currently takes a password for the admin user
