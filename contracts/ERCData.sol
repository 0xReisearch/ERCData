// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IERCData.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title ERCData
 * @dev Reference implementation of the ERCData standard for AI data storage
 */
contract ERCData is IERCData, AccessControl, Pausable, ReentrancyGuard {
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
    
    bytes32[] private _snapshotIds;
    uint256 private _nextDataId;
    uint256 private _nextBatchId;

    // Constructor
    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(SNAPSHOT_ROLE, msg.sender);
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
        require(_dataTypes[dataType].exists, "ERCData: data type not registered");

        uint256 batchId = _nextBatchId++;
        uint256 entriesCount = dataArray.length;

        for (uint256 i = 0; i < entriesCount; i++) {
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

            _providerData[msg.sender].push(dataId);
            emit DataStored(dataId, msg.sender, dataType, block.timestamp);
        }

        emit BatchProcessed(dataType, batchId, entriesCount);
        return batchId;
    }

    // Data type management
    function registerDataType(string calldata typeName) external override returns (bool) {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "ERCData: must have admin role");
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
        require(_dataTypes[typeName].exists, "ERCData: data type not registered");
        
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
        
        bytes32 snapshotId = keccak256(abi.encodePacked(name, block.timestamp, msg.sender));
        Snapshot storage snapshot = _snapshots[snapshotId];
        
        snapshot.id = snapshotId;
        snapshot.name = name;
        snapshot.timestamp = block.timestamp;
        snapshot.includedDataIds = dataIds;

        for (uint256 i = 0; i < dataIds.length; i++) {
            require(_dataEntries[dataIds[i]].provider != address(0), "ERCData: data entry does not exist");
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
        return DataEntryView({
            dataId: entry.dataId,
            provider: entry.provider,
            timestamp: entry.timestamp,
            dataType: entry.dataType,
            data: entry.data,
            metadata: entry.metadata,
            signature: entry.signature,
            isVerified: entry.isVerified,
            batchId: entry.batchId
        });
    }

    function getField(uint256 dataId, string calldata fieldName)
        external
        view
        override
        returns (bytes memory)
    {
        require(_dataEntries[dataId].provider != address(0), "ERCData: data does not exist");
        return _dataEntries[dataId].fields[fieldName];
    }

    function getBatchData(uint256 batchId) 
        external 
        view 
        override 
        returns (DataEntryView[] memory) 
    {
        uint256 count = 0;
        for (uint256 i = 1; i < _nextDataId; i++) {
            if (_dataEntries[i].batchId == batchId) {
                count++;
            }
        }

        DataEntryView[] memory entries = new DataEntryView[](count);
        uint256 index = 0;
        
        for (uint256 i = 1; i < _nextDataId; i++) {
            if (_dataEntries[i].batchId == batchId) {
                DataEntry storage entry = _dataEntries[i];
                entries[index] = DataEntryView({
                    dataId: entry.dataId,
                    provider: entry.provider,
                    timestamp: entry.timestamp,
                    dataType: entry.dataType,
                    data: entry.data,
                    metadata: entry.metadata,
                    signature: entry.signature,
                    isVerified: entry.isVerified,
                    batchId: entry.batchId
                });
                index++;
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

        bool isValid = _verifyDataIntegrity(dataId, verificationData);

        _verifications[dataId] = VerificationInfo({
            verifier: msg.sender,
            timestamp: block.timestamp,
            isValid: isValid,
            verificationMethod: "STANDARD",
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
        
        bool isValid = true;
        for (uint256 i = 1; i < _nextDataId; i++) {
            if (_dataEntries[i].batchId == batchId) {
                isValid = isValid && _verifyDataIntegrity(i, verificationData);
                if (!isValid) break;
            }
        }

        emit BatchVerified(batchId, msg.sender, isValid);
        return isValid;
    }

    function updateData(
        uint256 dataId,
        bytes calldata newData,
        bytes calldata newMetadata,
        bytes calldata signature
    ) external override whenNotPaused nonReentrant returns (bool) {
        DataEntry storage entry = _dataEntries[dataId];
        require(entry.provider == msg.sender, "ERCData: not the data provider");
        require(newData.length > 0, "ERCData: new data cannot be empty");

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
        returns (bool)
    {
        // This is a placeholder for actual verification logic
        // Implementations should override this with their specific verification method
        return true;
    }
} 