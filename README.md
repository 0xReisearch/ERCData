# ERCData Standard

## Abstract

A standard interface for storing and managing AI data on the Ethereum blockchain with built-in verification mechanisms. This standard provides a unified way to store, retrieve, verify, and update AI-related data, including model weights, training datasets, or any other type of AI data that requires on-chain availability and verification.

## Motivation

As AI technology evolves, there is an increasing need to store and verify AI-related data on-chain. Whether it's model weights, training data, or inference results, having a standardized way to store and verify this information becomes crucial for transparency and accountability. The ERCData standard provides a unified interface for:

- Storing AI model data on-chain
- Verifying data authenticity and integrity
- Managing data providers and verifiers
- Creating snapshots for versioning and auditing
- Supporting structured data types with field-level access
- Tracking data updates and modifications
- Maintaining a clear chain of custody for AI data

## Specification

The ERCData standard defines the following core functionality:

### Data Structures

```solidity
struct DataEntryView {
    uint256 dataId;
    address provider;
    uint256 timestamp;
    string dataType;
    bytes data;
    bytes metadata;
    bytes signature;
    bool isVerified;
    uint256 batchId;
}

struct VerificationInfo {
    address verifier;
    uint256 timestamp;
    bool isValid;
    string verificationMethod;
    bytes verificationData;
}

struct DataTypeInfoView {
    string name;
    bool exists;
    string[] fieldNames;
    string[] fieldTypes;
    bool[] isIndexed;
}

struct SnapshotView {
    bytes32 id;
    string name;
    uint256 timestamp;
    uint256[] includedDataIds;
    bytes[] data;
}
```

### Core Functions

1. **storeData**: Store new AI data on-chain
2. **getData**: Retrieve stored data by ID
3. **verifyData**: Verify the authenticity and integrity of stored data
4. **updateData**: Update existing data entries
5. **getVerificationInfo**: Get verification information for a data entry
6. **registerDataType**: Register a new data type with structured fields
7. **createSnapshot**: Create a point-in-time snapshot of selected data
8. **getField**: Access specific fields within structured data

### Events

1. **DataStored**: Emitted when new data is stored
2. **DataVerified**: Emitted when data is verified
3. **DataUpdated**: Emitted when data is updated
4. **BatchProcessed**: Emitted when batch data is processed
5. **SnapshotTaken**: Emitted when a snapshot is created
6. **DataTypeRegistered**: Emitted when a new data type is registered

## Implementation

The reference implementation includes:

- Role-based access control for data providers, verifiers, and snapshot creators
- Structured data types with field-level access
- Batch operations for efficient data storage
- Snapshot functionality for versioning and auditing
- Pausable functionality for emergency situations
- Reentrancy protection
- Comprehensive data tracking and management
- Extensible verification mechanism

## Security Considerations

1. **Access Control**: Only authorized providers can store and update data
2. **Verification**: Only authorized verifiers can verify data
3. **Data Integrity**: All updates are tracked and maintain the verification state
4. **Emergency Controls**: Pause mechanism for emergency situations
5. **Reentrancy Protection**: Guards against reentrancy attacks

## Usage

### For Data Providers

```solidity
// Store new data
function storeData(
    string calldata dataType,
    bytes calldata data,
    bytes calldata metadata,
    bytes calldata signature
) external returns (uint256 dataId);

// Store batch data
function storeBatch(
    string calldata dataType,
    bytes[] calldata dataArray,
    bytes[] calldata metadataArray,
    bytes[] calldata signatures
) external returns (uint256 batchId);

// Update existing data
function updateData(
    uint256 dataId,
    bytes calldata newData,
    bytes calldata newMetadata,
    bytes calldata signature
) external returns (bool);
```

### For Data Consumers

```solidity
// Retrieve data
function getData(uint256 dataId) external view returns (DataEntryView memory);

// Get specific field from structured data
function getField(uint256 dataId, string calldata fieldName) 
    external 
    view 
    returns (bytes memory);

// Get verification status
function getVerificationInfo(uint256 dataId) 
    external 
    view 
    returns (VerificationInfo memory);

// Get batch data
function getBatchData(uint256 batchId) 
    external 
    view 
    returns (DataEntryView[] memory);

// Get snapshot data
function getSnapshot(bytes32 snapshotId) 
    external 
    view 
    returns (SnapshotView memory);
```

### For Verifiers

```solidity
// Verify data
function verifyData(uint256 dataId, bytes calldata verificationData)
    external
    returns (bool);

// Verify batch
function verifyBatch(uint256 batchId, bytes calldata verificationData)
    external
    returns (bool);
```

### For Data Type Management

```solidity
// Register new data type
function registerDataType(string calldata typeName) 
    external 
    returns (bool);

// Add field to data type
function addField(
    string calldata typeName,
    string calldata fieldName,
    string calldata fieldType,
    bool isIndexed
) external;

// Get data type information
function getDataTypeInfo(string calldata typeName) 
    external 
    view 
    returns (DataTypeInfoView memory);
```

## Use Cases

1. **AI Model Transparency**: Store model weights on-chain for transparency and auditability
2. **Verifiable Datasets**: Create verifiable training datasets for AI models
3. **Model Evolution Tracking**: Use snapshots to track AI model evolution over time
4. **Decentralized AI Marketplaces**: Build marketplaces for AI models with verifiable quality
5. **AI Governance**: Implement on-chain governance for AI systems

## Getting Started

### Installation

```bash
npm install
```

### Compile

```bash
npx hardhat compile
```

### Test

```bash
npx hardhat test
```

### Deploy

```bash
npx hardhat run scripts/deploy.js --network <network>
```

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/). 