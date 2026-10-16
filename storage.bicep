// storage.bicep

var storageAccountName = 'st${uniqueString(resourceGroup().id)}'
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: 'uksouth'
  tags: {
    CostCentre: 'Engineering'
  }
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
}
