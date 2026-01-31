// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IERCData.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/**
 * @title ERCData
 * @dev Reference implementation of the ERCData standard for AI data storage
 */
contract ERCData is IERCData, AccessControl, Pausable, ReentrancyGuard, EIP712 {
    // Internal struct definitions
    struct Snapshot {
        bytes32 id;
        string name;
        uint256 timestamp;
        mapping(uint256 => bytes) data;
        uint256[] includedDataIds;
    }

    // Roles
    bytes32 public constant PROVIDER_ROLE = keccak256("PROVIDER_ROLE");
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    bytes32 public constant SNAPSHOT_ROLE = keccak256("SNAPSHOT_ROLE");

    // State variables
    mapping(uint256 => DataEntry) private _dataEntries;
    mapping(uint256 => VerificationInfo) private _verifications;
    mapping(address => uint256[]) private _providerData;
    mapping(string => DataTypeInfo) private _dataTypes;
    mapping(bytes32 => Snapshot) private _snapshots;
    mapping(uint256 => uint256[]) private _batchEntries; // batchId => array of dataIds
    
    // Privacy and access control
    mapping(uint256 => mapping(address => bool)) private _accessList; // dataId => address => canRead
    
    bytes32[] private _snapshotIds;
    uint256 private _nextDataId;
    uint256 private _nextBatchId;

    // Verification selectors (abi.encode(bytes4("EP12")), abi.encode(bytes4("HASH")))
    bytes4 private constant VERIF_EIP712 = 0x45503132; // "EP12"
    bytes4 private constant VERIF_HASH = 0x48415348;   // "HASH"

    // EIP-712 typehash for provider-signed entries
    // ERCDataEntry(bytes32 dataHash,bytes32 metadataHash,string dataType,address provider)
    bytes32 private constant DATA_ENTRY_TYPEHASH = keccak256(
        "ERCDataEntry(bytes32 dataHash,bytes32 metadataHash,string dataType,address provider)"
    );

    // Constructor
    // Constants for security limits
    uint256 private constant MAX_DATA_SIZE = 1024 * 1024; // 1MB per data entry
    uint256 private constant MAX_METADATA_SIZE = 64 * 1024; // 64KB per metadata entry
    uint256 private constant MAX_BATCH_SIZE = 100; // Maximum entries per batch

    constructor() EIP712("ERCData", "1") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SNAPSHOT_ROLE, msg.sender);
        _nextDataId = 1;
        _nextBatchId = 1;
    }

    // Data management functions
    function storeData(
        string calldata dataType,
        bytes calldata data,
        bytes calldata metadata,
        bytes calldata signature
    ) external override whenNotPaused nonReentrant returns (uint256) {
        require(hasRole(PROVIDER_ROLE, msg.sender), "ERCData: must have provider role");
        require(bytes(dataType).length > 0, "ERCData: dataType cannot be empty");
        require(data.length > 0, "ERCData: data cannot be empty");
        require(data.length <= MAX_DATA_SIZE, "ERCData: data too large");
        require(metadata.length <= MAX_METADATA_SIZE, "ERCData: metadata too large");
        // signature requirements removed - optional parameter
        require(_dataTypes[dataType].exists, "ERCData: data type not registered");

        uint256 dataId = _nextDataId++;

        // Initialize struct fields individually
        DataEntry storage entry = _dataEntries[dataId];
        entry.dataId = dataId;
        entry.provider = msg.sender;
        entry.timestamp = block.timestamp;
        entry.dataType = dataType;
        entry.data = data;
        entry.metadata = metadata;
        entry.signature = signature;
        entry.isVerified = false;
        entry.batchId = 0;
        entry.isPrivate = false;

        _providerData[msg.sender].push(dataId);

        emit DataStored(dataId, msg.sender, dataType, block.timestamp);
        return dataId;
    }

    function storePrivateData(
        string calldata dataType,
        bytes calldata data,
        bytes calldata metadata,
        bytes calldata signature
    ) external whenNotPaused nonReentrant returns (uint256) {
        require(hasRole(PROVIDER_ROLE, msg.sender), "ERCData: must have provider role");
        require(bytes(dataType).length > 0, "ERCData: dataType cannot be empty");
        require(data.length > 0, "ERCData: data cannot be empty");
        require(data.length <= MAX_DATA_SIZE, "ERCData: data too large");
        require(metadata.length <= MAX_METADATA_SIZE, "ERCData: metadata too large");
        require(_dataTypes[dataType].exists, "ERCData: data type not registered");

        uint256 dataId = _nextDataId++;

        // Initialize struct fields individually
        DataEntry storage entry = _dataEntries[dataId];
        entry.dataId = dataId;
        entry.provider = msg.sender;
        entry.timestamp = block.timestamp;
        entry.dataType = dataType;
        entry.data = data;
        entry.metadata = metadata;
        entry.signature = signature;
        entry.isVerified = false;
        entry.batchId = 0;
        entry.isPrivate = true;

        _providerData[msg.sender].push(dataId);

        emit DataStored(dataId, msg.sender, dataType, block.timestamp);
        return dataId;
    }

    // Batch operations
    function storeBatch(
        string calldata dataType,
        bytes[] calldata dataArray,
        bytes[] calldata metadataArray,
        bytes[] calldata signatures
    ) external override whenNotPaused nonReentrant returns (uint256) {
        require(hasRole(PROVIDER_ROLE, msg.sender), "ERCData: must have provider role");
        require(dataArray.length == metadataArray.length && dataArray.length == signatures.length, "ERCData: array lengths mismatch");
        require(dataArray.length > 0, "ERCData: empty batch not allowed");
        require(dataArray.length <= MAX_BATCH_SIZE, "ERCData: batch too large");
        require(bytes(dataType).length > 0, "ERCData: dataType cannot be empty");
        require(_dataTypes[dataType].exists, "ERCData: data type not registered");

        uint256 batchId = _nextBatchId++;
        uint256 entriesCount = dataArray.length;

        for (uint256 i = 0; i < entriesCount; i++) {
            require(dataArray[i].length > 0, "ERCData: data cannot be empty");
            require(dataArray[i].length <= MAX_DATA_SIZE, "ERCData: data too large");
            require(metadataArray[i].length <= MAX_METADATA_SIZE, "ERCData: metadata too large");
            // signature requirements removed - optional parameter
            
            uint256 dataId = _nextDataId++;
            
            // Initialize struct fields individually
            DataEntry storage entry = _dataEntries[dataId];
            entry.dataId = dataId;
            entry.provider = msg.sender;
            entry.timestamp = block.timestamp;
            entry.dataType = dataType;
            entry.data = dataArray[i];
            entry.metadata = metadataArray[i];
            entry.signature = signatures[i];
            entry.isVerified = false;
            entry.batchId = batchId;
            entry.isPrivate = false;

            _providerData[msg.sender].push(dataId);
            _batchEntries[batchId].push(dataId); // Add to batch mapping
            emit DataStored(dataId, msg.sender, dataType, block.timestamp);
        }

        emit BatchProcessed(dataType, batchId, entriesCount);
        return batchId;
    }

    // Privacy and access control functions
    function grantAccess(uint256 dataId, address reader) external whenNotPaused nonReentrant {
        require(_dataEntries[dataId].provider != address(0), "ERCData: data does not exist");
        require(_dataEntries[dataId].provider == msg.sender, "ERCData: only provider can grant access");
        require(_dataEntries[dataId].isPrivate, "ERCData: data is not private");
        require(reader != address(0), "ERCData: invalid reader address");

        _accessList[dataId][reader] = true;
        emit AccessGranted(dataId, reader);
    }

    function revokeAccess(uint256 dataId, address reader) external whenNotPaused nonReentrant {
        require(_dataEntries[dataId].provider != address(0), "ERCData: data does not exist");
        require(_dataEntries[dataId].provider == msg.sender, "ERCData: only provider can revoke access");
        require(_dataEntries[dataId].isPrivate, "ERCData: data is not private");

        _accessList[dataId][reader] = false;
        emit AccessRevoked(dataId, reader);
    }

    function grantBatchAccess(uint256 dataId, address[] calldata readers) external whenNotPaused nonReentrant {
        require(_dataEntries[dataId].provider != address(0), "ERCData: data does not exist");
        require(_dataEntries[dataId].provider == msg.sender, "ERCData: only provider can grant access");
        require(_dataEntries[dataId].isPrivate, "ERCData: data is not private");
        require(readers.length > 0, "ERCData: empty readers array");
        require(readers.length <= 100, "ERCData: too many readers"); // Gas limit protection

        for (uint256 i = 0; i < readers.length; i++) {
            require(readers[i] != address(0), "ERCData: invalid reader address");
            _accessList[dataId][readers[i]] = true;
            emit AccessGranted(dataId, readers[i]);
        }
    }

    function hasAccess(uint256 dataId, address reader) external view returns (bool) {
        require(_dataEntries[dataId].provider != address(0), "ERCData: data does not exist");
        
        DataEntry storage entry = _dataEntries[dataId];
        
        // Public data is always accessible
        if (!entry.isPrivate) {
            return true;
        }
        
        // Private data access control
        return entry.provider == reader || 
               _accessList[dataId][reader] || 
               hasRole(DEFAULT_ADMIN_ROLE, reader);
    }

    // Data type management
    function registerDataType(string calldata typeName) external override returns (bool) {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "ERCData: must have admin role");
        require(bytes(typeName).length > 0, "ERCData: typeName cannot be empty");
        require(bytes(typeName).length <= 64, "ERCData: typeName too long");
        require(!_dataTypes[typeName].exists, "ERCData: data type already exists");

        _dataTypes[typeName].name = typeName;
        _dataTypes[typeName].exists = true;

        emit DataTypeRegistered(typeName);
        return true;
    }

    function addField(
        string calldata typeName,
        string calldata fieldName,
        string calldata fieldType,
        bool isIndexed
    ) external override {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "ERCData: must have admin role");
        require(bytes(typeName).length > 0, "ERCData: typeName cannot be empty");
        require(bytes(fieldName).length > 0, "ERCData: fieldName cannot be empty");
        require(bytes(fieldType).length > 0, "ERCData: fieldType cannot be empty");
        require(bytes(fieldName).length <= 32, "ERCData: fieldName too long");
        require(bytes(fieldType).length <= 32, "ERCData: fieldType too long");
        require(_dataTypes[typeName].exists, "ERCData: data type not registered");
        require(bytes(_dataTypes[typeName].fieldTypes[fieldName]).length == 0, "ERCData: field already exists");
        
        _dataTypes[typeName].fieldNames.push(fieldName);
        _dataTypes[typeName].fieldTypes[fieldName] = fieldType;
        _dataTypes[typeName].isIndexed[fieldName] = isIndexed;

        emit FieldAdded(typeName, fieldName, fieldType, isIndexed);
    }

    // Snapshot management
    function createSnapshot(
        string calldata name,
        uint256[] calldata dataIds
    ) external override whenNotPaused returns (bytes32) {
        require(hasRole(SNAPSHOT_ROLE, msg.sender), "ERCData: must have snapshot role");
        require(bytes(name).length > 0, "ERCData: snapshot name cannot be empty");
        require(bytes(name).length <= 64, "ERCData: snapshot name too long");
        require(dataIds.length > 0, "ERCData: empty snapshot not allowed");
        require(dataIds.length <= 1000, "ERCData: snapshot too large"); // Prevent gas issues
        
        bytes32 snapshotId = keccak256(abi.encodePacked(name, block.timestamp, msg.sender, dataIds.length));
        require(_snapshots[snapshotId].timestamp == 0, "ERCData: snapshot collision");
        
        Snapshot storage snapshot = _snapshots[snapshotId];
        snapshot.id = snapshotId;
        snapshot.name = name;
        snapshot.timestamp = block.timestamp;
        snapshot.includedDataIds = dataIds;

        for (uint256 i = 0; i < dataIds.length; i++) {
            require(_dataEntries[dataIds[i]].provider != address(0), "ERCData: data entry does not exist");
            // Note: Duplicate check removed for gas efficiency - duplicates just overwrite the same data
            snapshot.data[dataIds[i]] = _dataEntries[dataIds[i]].data;
        }

        _snapshotIds.push(snapshotId);
        emit SnapshotTaken(snapshotId, name, block.timestamp);
        return snapshotId;
    }

    // View functions
    function getData(uint256 dataId) 
        external 
        view 
        override 
        returns (DataEntryView memory) 
    {
        require(_dataEntries[dataId].provider != address(0), "ERCData: data does not exist");
        DataEntry storage entry = _dataEntries[dataId];
        
        // Access control check
        if (entry.isPrivate) {
            require(
                entry.provider == msg.sender || 
                _accessList[dataId][msg.sender] || 
                hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
                "ERCData: access denied"
            );
        }
        
        return DataEntryView({
            dataId: entry.dataId,
            provider: entry.provider,
            timestamp: entry.timestamp,
            dataType: entry.dataType,
            data: entry.data,
            metadata: entry.metadata,
            signature: entry.signature,
            isVerified: entry.isVerified,
            batchId: entry.batchId,
            isPrivate: entry.isPrivate
        });
    }

    function getField(uint256 dataId, string calldata fieldName)
        external
        view
        override
        returns (bytes memory)
    {
        require(_dataEntries[dataId].provider != address(0), "ERCData: data does not exist");
        DataEntry storage entry = _dataEntries[dataId];
        
        // Access control check
        if (entry.isPrivate) {
            require(
                entry.provider == msg.sender || 
                _accessList[dataId][msg.sender] || 
                hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
                "ERCData: access denied"
            );
        }
        
        return entry.fields[fieldName];
    }

    // Structured field setters
    function setField(uint256 dataId, string calldata fieldName, bytes calldata value)
        external
        override
        whenNotPaused
        nonReentrant
        returns (bool)
    {
        DataEntry storage entry = _dataEntries[dataId];
        require(entry.provider != address(0), "ERCData: data does not exist");
        require(entry.provider == msg.sender, "ERCData: not the data provider");
        require(_fieldExists(entry.dataType, fieldName), "ERCData: field not registered");

        entry.fields[fieldName] = value;
        emit FieldSet(dataId, fieldName);
        return true;
    }

    function setFields(uint256 dataId, string[] calldata fieldNames, bytes[] calldata values)
        external
        override
        whenNotPaused
        nonReentrant
        returns (bool)
    {
        require(fieldNames.length == values.length, "ERCData: array lengths mismatch");
        DataEntry storage entry = _dataEntries[dataId];
        require(entry.provider != address(0), "ERCData: data does not exist");
        require(entry.provider == msg.sender, "ERCData: not the data provider");

        for (uint256 i = 0; i < fieldNames.length; i++) {
            require(_fieldExists(entry.dataType, fieldNames[i]), "ERCData: field not registered");
            entry.fields[fieldNames[i]] = values[i];
            emit FieldSet(dataId, fieldNames[i]);
        }
        return true;
    }

    function getBatchData(uint256 batchId) 
        external 
        view 
        override 
        returns (DataEntryView[] memory) 
    {
        uint256[] memory dataIds = _batchEntries[batchId];
        require(dataIds.length > 0, "ERCData: batch does not exist or is empty");
        
        DataEntryView[] memory entries = new DataEntryView[](dataIds.length);
        
        for (uint256 i = 0; i < dataIds.length; i++) {
            DataEntry storage entry = _dataEntries[dataIds[i]];
            
            // Access control check - if private and no access, skip entry or revert
            if (entry.isPrivate && 
                entry.provider != msg.sender && 
                !_accessList[dataIds[i]][msg.sender] && 
                !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
                // For batch operations, we'll provide empty data for inaccessible entries
                entries[i] = DataEntryView({
                    dataId: entry.dataId,
                    provider: entry.provider,
                    timestamp: entry.timestamp,
                    dataType: entry.dataType,
                    data: new bytes(0), // Empty data for inaccessible entries
                    metadata: new bytes(0), // Empty metadata for inaccessible entries
                    signature: new bytes(0), // Empty signature for inaccessible entries
                    isVerified: entry.isVerified,
                    batchId: entry.batchId,
                    isPrivate: entry.isPrivate
                });
            } else {
                entries[i] = DataEntryView({
                    dataId: entry.dataId,
                    provider: entry.provider,
                    timestamp: entry.timestamp,
                    dataType: entry.dataType,
                    data: entry.data,
                    metadata: entry.metadata,
                    signature: entry.signature,
                    isVerified: entry.isVerified,
                    batchId: entry.batchId,
                    isPrivate: entry.isPrivate
                });
            }
        }

        return entries;
    }

    function getDataTypeInfo(string calldata typeName) 
        external 
        view 
        override 
        returns (DataTypeInfoView memory) 
    {
        require(_dataTypes[typeName].exists, "ERCData: data type not registered");
        DataTypeInfo storage info = _dataTypes[typeName];
        
        string[] memory types = new string[](info.fieldNames.length);
        bool[] memory isIndexedArr = new bool[](info.fieldNames.length);
        
        for (uint256 i = 0; i < info.fieldNames.length; i++) {
            types[i] = info.fieldTypes[info.fieldNames[i]];
            isIndexedArr[i] = info.isIndexed[info.fieldNames[i]];
        }
        
        return DataTypeInfoView({
            name: info.name,
            exists: info.exists,
            fieldNames: info.fieldNames,
            fieldTypes: types,
            isIndexed: isIndexedArr
        });
    }

    function getSnapshot(bytes32 snapshotId) 
        external 
        view 
        override 
        returns (SnapshotView memory) 
    {
        require(_snapshots[snapshotId].timestamp > 0, "ERCData: snapshot does not exist");
        Snapshot storage snapshot = _snapshots[snapshotId];
        
        bytes[] memory snapshotData = new bytes[](snapshot.includedDataIds.length);
        for (uint256 i = 0; i < snapshot.includedDataIds.length; i++) {
            snapshotData[i] = snapshot.data[snapshot.includedDataIds[i]];
        }
        
        return SnapshotView({
            id: snapshot.id,
            name: snapshot.name,
            timestamp: snapshot.timestamp,
            includedDataIds: snapshot.includedDataIds,
            data: snapshotData
        });
    }

    function listSnapshots() 
        external 
        view 
        override 
        returns (bytes32[] memory) 
    {
        return _snapshotIds;
    }

    function verifyData(uint256 dataId, bytes calldata verificationData)
        external
        override
        whenNotPaused
        nonReentrant
        returns (bool)
    {
        require(hasRole(VERIFIER_ROLE, msg.sender), "ERCData: must have verifier role");
        require(_dataEntries[dataId].provider != address(0), "ERCData: data does not exist");

        (bool isValid, string memory method) = _verifyDataIntegrity(dataId, verificationData);

        _verifications[dataId] = VerificationInfo({
            verifier: msg.sender,
            timestamp: block.timestamp,
            isValid: isValid,
            verificationMethod: method,
            verificationData: verificationData
        });

        _dataEntries[dataId].isVerified = isValid;

        emit DataVerified(dataId, msg.sender, isValid, block.timestamp);
        return isValid;
    }

    function verifyBatch(uint256 batchId, bytes calldata verificationData)
        external
        override
        whenNotPaused
        nonReentrant
        returns (bool)
    {
        require(hasRole(VERIFIER_ROLE, msg.sender), "ERCData: must have verifier role");
        
        uint256[] memory dataIds = _batchEntries[batchId];
        require(dataIds.length > 0, "ERCData: batch does not exist or is empty");
        
        bool aggregateValid = true;
        for (uint256 i = 0; i < dataIds.length; i++) {
            uint256 dataId = dataIds[i];
            (bool ok, string memory method) = _verifyDataIntegrity(dataId, verificationData);

            // Record per-entry verification info and state
            _verifications[dataId] = VerificationInfo({
                verifier: msg.sender,
                timestamp: block.timestamp,
                isValid: ok,
                verificationMethod: method,
                verificationData: verificationData
            });
            _dataEntries[dataId].isVerified = ok;

            emit DataVerified(dataId, msg.sender, ok, block.timestamp);
            aggregateValid = aggregateValid && ok;
        }

        emit BatchVerified(batchId, msg.sender, aggregateValid);
        return aggregateValid;
    }

    function updateData(
        uint256 dataId,
        bytes calldata newData,
        bytes calldata newMetadata,
        bytes calldata signature
    ) external override whenNotPaused nonReentrant returns (bool) {
        DataEntry storage entry = _dataEntries[dataId];
        require(entry.provider != address(0), "ERCData: data does not exist");
        require(entry.provider == msg.sender, "ERCData: not the data provider");
        require(newData.length > 0, "ERCData: new data cannot be empty");
        require(newData.length <= MAX_DATA_SIZE, "ERCData: new data too large");
        require(newMetadata.length <= MAX_METADATA_SIZE, "ERCData: new metadata too large");
        // signature requirements removed - optional parameter

        entry.data = newData;
        entry.metadata = newMetadata;
        entry.signature = signature;
        entry.timestamp = block.timestamp;
        entry.isVerified = false;

        // Reset verification when data is updated
        delete _verifications[dataId];

        emit DataUpdated(dataId, msg.sender, block.timestamp);
        return true;
    }

    function getVerificationInfo(uint256 dataId)
        external
        view
        override
        returns (VerificationInfo memory)
    {
        require(_dataEntries[dataId].provider != address(0), "ERCData: data does not exist");
        return _verifications[dataId];
    }

    // Internal functions
    function _verifyDataIntegrity(uint256 dataId, bytes calldata verificationData)
        internal
        view
        returns (bool, string memory)
    {
        DataEntry storage entry = _dataEntries[dataId];
        require(entry.provider != address(0), "ERCData: data entry does not exist");

        // Expect verificationData to be abi.encode(selector) or abi.encode(selector, payload)
        if (verificationData.length == 32) {
            bytes4 selector = abi.decode(verificationData, (bytes4));
            require(selector == VERIF_EIP712, "ERCData: invalid selector for length");

            // EIP-712 provider signature verification
            bytes32 dataHash = keccak256(entry.data);
            bytes32 metadataHash = keccak256(entry.metadata);
            bytes32 structHash = keccak256(
                abi.encode(
                    DATA_ENTRY_TYPEHASH,
                    dataHash,
                    metadataHash,
                    keccak256(bytes(entry.dataType)),
                    entry.provider
                )
            );
            bytes32 digest = _hashTypedDataV4(structHash);

            // Protect against signature malleability and zero address
            if (entry.signature.length != 65) {
                return (false, "EIP712_PROVIDER_SIG");
            }
            
            address recovered = ECDSA.recover(digest, entry.signature);
            bool ok = (recovered == entry.provider && recovered != address(0));
            return (ok, "EIP712_PROVIDER_SIG");
        } else if (verificationData.length == 64) {
            (bytes4 selector, bytes32 expectedHash) = abi.decode(verificationData, (bytes4, bytes32));
            require(selector == VERIF_HASH, "ERCData: unknown selector");
            require(expectedHash != bytes32(0), "ERCData: invalid hash");
            bool ok = (keccak256(entry.data) == expectedHash);
            return (ok, "DATA_HASH_EQ");
        } else {
            revert("ERCData: invalid verificationData format");
        }
    }

    function _fieldExists(string memory typeName, string memory fieldName) internal view returns (bool) {
        if (!_dataTypes[typeName].exists) return false;
        // If a field was added, it must have a non-empty type string
        string memory t = _dataTypes[typeName].fieldTypes[fieldName];
        return bytes(t).length != 0;
    }

    // Admin functions for emergency management
    function pause() external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "ERCData: must have admin role");
        _pause();
    }

    function unpause() external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "ERCData: must have admin role");
        _unpause();
    }

    // View function to get batch info without data
    function getBatchInfo(uint256 batchId) external view returns (uint256[] memory dataIds, uint256 count) {
        dataIds = _batchEntries[batchId];
        count = dataIds.length;
    }

    // Emergency function to remove corrupted batch mapping (admin only)
    function removeBatchMapping(uint256 batchId) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "ERCData: must have admin role");
        require(_batchEntries[batchId].length > 0, "ERCData: batch does not exist");
        
        delete _batchEntries[batchId];
    }
}
