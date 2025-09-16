# ERCData Standard

## Table of Contents

- [Abstract](#abstract)
- [Motivation](#motivation)
- [Specification](#specification)
  - [Data Structures](#data-structures)
  - [Core Functions](#core-functions)
  - [Events](#events)
- [Implementation](#implementation)
- [Security Considerations](#security-considerations)
- [Usage](#usage)
  - [For Data Providers](#for-data-providers)
  - [For Data Consumers](#for-data-consumers)
  - [For Verifiers](#for-verifiers)
  - [For Data Type Management](#for-data-type-management)
- [Verification Semantics](#verification-semantics)
- [Use Cases](#use-cases)
- [Getting Started](#getting-started)
  - [Installation](#installation)
  - [Compile](#compile)
  - [Test](#test)
- [Deployment](#deployment)
  - [Setup Environment](#setup-environment)
  - [Deploy to Base Testnet (Sepolia)](#deploy-to-base-testnet-sepolia)
  - [Deploy to Base Mainnet](#deploy-to-base-mainnet)
- [Quick Start: Verify Data](#quick-start-verify-data)
- [Quick Start: Batch Verify](#quick-start-batch-verify)
- [Copyright](#copyright)

## Abstract

A standard interface for storing and managing AI-related metadata and verification information on the Ethereum blockchain. This standard provides a unified way to store, retrieve, verify, and update AI-related data fingerprints, metadata, and verification records, enabling transparency and accountability for AI systems.

## Motivation

As AI technology evolves, there is an increasing need to establish transparent and verifiable records of AI systems. While storing large AI models or training datasets on-chain is impractical due to size constraints, there's significant value in storing cryptographic proofs, metadata, and verification records. The ERCData standard provides a unified interface for:

- Recording cryptographic fingerprints and metadata of AI systems
- Verifying data authenticity and integrity
- Managing data providers and verifiers
- Creating snapshots for versioning and auditing
- Supporting structured data types with field-level access
- Tracking updates and modifications to AI systems
- Maintaining a clear chain of custody for AI-related information

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

## Verification Semantics

- Identity binding: Provider signs the entry’s hashes and must match `provider`.
- Integrity binding: Verifies `keccak256(data)` and (optionally) `keccak256(metadata)` integrity.
- Context binding: EIP-712 domain includes `chainId` and `verifyingContract` to prevent replay.
- Verifier attestation: Only `VERIFIER_ROLE` can verify; the contract records verifier, time, method, and calldata.
- State updates: On success, sets `isVerified` and stores `VerificationInfo`; `updateData` resets verification.

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

Verification methods are selected by encoding a 4-byte selector (and optional payload) into `verificationData` using ABI encoding (not packed):

- Selector `0x45503132` ("EP12"): EIP-712 provider signature verification.
  - Encoding: `abi.encode(bytes4("EP12"))` → 32 bytes.
  - Checks that the stored `signature` recovers to the entry `provider` over the typed data:
    - Typehash: `ERCDataEntry(bytes32 dataHash,bytes32 metadataHash,string dataType,address provider)`
    - Struct fields: `keccak256(data)`, `keccak256(metadata)`, `dataType`, `provider`
    - Domain: name "ERCData", version "1", current `chainId`, and `verifyingContract` = this contract.
  - On success: `verificationMethod` = `"EIP712_PROVIDER_SIG"`.

- Selector `0x48415348` ("HASH"): Data hash equality verification.
  - Encoding: `abi.encode(bytes4("HASH"), bytes32 expectedDataHash)` → 64 bytes.
  - Checks: `keccak256(stored data) == expectedDataHash`.
  - On success: `verificationMethod` = `"DATA_HASH_EQ"`.

Example with Ethers.js v5:

```ts
// Build EIP-712 signature off-chain by the provider
const domain = {
  name: "ERCData",
  version: "1",
  chainId: (await ethers.provider.getNetwork()).chainId,
  verifyingContract: ercData.address,
};
const types = {
  ERCDataEntry: [
    { name: "dataHash", type: "bytes32" },
    { name: "metadataHash", type: "bytes32" },
    { name: "dataType", type: "string" },
    { name: "provider", type: "address" },
  ],
};
const value = {
  dataHash: ethers.utils.keccak256(dataBytes),
  metadataHash: ethers.utils.keccak256(metadataBytes),
  dataType: "AI_MODEL_WEIGHTS",
  provider: provider.address,
};
const signature = await provider._signTypedData(domain, types as any, value);

// Store with signature
await ercData.connect(provider).storeData(
  "AI_MODEL_WEIGHTS",
  dataBytes,
  metadataBytes,
  ethers.utils.arrayify(signature)
);

// Verify using EIP-712 selector
const verificationData = ethers.utils.defaultAbiCoder.encode(["bytes4"], ["0x45503132"]);
await ercData.connect(verifier).verifyData(dataId, verificationData);

// Verify using HASH selector
const expected = ethers.utils.keccak256(dataBytes);
const verificationDataHash = ethers.utils.defaultAbiCoder.encode(["bytes4", "bytes32"], ["0x48415348", expected]);
await ercData.connect(verifier).verifyData(dataId, verificationDataHash);
```

Batch verification behavior:

- Same selector for all entries: `verifyBatch(batchId, verificationData)` applies the same `verificationData` to each entry in the batch.
- Per-entry state: Updates each entry’s `isVerified` and `VerificationInfo`, and emits `DataVerified` for each.
- Aggregate event: Emits `BatchVerified(batchId, verifier, isValidAll)` where `isValidAll` is true only if all entries pass.
- HASH method caveat: The provided `expectedDataHash` applies to every entry, so use only for homogeneous batches.

Failure cases to expect:

- Unknown selector: Reverts (invalid or unknown selector/format).
- Wrong signer or stale signature: EIP-712 verification returns false; entry remains unverified.
- Domain mismatch: EIP-712 bound to a different contract/chain returns false.
- Hash mismatch: HASH method returns false.

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

1. **AI Model Metadata & Provenance**: Store cryptographic hashes, metadata, and provenance information about AI models while keeping the actual models off-chain
2. **Model Performance Metrics**: Record and verify performance metrics, accuracy scores, and evaluation results for AI models
3. **Training Dataset Fingerprints**: Store dataset manifests, statistical summaries, and cryptographic fingerprints of training data
4. **AI Inference Results**: Record and verify outputs from AI models with complete audit trails
5. **Model Governance & Compliance**: Track model versions, approvals, and compliance certifications with immutable records
6. **Federated Learning Coordination**: Coordinate federated learning processes with on-chain verification of participant contributions
7. **AI Oracle Networks**: Enable decentralized networks of AI oracles to provide verified AI services with transparent records

## Getting Started

### Installation

```bash
# Install dependencies
npm install
```

### Compile

```bash
# Compile contracts
npx hardhat compile
```

### Test

```bash
# Run tests
npx hardhat test
```

### Deployment

#### Setup Environment

1. Create a `.env` file based on `.env.example`:
   ```bash
   cp .env.example .env
   ```

2. Edit the `.env` file with your private key and RPC URLs:
   ```
   # Replace with your actual private key (without 0x prefix)
   PRIVATE_KEY=your_private_key_here
   
   # Use default Base RPC URLs or replace with your own
   BASE_MAINNET_RPC_URL=https://mainnet.base.org
   BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
   
   # Add API keys for contract verification
   BASESCAN_API_KEY=your_basescan_api_key
   ```

#### Deploy to Base Testnet (Sepolia)

```bash
npx hardhat run scripts/deploy.ts --network base-sepolia
```

#### Deploy to Base Mainnet

```bash
npx hardhat run scripts/deploy.ts --network base
```

## Quick Start: Verify Data

```ts
// 1) Provider signs entry (EIP-712) and stores it
const dataBytes = ethers.utils.toUtf8Bytes("model weights data");
const metadataBytes = ethers.utils.toUtf8Bytes('{"version":"1.0"}');
const domain = {
  name: "ERCData",
  version: "1",
  chainId: (await ethers.provider.getNetwork()).chainId,
  verifyingContract: ercData.address,
};
const types = {
  ERCDataEntry: [
    { name: "dataHash", type: "bytes32" },
    { name: "metadataHash", type: "bytes32" },
    { name: "dataType", type: "string" },
    { name: "provider", type: "address" },
  ],
};
const value = {
  dataHash: ethers.utils.keccak256(dataBytes),
  metadataHash: ethers.utils.keccak256(metadataBytes),
  dataType: "AI_MODEL_WEIGHTS",
  provider: provider.address,
};
const signature = await provider._signTypedData(domain, types as any, value);
const tx = await ercData.connect(provider).storeData(
  "AI_MODEL_WEIGHTS",
  dataBytes,
  metadataBytes,
  ethers.utils.arrayify(signature)
);
const receipt = await tx.wait();
const dataId = receipt.events?.find(e => e.event === "DataStored").args[0];

// 2) Verifier validates using EIP-712 method selector ("EP12")
const verificationData = ethers.utils.defaultAbiCoder.encode(["bytes4"], ["0x45503132"]);
const verified = await ercData.connect(verifier).verifyData(dataId, verificationData);

// Alternatively: hash-only method for homogeneous data
const expectedHash = ethers.utils.keccak256(dataBytes);
const hashVerification = ethers.utils.defaultAbiCoder.encode(["bytes4","bytes32"], ["0x48415348", expectedHash]);
await ercData.connect(verifier).verifyData(dataId, hashVerification);
```

See the Verifiers section above for full details and failure cases.

## Quick Start: Batch Verify

```ts
// 1) Provider stores a batch (sign each entry off-chain in the same way as single entries)
const dataArray = [
  ethers.utils.toUtf8Bytes("weights v1"),
  ethers.utils.toUtf8Bytes("weights v2"),
];
const metadataArray = [
  ethers.utils.toUtf8Bytes('{"version":"1"}'),
  ethers.utils.toUtf8Bytes('{"version":"2"}'),
];
// Sign both entries with EIP-712 (domain = {name:"ERCData",version:"1",chainId,verifyingContract})
const sig0 = await provider._signTypedData(domain, types as any, {
  dataHash: ethers.utils.keccak256(dataArray[0]),
  metadataHash: ethers.utils.keccak256(metadataArray[0]),
  dataType: "AI_MODEL_WEIGHTS",
  provider: provider.address,
});
const sig1 = await provider._signTypedData(domain, types as any, {
  dataHash: ethers.utils.keccak256(dataArray[1]),
  metadataHash: ethers.utils.keccak256(metadataArray[1]),
  dataType: "AI_MODEL_WEIGHTS",
  provider: provider.address,
});

const batchTx = await ercData.connect(provider).storeBatch(
  "AI_MODEL_WEIGHTS",
  dataArray,
  metadataArray,
  [ethers.utils.arrayify(sig0), ethers.utils.arrayify(sig1)]
);
const batchRc = await batchTx.wait();
const batchId = batchRc.events?.find(e => e.event === "BatchProcessed").args[1];

// 2) Verifier validates the entire batch using the EIP-712 method selector ("EP12")
const ep12 = ethers.utils.defaultAbiCoder.encode(["bytes4"], ["0x45503132"]);
const allOk = await ercData.connect(verifier).verifyBatch(batchId, ep12);

// Inspect per-entry results
const entries = await ercData.getBatchData(batchId);
console.log(entries.map(e => e.isVerified)); // [true, true] if all succeeded

// Alternative: hash-only batch verification for homogeneous data
// (same expected hash applied to all entries)
const expectedHash = ethers.utils.keccak256(dataArray[0]);
const hashSel = ethers.utils.defaultAbiCoder.encode(["bytes4","bytes32"], ["0x48415348", expectedHash]);
await ercData.connect(verifier).verifyBatch(batchId, hashSel);
```

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/). 
