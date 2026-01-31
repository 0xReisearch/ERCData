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
    // Custom errors (saves ~3KB vs string reverts)
    error Unauthorized();
    error NotFound();
    error InvalidInput();
    error AccessDenied();
    error AlreadyExists();
    error TooLarge();

    struct Snapshot {
        bytes32 id;
        string name;
        uint256 timestamp;
        mapping(uint256 => bytes) data;
        uint256[] includedDataIds;
    }

    bytes32 public constant PROVIDER_ROLE = keccak256("PROVIDER_ROLE");
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    bytes32 public constant SNAPSHOT_ROLE = keccak256("SNAPSHOT_ROLE");

    mapping(uint256 => DataEntry) private _entries;
    mapping(uint256 => VerificationInfo) private _verifications;
    mapping(address => uint256[]) private _providerData;
    mapping(string => DataTypeInfo) private _dataTypes;
    mapping(bytes32 => Snapshot) private _snapshots;
    mapping(uint256 => uint256[]) private _batchEntries;
    mapping(uint256 => mapping(address => bool)) private _accessList;

    bytes32[] private _snapshotIds;
    uint256 private _nextDataId;
    uint256 private _nextBatchId;

    bytes4 private constant SEL_EIP712 = 0x45503132;
    bytes4 private constant SEL_HASH = 0x48415348;

    bytes32 private constant DATA_ENTRY_TYPEHASH = keccak256(
        "ERCDataEntry(bytes32 dataHash,bytes32 metadataHash,string dataType,address provider)"
    );

    uint256 private constant MAX_DATA = 1048576;     // 1MB
    uint256 private constant MAX_META = 65536;        // 64KB
    uint256 private constant MAX_BATCH = 100;

    constructor() EIP712("ERCData", "1") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SNAPSHOT_ROLE, msg.sender);
        _nextDataId = 1;
        _nextBatchId = 1;
    }

    // ── Internal store logic (deduplicates storeData/storePrivateData) ──

    function _store(
        string calldata dataType,
        bytes calldata data,
        bytes calldata metadata,
        bytes calldata signature,
        bool isPrivate
    ) internal returns (uint256) {
        if (!hasRole(PROVIDER_ROLE, msg.sender)) revert Unauthorized();
        if (bytes(dataType).length == 0 || data.length == 0) revert InvalidInput();
        if (data.length > MAX_DATA || metadata.length > MAX_META) revert TooLarge();
        if (!_dataTypes[dataType].exists) revert NotFound();

        uint256 dataId = _nextDataId++;
        DataEntry storage e = _entries[dataId];
        e.dataId = dataId;
        e.provider = msg.sender;
        e.timestamp = block.timestamp;
        e.dataType = dataType;
        e.data = data;
        e.metadata = metadata;
        e.signature = signature;
        e.isPrivate = isPrivate;

        _providerData[msg.sender].push(dataId);
        emit DataStored(dataId, msg.sender, dataType, block.timestamp);
        return dataId;
    }

    function storeData(
        string calldata dataType, bytes calldata data,
        bytes calldata metadata, bytes calldata signature
    ) external override whenNotPaused nonReentrant returns (uint256) {
        return _store(dataType, data, metadata, signature, false);
    }

    function storePrivateData(
        string calldata dataType, bytes calldata data,
        bytes calldata metadata, bytes calldata signature
    ) external override whenNotPaused nonReentrant returns (uint256) {
        return _store(dataType, data, metadata, signature, true);
    }

    // ── Batch ──

    function storeBatch(
        string calldata dataType, bytes[] calldata dataArr,
        bytes[] calldata metaArr, bytes[] calldata sigArr
    ) external override whenNotPaused nonReentrant returns (uint256) {
        if (!hasRole(PROVIDER_ROLE, msg.sender)) revert Unauthorized();
        uint256 n = dataArr.length;
        if (n == 0 || n != metaArr.length || n != sigArr.length) revert InvalidInput();
        if (n > MAX_BATCH) revert TooLarge();
        if (bytes(dataType).length == 0 || !_dataTypes[dataType].exists) revert InvalidInput();

        uint256 batchId = _nextBatchId++;
        for (uint256 i; i < n;) {
            if (dataArr[i].length == 0 || dataArr[i].length > MAX_DATA) revert InvalidInput();
            if (metaArr[i].length > MAX_META) revert TooLarge();

            uint256 dataId = _nextDataId++;
            DataEntry storage e = _entries[dataId];
            e.dataId = dataId;
            e.provider = msg.sender;
            e.timestamp = block.timestamp;
            e.dataType = dataType;
            e.data = dataArr[i];
            e.metadata = metaArr[i];
            e.signature = sigArr[i];
            e.batchId = batchId;

            _providerData[msg.sender].push(dataId);
            _batchEntries[batchId].push(dataId);
            emit DataStored(dataId, msg.sender, dataType, block.timestamp);
            unchecked { ++i; }
        }
        emit BatchProcessed(dataType, batchId, n);
        return batchId;
    }

    // ── Access control ──

    function _requirePrivateOwner(uint256 dataId) internal view {
        DataEntry storage e = _entries[dataId];
        if (e.provider == address(0)) revert NotFound();
        if (e.provider != msg.sender) revert Unauthorized();
        if (!e.isPrivate) revert InvalidInput();
    }

    function grantAccess(uint256 dataId, address reader) external override whenNotPaused {
        _requirePrivateOwner(dataId);
        if (reader == address(0)) revert InvalidInput();
        _accessList[dataId][reader] = true;
        emit AccessGranted(dataId, reader);
    }

    function revokeAccess(uint256 dataId, address reader) external override whenNotPaused {
        _requirePrivateOwner(dataId);
        _accessList[dataId][reader] = false;
        emit AccessRevoked(dataId, reader);
    }

    function grantBatchAccess(uint256 dataId, address[] calldata readers) external override whenNotPaused {
        _requirePrivateOwner(dataId);
        uint256 n = readers.length;
        if (n == 0 || n > 100) revert InvalidInput();
        for (uint256 i; i < n;) {
            if (readers[i] == address(0)) revert InvalidInput();
            _accessList[dataId][readers[i]] = true;
            emit AccessGranted(dataId, readers[i]);
            unchecked { ++i; }
        }
    }

    function hasAccess(uint256 dataId, address reader) external view override returns (bool) {
        DataEntry storage e = _entries[dataId];
        if (e.provider == address(0)) revert NotFound();
        if (!e.isPrivate) return true;
        return e.provider == reader || _accessList[dataId][reader] || hasRole(DEFAULT_ADMIN_ROLE, reader);
    }

    // ── Data type management ──

    function registerDataType(string calldata typeName) external override returns (bool) {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert Unauthorized();
        if (bytes(typeName).length == 0 || bytes(typeName).length > 64) revert InvalidInput();
        if (_dataTypes[typeName].exists) revert AlreadyExists();
        _dataTypes[typeName].name = typeName;
        _dataTypes[typeName].exists = true;
        emit DataTypeRegistered(typeName);
        return true;
    }

    function addField(
        string calldata typeName, string calldata fieldName,
        string calldata fieldType, bool isIndexed
    ) external override {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert Unauthorized();
        if (bytes(fieldName).length == 0 || bytes(fieldType).length == 0) revert InvalidInput();
        if (bytes(fieldName).length > 32 || bytes(fieldType).length > 32) revert TooLarge();
        if (!_dataTypes[typeName].exists) revert NotFound();
        if (bytes(_dataTypes[typeName].fieldTypes[fieldName]).length != 0) revert AlreadyExists();

        _dataTypes[typeName].fieldNames.push(fieldName);
        _dataTypes[typeName].fieldTypes[fieldName] = fieldType;
        _dataTypes[typeName].isIndexed[fieldName] = isIndexed;
        emit FieldAdded(typeName, fieldName, fieldType, isIndexed);
    }

    // ── Snapshots ──

    function createSnapshot(
        string calldata name, uint256[] calldata dataIds
    ) external override whenNotPaused returns (bytes32) {
        if (!hasRole(SNAPSHOT_ROLE, msg.sender)) revert Unauthorized();
        if (bytes(name).length == 0 || bytes(name).length > 64) revert InvalidInput();
        uint256 n = dataIds.length;
        if (n == 0 || n > 1000) revert InvalidInput();

        bytes32 sid = keccak256(abi.encodePacked(name, block.timestamp, msg.sender, n));
        if (_snapshots[sid].timestamp != 0) revert AlreadyExists();

        Snapshot storage s = _snapshots[sid];
        s.id = sid;
        s.name = name;
        s.timestamp = block.timestamp;
        s.includedDataIds = dataIds;

        for (uint256 i; i < n;) {
            if (_entries[dataIds[i]].provider == address(0)) revert NotFound();
            s.data[dataIds[i]] = _entries[dataIds[i]].data;
            unchecked { ++i; }
        }
        _snapshotIds.push(sid);
        emit SnapshotTaken(sid, name, block.timestamp);
        return sid;
    }

    // ── View: access-checked helper ──

    function _checkAccess(uint256 dataId) internal view {
        DataEntry storage e = _entries[dataId];
        if (e.provider == address(0)) revert NotFound();
        if (e.isPrivate &&
            e.provider != msg.sender &&
            !_accessList[dataId][msg.sender] &&
            !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)
        ) revert AccessDenied();
    }

    function _toView(DataEntry storage e) internal view returns (DataEntryView memory) {
        return DataEntryView(
            e.dataId, e.provider, e.timestamp, e.dataType,
            e.data, e.metadata, e.signature,
            e.isVerified, e.batchId, e.isPrivate
        );
    }

    // ── View functions ──

    function getData(uint256 dataId) external view override returns (DataEntryView memory) {
        _checkAccess(dataId);
        return _toView(_entries[dataId]);
    }

    function getField(uint256 dataId, string calldata fieldName) external view override returns (bytes memory) {
        _checkAccess(dataId);
        return _entries[dataId].fields[fieldName];
    }

    function setField(uint256 dataId, string calldata fieldName, bytes calldata value)
        external override whenNotPaused nonReentrant returns (bool)
    {
        DataEntry storage e = _entries[dataId];
        if (e.provider == address(0)) revert NotFound();
        if (e.provider != msg.sender) revert Unauthorized();
        if (!_fieldExists(e.dataType, fieldName)) revert NotFound();
        e.fields[fieldName] = value;
        emit FieldSet(dataId, fieldName);
        return true;
    }

    function setFields(uint256 dataId, string[] calldata names, bytes[] calldata vals)
        external override whenNotPaused nonReentrant returns (bool)
    {
        if (names.length != vals.length) revert InvalidInput();
        DataEntry storage e = _entries[dataId];
        if (e.provider == address(0)) revert NotFound();
        if (e.provider != msg.sender) revert Unauthorized();
        for (uint256 i; i < names.length;) {
            if (!_fieldExists(e.dataType, names[i])) revert NotFound();
            e.fields[names[i]] = vals[i];
            emit FieldSet(dataId, names[i]);
            unchecked { ++i; }
        }
        return true;
    }

    function getBatchData(uint256 batchId) external view override returns (DataEntryView[] memory) {
        uint256[] memory ids = _batchEntries[batchId];
        if (ids.length == 0) revert NotFound();
        DataEntryView[] memory out = new DataEntryView[](ids.length);
        for (uint256 i; i < ids.length;) {
            DataEntry storage e = _entries[ids[i]];
            if (e.isPrivate && e.provider != msg.sender &&
                !_accessList[ids[i]][msg.sender] && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
                // Redact private entries caller can't access
                out[i] = DataEntryView(
                    e.dataId, e.provider, e.timestamp, e.dataType,
                    "", "", "", e.isVerified, e.batchId, true
                );
            } else {
                out[i] = _toView(e);
            }
            unchecked { ++i; }
        }
        return out;
    }

    function getDataTypeInfo(string calldata typeName) external view override returns (DataTypeInfoView memory) {
        if (!_dataTypes[typeName].exists) revert NotFound();
        DataTypeInfo storage info = _dataTypes[typeName];
        uint256 n = info.fieldNames.length;
        string[] memory types = new string[](n);
        bool[] memory idx = new bool[](n);
        for (uint256 i; i < n;) {
            types[i] = info.fieldTypes[info.fieldNames[i]];
            idx[i] = info.isIndexed[info.fieldNames[i]];
            unchecked { ++i; }
        }
        return DataTypeInfoView(info.name, true, info.fieldNames, types, idx);
    }

    function getSnapshot(bytes32 sid) external view override returns (SnapshotView memory) {
        if (_snapshots[sid].timestamp == 0) revert NotFound();
        Snapshot storage s = _snapshots[sid];
        uint256 n = s.includedDataIds.length;
        bytes[] memory d = new bytes[](n);
        for (uint256 i; i < n;) {
            d[i] = s.data[s.includedDataIds[i]];
            unchecked { ++i; }
        }
        return SnapshotView(s.id, s.name, s.timestamp, s.includedDataIds, d);
    }

    function listSnapshots() external view override returns (bytes32[] memory) {
        return _snapshotIds;
    }

    // ── Verification ──

    function verifyData(uint256 dataId, bytes calldata vData)
        external override whenNotPaused nonReentrant returns (bool)
    {
        if (!hasRole(VERIFIER_ROLE, msg.sender)) revert Unauthorized();
        if (_entries[dataId].provider == address(0)) revert NotFound();

        (bool ok, string memory method) = _verify(dataId, vData);
        _verifications[dataId] = VerificationInfo(msg.sender, block.timestamp, ok, method, vData);
        _entries[dataId].isVerified = ok;
        emit DataVerified(dataId, msg.sender, ok, block.timestamp);
        return ok;
    }

    function verifyBatch(uint256 batchId, bytes calldata vData)
        external override whenNotPaused nonReentrant returns (bool)
    {
        if (!hasRole(VERIFIER_ROLE, msg.sender)) revert Unauthorized();
        uint256[] memory ids = _batchEntries[batchId];
        if (ids.length == 0) revert NotFound();

        bool all = true;
        for (uint256 i; i < ids.length;) {
            (bool ok, string memory method) = _verify(ids[i], vData);
            _verifications[ids[i]] = VerificationInfo(msg.sender, block.timestamp, ok, method, vData);
            _entries[ids[i]].isVerified = ok;
            emit DataVerified(ids[i], msg.sender, ok, block.timestamp);
            if (!ok) all = false;
            unchecked { ++i; }
        }
        emit BatchVerified(batchId, msg.sender, all);
        return all;
    }

    function updateData(
        uint256 dataId, bytes calldata newData,
        bytes calldata newMeta, bytes calldata sig
    ) external override whenNotPaused nonReentrant returns (bool) {
        DataEntry storage e = _entries[dataId];
        if (e.provider == address(0)) revert NotFound();
        if (e.provider != msg.sender) revert Unauthorized();
        if (newData.length == 0 || newData.length > MAX_DATA) revert InvalidInput();
        if (newMeta.length > MAX_META) revert TooLarge();

        e.data = newData;
        e.metadata = newMeta;
        e.signature = sig;
        e.timestamp = block.timestamp;
        e.isVerified = false;
        delete _verifications[dataId];
        emit DataUpdated(dataId, msg.sender, block.timestamp);
        return true;
    }

    function getVerificationInfo(uint256 dataId) external view override returns (VerificationInfo memory) {
        if (_entries[dataId].provider == address(0)) revert NotFound();
        return _verifications[dataId];
    }

    // ── Internal ──

    function _verify(uint256 dataId, bytes calldata vData) internal view returns (bool, string memory) {
        DataEntry storage e = _entries[dataId];
        if (e.provider == address(0)) revert NotFound();

        if (vData.length == 32) {
            bytes4 sel = abi.decode(vData, (bytes4));
            if (sel != SEL_EIP712) revert InvalidInput();

            bytes32 structHash = keccak256(abi.encode(
                DATA_ENTRY_TYPEHASH,
                keccak256(e.data),
                keccak256(e.metadata),
                keccak256(bytes(e.dataType)),
                e.provider
            ));
            bytes32 digest = _hashTypedDataV4(structHash);

            if (e.signature.length != 65) return (false, "EIP712_PROVIDER_SIG");
            address recovered = ECDSA.recover(digest, e.signature);
            return (recovered == e.provider && recovered != address(0), "EIP712_PROVIDER_SIG");
        } else if (vData.length == 64) {
            (bytes4 sel, bytes32 expected) = abi.decode(vData, (bytes4, bytes32));
            if (sel != SEL_HASH) revert InvalidInput();
            if (expected == bytes32(0)) revert InvalidInput();
            return (keccak256(e.data) == expected, "DATA_HASH_EQ");
        } else {
            revert InvalidInput();
        }
    }

    function _fieldExists(string memory typeName, string memory fieldName) internal view returns (bool) {
        if (!_dataTypes[typeName].exists) return false;
        return bytes(_dataTypes[typeName].fieldTypes[fieldName]).length != 0;
    }

    // ── Admin ──

    function pause() external {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert Unauthorized();
        _pause();
    }

    function unpause() external {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert Unauthorized();
        _unpause();
    }
}
