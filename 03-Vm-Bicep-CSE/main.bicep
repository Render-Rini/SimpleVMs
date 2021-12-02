///////////////////////////////// Parameters //////////////////////////////////////////////////////////////

@description('Specifies the location for all resources.')
param location string = resourceGroup().location

@description('The name of the environment. This must be dev, test, or prod.')
@allowed([
  'dev'
  'test'
  'prod'
])
param environmentName string

@description('Tags for the resources')
param resourceTags object

@description('Specifies the administrator username for the Virtual Machine.')
@secure()
param adminUsername string

@description('Specifies the administrator password for the Virtual Machine.')
@secure()
param adminPassword string

@description('Virtual machine size.')
param vmSize string

@description('Specifies the Windows version for the VM. This will pick a fully patched image of this given Windows version.')
@allowed([
  '2016-Datacenter'
  '2019-Datacenter'
])
param windowsOSVersion string

@description('Name of the external data disk')
param ext_disk_name string

@description('Location of the post Deployment Configuration Script to be executed by Custom Script Extension')
param fileUris string

/// VM and Related resources variables ///
var storageAccountName = '${environmentName}${uniqueString(resourceGroup().id)}vm'
var storageAccountSkuName = (environmentName == 'prod') ? 'Standard_GRS' : 'Standard_LRS'
var networkInterfaceName = '${environmentName}-nic'
var vNetAddressPrefix = '10.0.0.0/16'
var vNetSubnetName = 'default'
var vNetSubnetAddressPrefix = '10.0.0.0/24'
var publicIPAddressName = '${environmentName}-pip'
var vmName = '${environmentName}-vm'
var vNetName = '${environmentName}-vnet'
var networkSecurityGroupName = '${environmentName}-NSG'

//////////////////////////////////////// VM Related Resources ////////////////////////////////////////////////////////

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-06-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: storageAccountSkuName
  }
  kind: 'StorageV2'
  properties: {}
}

resource publicIPAddress 'Microsoft.Network/publicIPAddresses@2020-06-01' = {
  name: publicIPAddressName
  location: location
  properties: {
    publicIPAllocationMethod: 'Dynamic'
  }
}

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2020-06-01' = {
  name: networkSecurityGroupName
  location: location
  properties: {
    securityRules: [
      {
        name: 'default-allow-3389'
        properties: {
          priority: 1000
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRange: '3389'
          protocol: 'Tcp'
          sourceAddressPrefix: '1.1.1.1'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource vNet 'Microsoft.Network/virtualNetworks@2020-06-01' = {
  name: vNetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vNetAddressPrefix
      ]
    }
    subnets: [
      {
        name: vNetSubnetName
        properties: {
          addressPrefix: vNetSubnetAddressPrefix
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
        }
      }
    ]
  }
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2020-06-01' = {
  name: networkInterfaceName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIPAddress.id
          }
          subnet: {
            id: '${vNet.id}/subnets/${vNetSubnetName}'
          }
        }
      }
    ]
  }
}

resource ext_disk_resource 'Microsoft.Compute/disks@2021-04-01' = {
  name: ext_disk_name
  location: location
  sku: {
    name: 'Premium_LRS'
  }
  properties: {
    creationData: {
      createOption: 'Empty'
    }
    diskSizeGB: 25
    diskIOPSReadWrite: 120
    diskMBpsReadWrite: 25
    encryption: {
      type: 'EncryptionAtRestWithPlatformKey'
    }
    networkAccessPolicy: 'AllowAll'
    tier: 'P4'
  }
}

resource virtualMachine 'Microsoft.Compute/virtualMachines@2020-06-01' = {
  name: vmName
  location: location
  tags: resourceTags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: windowsOSVersion
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
      }
      dataDisks: [
        {
          lun: 0
          name: ext_disk_name
          createOption: 'Attach'
          caching: 'None'
          writeAcceleratorEnabled: false
          managedDisk: {
            storageAccountType: 'Premium_LRS'
            id: ext_disk_resource.id
          }
          diskSizeGB: 25
          toBeDetached: false
        }
      ]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: storageAccount.properties.primaryEndpoints.blob
      }
    }
  }
}

resource virtualMachines_dev_vm_name_CustomScriptExtension 'Microsoft.Compute/virtualMachines/extensions@2021-07-01' = {
  parent: virtualMachine
  name: 'CustomScriptExtension'
  location: location
  properties: {
    autoUpgradeMinorVersion: true
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.9'
    settings: {
      fileUris: split(fileUris, ' ')
      commandToExecute: 'powershell.exe -ExecutionPolicy Bypass -File CSE-ChocoInstall.ps1'
    }
    protectedSettings: {}
  }
}
