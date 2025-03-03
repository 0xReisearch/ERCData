// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IERCData
 * @dev Interface for the ERCData standard for storing and managing AI data on-chain
 */
interface IERCData {
    /**
     * @dev Structure for data entries
     */
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

    /**
     * @dev Complete structure for data entries (internal usage)
     */
    struct DataEntry {
        uint256 dataId;
        address provider;
        uint256 timestamp;
        string dataType;
        bytes data;
        bytes metadata;
        bytes signature;
        mapping(string => bytes) fields;
        bool isVerified;
        uint256 batchId;
    }

    /**
     * @dev Structure for data verification
     */
    struct VerificationInfo {
        address verifier;
        uint256 timestamp;
        bool isValid;
        string verificationMethod;
        bytes verificationData;
    }

    /**
     * @dev Structure for data type definition
     */
    struct DataTypeInfo {
        string name;
        string[] fieldNames;
        mapping(string => string) fieldTypes;
        mapping(string => bool) isIndexed;
        bool exists;
    }

    /**
     * @dev Structure for snapshot data (without mapping for external returns)
     */
    struct SnapshotView {
        bytes32 id;
        string name;
        uint256 timestamp;
        uint256[] includedDataIds;
        bytes[] data;
    }

    struct DataTypeInfoView {
        string name;
        bool exists;
        string[] fieldNames;
        string[] fieldTypes;
        bool[] isIndexed;
    }

    // Events for data management
    event DataStored(uint256 indexed dataId, address indexed provider, string indexed dataType, uint256 timestamp);
    event DataVerified(uint256 indexed dataId, address indexed verifier, bool isValid, uint256 timestamp);
    event DataUpdated(uint256 indexed dataId, address indexed provider, uint256 timestamp);
    
    // Events for batch operations
    event BatchProcessed(string indexed dataType, uint256 batchId, uint256 entriesCount);
    event BatchVerified(uint256 indexed batchId, address indexed verifier, bool isValid);
    
    // Events for data type management
    event DataTypeRegistered(string typeName);
    event FieldAdded(string indexed dataType, string fieldName, string fieldType, bool indexed isIndexed);
    
    // Events for snapshots
    event SnapshotTaken(bytes32 indexed snapshotId, string name, uint256 timestamp);

    // Core data management functions
    function storeData(string calldata dataType, bytes calldata data, bytes calldata metadata, bytes calldata signature) external returns (uint256 dataId);
    function getData(uint256 dataId) external view returns (DataEntryView memory);
    function verifyData(uint256 dataId, bytes calldata verificationData) external returns (bool success);
    function updateData(uint256 dataId, bytes calldata newData, bytes calldata newMetadata, bytes calldata signature) external returns (bool success);
    function getVerificationInfo(uint256 dataId) external view returns (VerificationInfo memory);

    // Batch operations
    function storeBatch(string calldata dataType, bytes[] calldata dataArray, bytes[] calldata metadataArray, bytes[] calldata signatures) external returns (uint256 batchId);
    function verifyBatch(uint256 batchId, bytes calldata verificationData) external returns (bool success);
    function getBatchData(uint256 batchId) external view returns (DataEntryView[] memory);

    // Data type management
    function registerDataType(string calldata typeName) external returns (bool);
    function addField(string calldata typeName, string calldata fieldName, string calldata fieldType, bool isIndexed) external;
    function getDataTypeInfo(string calldata typeName) external view returns (DataTypeInfoView memory);

    // Snapshot management
    function createSnapshot(string calldata name, uint256[] calldata dataIds) external returns (bytes32);
    function getSnapshot(bytes32 snapshotId) external view returns (SnapshotView memory);
    function listSnapshots() external view returns (bytes32[] memory);

    // Add function to get field data
    function getField(uint256 dataId, string calldata fieldName) external view returns (bytes memory);
} 