LOCATION="eastus"
RESOURCE_GROUP="k8s-vnet-test-$(($RANDOM % 10000))"
VNET_NAME="k8s-vnet"
SUBNET_NAME="k8s-subnet"
K8S_CLUSTER_NAME="aks-cluster"
IOT_HUB_NAME="iothub-test-$(($RANDOM % 10000))"
DEVICE_ID="myNodeJsSimulatorDevice"

STORAGE_ACCOUNT_NAME="iothub-store-$(($RANDOM % 10000))"
STORAGE_CONTAINER_NAME="eph-leases"

# Create Resource Group
echo "Creating a resource group: $RESOURCE_GROUP"
az group create \
  --location $LOCATION \
  --name $RESOURCE_GROUP
echo "Done."

# Create VNET and subnet
ADDR_PREFIXES='10.0.0.0/16'
SUBNET_PREFIXES='10.0.0.0/24'
echo "Creating a VNet ($VNET_NAME) with address prefixes ($ADDR_PREFIXES) and subnet ($SUBNET_NAME) with address prefixes ($SUBNET_PREFIXES)"
az network vnet create \
  --resource-group $RESOURCE_GROUP \
  --name $VNET_NAME \
  --address-prefixes $ADDR_PREFIXES \
  --subnet-name $SUBNET_NAME \
  --subnet-prefix $SUBNET_PREFIXES
echo "Done."

az network vnet subnet update \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $VNET_NAME \
  --subnet-name $SUBNET_NAME \
  --service-endpoints Microsoft.EventHub

# Subnet ID
SUBNET_ID=$(az network vnet subnet list \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $VNET_NAME \
  --query [].id \
  --output tsv)

# Create AKS cluster
echo "Creating an AKS cluster (using advanced networking + auto-gen SSH keys) within VNet Subnet ID: $SUBNET_ID"
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name $K8S_CLUSTER_NAME \
  --network-plugin azure \
  --vnet-subnet-id $SUBNET_ID \
  --docker-bridge-address 172.17.0.1/16 \
  --dns-service-ip 10.2.0.10 \
  --service-cidr 10.2.0.0/24 \
  --generate-ssh-keys
echo "Done."

# Get AKS credentials
echo "Downloading AKS credentials to add to kubectl, assumes kubectl already installed (Azure Cloud Shell has it preinstalled)."
az aks get-credentials \
  --resource-group $RESOURCE_GROUP \
  --name $K8S_CLUSTER_NAME
echo "Done."

# AKS sister resource group created, show it for reference.
echo "Identifying AKS Node Resource Group..."
az aks show \
  --resource-group $RESOURCE_GROUP \
  --name $K8S_CLUSTER_NAME \
  --query nodeResourceGroup \
  --output tsv
echo "Done."

# Create an IoT Hub
echo "Creating an IoT Hub: $IOT_HUB_NAME"
az iot hub create \
  --resource-group $RESOURCE_GROUP \
  --name $IOT_HUB_NAME \
  --sku S1 \
  --location $LOCATION \
  --partition-count 4
echo "Done."

# Ensure IoT Extension
echo "Adding Azure CLI IoT Extension..."
az extension add --name azure-cli-iot-ext
echo "Done."

# Create a device simulator
echo "Creating new IoT Device for telemetry simulation: $DEVICE_ID"
az iot hub device-identity create \
  --hub-name $IOT_HUB_NAME \
  --device-id $DEVICE_ID
echo "Done."

# Get a device connection string
echo "Getting device connection string for: $DEVICE_ID"
DEVICE_CONNECTION_STRING_VALUE=$(az iot hub device-identity show-connection-string \
  --hub-name $IOT_HUB_NAME \
  --device-id $DEVICE_ID \
  --output tsv)
echo "Done."

# Creating an EventHub-compatible EP
IOTHUB_POLICY_NAME="iothubowner" # Default policy for IoT Hub with manage/write/read access

IOTHUB_EVENTS_EH_HUB_COMPAT_EP=$(az iot hub show \
  --name $IOT_HUB_NAME \
  --query properties.eventHubEndpoints.events.endpoint \
  --output tsv)

IOTHUB_KEY=$(az iot hub policy show \
  --hub-name $IOT_HUB_NAME \
  --name $IOTHUB_POLICY_NAME \
  --query primaryKey)

EVENT_HUB_CONNECTION_STRING_VALUE="$IOTHUB_EVENTS_EH_HUB_COMPAT_EP;SharedAccessKeyName=$IOTHUB_POLICY_NAME;SharedAccessKey=$IOTHUB_KEY"
EVENT_HUB_NAME_VALUE="messages/events"

# Create a storage account
echo "Creating storage account: $STORAGE_ACCOUNT_NAME"
az storage account create \
  --location $LOCATION \
  --name $STORAGE_ACCOUNT_NAME \
  --resource-group $RESOURCE_GROUP  \
  --sku "Standard_LRS"
echo "Done."

# Get storage account key
echo "Finding storage account key..."
STORAGE_ACCOUNT_KEY=$(az storage account keys list \
  --account-name $STORAGE_ACCOUNT_NAME \
  --resource-group $RESOURCE_GROUP  \
  --query [0].value \
  --output tsv)
echo "Found key: $STORAGE_ACCOUNT_KEY"
echo "Done."

# Create container for EPH leases
echo "Creating blob container for EventProcessorHost leases: $STORAGE_CONTAINER_NAME"
az storage container create \
  --name $STORAGE_CONTAINER_NAME \
  --account-name $STORAGE_ACCOUNT_NAME \
  --account-key $STORAGE_ACCOUNT_KEY
echo "Done."

# Updating kubernetes file for deployment
sed -i -e "s/DEVICE_CONNECTION_STRING_VALUE/DEVICE_CONNECTION_STRING_VALUE/g" kubernetes.yml
sed -i -e "s@EVENT_HUB_CONNECTION_STRING_VALUE@EVENT_HUB_CONNECTION_STRING_VALUE@g" kubernetes.yml
sed -i -e "s/EVENT_HUB_NAME_VALUE/EVENT_HUB_NAME_VALUE/g" kubernetes.yml
sed -i -e "s/STORAGE_ACCOUNT_NAME_VALUE/STORAGE_ACCOUNT_NAME/g" kubernetes.yml
sed -i -e "s/STORAGE_CONTAINER_NAME_VALUE/STORAGE_CONTAINER_NAME/g" kubernetes.yml
sed -i -e "s/STORAGE_ACCOUNT_KEY_VALUE/STORAGE_ACCOUNT_KEY/g" kubernetes.yml

# Deploying apps
kubectl apply -f kubernetes.yml

# Check for deployments
echo "Sleeping for 30s before checking deployments.."
sleep 30

echo "Checking deployments..."
kubectl get deployments