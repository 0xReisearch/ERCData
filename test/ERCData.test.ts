import { expect } from "chai";
import { ethers } from "hardhat";
import { ERCData } from "../typechain-types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Contract } from "ethers";
import { keccak256, defaultAbiCoder } from "ethers/lib/utils";

describe("ERCData", function () {
    let ercData: ERCData;
    let owner: SignerWithAddress;
    let provider: SignerWithAddress;
    let verifier: SignerWithAddress;
    let user: SignerWithAddress;

    // Test data
    const TEST_DATA_TYPE = "AI_MODEL_WEIGHTS";
    const TEST_DATA = ethers.utils.toUtf8Bytes("model weights data");
    const TEST_METADATA = ethers.utils.toUtf8Bytes('{"version": "1.0", "architecture": "transformer"}');
    // Selectors for verification encodings
    const SEL_EIP712 = "0x45503132"; // EP12
    const SEL_HASH = "0x48415348";  // HASH

    async function signEntry(
        signer: SignerWithAddress,
        contract: ERCData,
        dataType: string,
        data: Uint8Array,
        metadata: Uint8Array
    ): Promise<string> {
        const network = await ethers.provider.getNetwork();
        const domain = {
            name: "ERCData",
            version: "1",
            chainId: network.chainId,
            verifyingContract: contract.address,
        };
        const types = {
            ERCDataEntry: [
                { name: "dataHash", type: "bytes32" },
                { name: "metadataHash", type: "bytes32" },
                { name: "dataType", type: "string" },
                { name: "provider", type: "address" },
            ],
        } as const;
        const value = {
            dataHash: keccak256(data),
            metadataHash: keccak256(metadata),
            dataType,
            provider: signer.address,
        };
        return await signer._signTypedData(domain, types as any, value);
    }

    beforeEach(async function () {
        // Get signers
        [owner, provider, verifier, user] = await ethers.getSigners();

        // Deploy contract
        const ERCDataFactory = await ethers.getContractFactory("ERCData");
        ercData = (await ERCDataFactory.deploy()) as ERCData;
        await ercData.deployed();

        // Setup roles
        await ercData.grantRole(await ercData.PROVIDER_ROLE(), provider.address);
        await ercData.grantRole(await ercData.VERIFIER_ROLE(), verifier.address);
        await ercData.grantRole(await ercData.SNAPSHOT_ROLE(), owner.address);

        // Register test data type
        await ercData.registerDataType(TEST_DATA_TYPE);
    });

    describe("Role Management", function () {
        it("Should set correct roles during deployment", async function () {
            expect(await ercData.hasRole(await ercData.DEFAULT_ADMIN_ROLE(), owner.address)).to.be.true;
            expect(await ercData.hasRole(await ercData.PROVIDER_ROLE(), provider.address)).to.be.true;
            expect(await ercData.hasRole(await ercData.VERIFIER_ROLE(), verifier.address)).to.be.true;
        });

        it("Should prevent unauthorized role assignments", async function () {
            await expect(
                ercData.connect(user).grantRole(await ercData.PROVIDER_ROLE(), user.address)
            ).to.be.reverted;
        });
    });

    describe("Data Type Management", function () {
        it("Should register new data type", async function () {
            const newType = "NEW_TYPE";
            await ercData.registerDataType(newType);
            const typeInfo = await ercData.getDataTypeInfo(newType);
            expect(typeInfo.exists).to.be.true;
        });

        it("Should add fields to data type", async function () {
            await ercData.addField(TEST_DATA_TYPE, "accuracy", "uint256", true);
            const typeInfo = await ercData.getDataTypeInfo(TEST_DATA_TYPE);
            expect(typeInfo.fieldNames.length).to.equal(1);
        });

        it("Should prevent duplicate data type registration", async function () {
            await expect(
                ercData.registerDataType(TEST_DATA_TYPE)
            ).to.be.revertedWith("ERCData: data type already exists");
        });
    });

    describe("Structured Fields", function () {
        let dataId: number;

        beforeEach(async function () {
            await ercData.addField(TEST_DATA_TYPE, "accuracy", "uint256", true);
            await ercData.addField(TEST_DATA_TYPE, "author", "string", false);
            const signature = await signEntry(provider, ercData, TEST_DATA_TYPE, TEST_DATA, TEST_METADATA);
            const tx = await ercData.connect(provider).storeData(
                TEST_DATA_TYPE,
                TEST_DATA,
                TEST_METADATA,
                ethers.utils.arrayify(signature)
            );
            const rc = await tx.wait();
            dataId = rc.events?.find(e => e.event === "DataStored")?.args?.[0].toNumber();
        });

        it("Should allow provider to set and read a field", async function () {
            const value = ethers.utils.defaultAbiCoder.encode(["uint256"], [95]);
            await ercData.connect(provider).setField(dataId, "accuracy", value);
            const raw = await ercData.getField(dataId, "accuracy");
            const [decoded] = ethers.utils.defaultAbiCoder.decode(["uint256"], raw);
            expect(decoded.toNumber()).to.equal(95);
        });

        it("Should batch set multiple fields", async function () {
            const values = [
                ethers.utils.defaultAbiCoder.encode(["uint256"], [88]),
                ethers.utils.toUtf8Bytes("alice"),
            ];
            await ercData.connect(provider).setFields(dataId, ["accuracy", "author"], values);
            const accRaw = await ercData.getField(dataId, "accuracy");
            const [acc] = ethers.utils.defaultAbiCoder.decode(["uint256"], accRaw);
            expect(acc.toNumber()).to.equal(88);
            const authorRaw = await ercData.getField(dataId, "author");
            expect(ethers.utils.toUtf8String(authorRaw)).to.equal("alice");
        });

        it("Should prevent non-provider from setting a field", async function () {
            const value = ethers.utils.defaultAbiCoder.encode(["uint256"], [42]);
            await expect(
                ercData.connect(user).setField(dataId, "accuracy", value)
            ).to.be.revertedWith("ERCData: not the data provider");
        });

        it("Should revert when field not registered", async function () {
            const value = ethers.utils.defaultAbiCoder.encode(["uint256"], [1]);
            await expect(
                ercData.connect(provider).setField(dataId, "unknownField", value)
            ).to.be.revertedWith("ERCData: field not registered");
        });
    });

    describe("Data Storage", function () {
        it("Should store data correctly", async function () {
            const signature = await signEntry(provider, ercData, TEST_DATA_TYPE, TEST_DATA, TEST_METADATA);
            const tx = await ercData.connect(provider).storeData(
                TEST_DATA_TYPE,
                TEST_DATA,
                TEST_METADATA,
                ethers.utils.arrayify(signature)
            );
            const receipt = await tx.wait();
            const event = receipt.events?.find(e => e.event === "DataStored");
            expect(event).to.not.be.undefined;

            // Extract dataId from event args
            const dataId = event?.args?.[0].toNumber();
            expect(dataId).to.not.be.undefined;

            const storedData = await ercData.getData(dataId);
            
            expect(storedData.dataType).to.equal(TEST_DATA_TYPE);
            expect(storedData.provider).to.equal(provider.address);
            expect(storedData.isVerified).to.be.false;
        });

        it("Should prevent unauthorized data storage", async function () {
            await expect(
                ercData.connect(user).storeData(
                    TEST_DATA_TYPE,
                    TEST_DATA,
                    TEST_METADATA,
                    ethers.utils.toUtf8Bytes("sig")
                )
            ).to.be.revertedWith("ERCData: must have provider role");
        });
    });

    describe("Batch Operations", function () {
        it("Should store batch data correctly", async function () {
            const dataArray = [TEST_DATA, TEST_DATA];
            const metadataArray = [TEST_METADATA, TEST_METADATA];
            const sig = await signEntry(provider, ercData, TEST_DATA_TYPE, TEST_DATA, TEST_METADATA);
            const signatureArray = [ethers.utils.arrayify(sig), ethers.utils.arrayify(sig)];

            const tx = await ercData.connect(provider).storeBatch(
                TEST_DATA_TYPE,
                dataArray,
                metadataArray,
                signatureArray
            );
            const receipt = await tx.wait();
            const event = receipt.events?.find(e => e.event === "BatchProcessed");
            expect(event).to.not.be.undefined;
            expect(event?.args?.[2].toNumber()).to.equal(2); // entriesCount is the third argument
        });

        it("Should verify batch correctly and mark entries", async function () {
            const dataArray = [TEST_DATA, TEST_DATA];
            const metadataArray = [TEST_METADATA, TEST_METADATA];
            const sig = await signEntry(provider, ercData, TEST_DATA_TYPE, TEST_DATA, TEST_METADATA);
            const signatureArray = [ethers.utils.arrayify(sig), ethers.utils.arrayify(sig)];

            const tx = await ercData.connect(provider).storeBatch(
                TEST_DATA_TYPE,
                dataArray,
                metadataArray,
                signatureArray
            );
            const receipt = await tx.wait();
            const event = receipt.events?.find(e => e.event === "BatchProcessed");
            const batchId = event?.args?.[1].toNumber(); // batchId is the second argument
            expect(batchId).to.not.be.undefined;

            const enc = defaultAbiCoder.encode(["bytes4"], [SEL_EIP712]);
            const verifyTx = await ercData.connect(verifier).verifyBatch(batchId, enc);
            const verifyReceipt = await verifyTx.wait();
            const verifyEvent = verifyReceipt.events?.find(e => e.event === "BatchVerified");
            expect(verifyEvent?.args?.[2]).to.be.true; // isValid is the third argument

            // Ensure entries in the batch are now marked verified
            const entries = await ercData.getBatchData(batchId);
            expect(entries.length).to.equal(2);
            expect(entries[0].isVerified).to.be.true;
            expect(entries[1].isVerified).to.be.true;
        });

        it("Should return false if any batch entry fails, and set per-entry states", async function () {
            const dataArray = [TEST_DATA, ethers.utils.toUtf8Bytes("bad")];
            const metadataArray = [TEST_METADATA, TEST_METADATA];
            const sigGood = await signEntry(provider, ercData, TEST_DATA_TYPE, dataArray[0], metadataArray[0]);
            // Wrong signer for second entry
            const sigBad = await signEntry((await ethers.getSigners())[3], ercData, TEST_DATA_TYPE, dataArray[1], metadataArray[1]);
            const signatureArray = [ethers.utils.arrayify(sigGood), ethers.utils.arrayify(sigBad)];

            const tx = await ercData.connect(provider).storeBatch(
                TEST_DATA_TYPE,
                dataArray,
                metadataArray,
                signatureArray
            );
            const receipt = await tx.wait();
            const event = receipt.events?.find(e => e.event === "BatchProcessed");
            const batchId = event?.args?.[1].toNumber();

            const enc = defaultAbiCoder.encode(["bytes4"], [SEL_EIP712]);
            const verifyTx = await ercData.connect(verifier).verifyBatch(batchId, enc);
            const verifyReceipt = await verifyTx.wait();
            const verifyEvent = verifyReceipt.events?.find(e => e.event === "BatchVerified");
            expect(verifyEvent?.args?.[2]).to.be.false;

            const entries = await ercData.getBatchData(batchId);
            expect(entries.length).to.equal(2);
            expect(entries[0].isVerified).to.be.true;
            expect(entries[1].isVerified).to.be.false;
        });
    });

    describe("Verification", function () {
        let dataId: number;

        beforeEach(async function () {
            const signature = await signEntry(provider, ercData, TEST_DATA_TYPE, TEST_DATA, TEST_METADATA);
            const tx = await ercData.connect(provider).storeData(
                TEST_DATA_TYPE,
                TEST_DATA,
                TEST_METADATA,
                ethers.utils.arrayify(signature)
            );
            const receipt = await tx.wait();
            const event = receipt.events?.find(e => e.event === "DataStored");
            dataId = event?.args?.[0].toNumber(); // dataId is the first argument
        });

        it("Should verify data correctly", async function () {
            const enc = defaultAbiCoder.encode(["bytes4"], [SEL_EIP712]);
            const tx = await ercData.connect(verifier).verifyData(dataId, enc);
            const receipt = await tx.wait();
            const event = receipt.events?.find(e => e.event === "DataVerified");
            expect(event?.args?.[2]).to.be.true; // isValid is the third argument

            const verificationInfo = await ercData.getVerificationInfo(dataId);
            expect(verificationInfo.isValid).to.be.true;
            expect(verificationInfo.verifier).to.equal(verifier.address);
            expect(verificationInfo.verificationMethod).to.equal("EIP712_PROVIDER_SIG");
        });

        it("Should prevent unauthorized verification", async function () {
            const enc = defaultAbiCoder.encode(["bytes4"], [SEL_EIP712]);
            await expect(
                ercData.connect(user).verifyData(dataId, enc)
            ).to.be.revertedWith("ERCData: must have verifier role");
        });

        it("Should verify using hash method", async function () {
            const encHash = defaultAbiCoder.encode(["bytes4", "bytes32"], [SEL_HASH, keccak256(TEST_DATA)]);
            const tx = await ercData.connect(verifier).verifyData(dataId, encHash);
            const receipt = await tx.wait();
            const event = receipt.events?.find(e => e.event === "DataVerified");
            expect(event?.args?.[2]).to.be.true; // isValid is the third argument

            const verificationInfo = await ercData.getVerificationInfo(dataId);
            expect(verificationInfo.verificationMethod).to.equal("DATA_HASH_EQ");
        });

        it("Should fail EIP-712 verification with wrong signer", async function () {
            // Store another entry but with a signature from the wrong signer
            const badSig = await signEntry(user, ercData, TEST_DATA_TYPE, TEST_DATA, TEST_METADATA);
            const txStore = await ercData.connect(provider).storeData(
                TEST_DATA_TYPE,
                TEST_DATA,
                TEST_METADATA,
                ethers.utils.arrayify(badSig)
            );
            const receiptStore = await txStore.wait();
            const eventStore = receiptStore.events?.find(e => e.event === "DataStored");
            const badDataId = eventStore?.args?.[0].toNumber();

            const enc = defaultAbiCoder.encode(["bytes4"], [SEL_EIP712]);
            const tx = await ercData.connect(verifier).verifyData(badDataId, enc);
            const receipt = await tx.wait();
            const event = receipt.events?.find(e => e.event === "DataVerified");
            expect(event?.args?.[2]).to.be.false; // isValid should be false

            const verificationInfo = await ercData.getVerificationInfo(badDataId);
            expect(verificationInfo.isValid).to.be.false;
            const stored = await ercData.getData(badDataId);
            expect(stored.isVerified).to.be.false;
        });

        it("Should revert on unknown selector", async function () {
            const wrongEnc = defaultAbiCoder.encode(["bytes4"], ["0x00000000"]);
            await expect(
                ercData.connect(verifier).verifyData(dataId, wrongEnc)
            ).to.be.revertedWith("ERCData: invalid selector for length");
        });

        it("Should fail EIP-712 after data change with stale signature", async function () {
            const signature = await signEntry(provider, ercData, TEST_DATA_TYPE, TEST_DATA, TEST_METADATA);
            const txStore = await ercData.connect(provider).storeData(
                TEST_DATA_TYPE,
                TEST_DATA,
                TEST_METADATA,
                ethers.utils.arrayify(signature)
            );
            const rc = await txStore.wait();
            const ev = rc.events?.find(e => e.event === "DataStored");
            const id = ev?.args?.[0].toNumber();

            // Update data but keep old signature
            const newData = ethers.utils.toUtf8Bytes("different data");
            await ercData.connect(provider).updateData(id, newData, TEST_METADATA, ethers.utils.arrayify(signature));

            const enc = defaultAbiCoder.encode(["bytes4"], [SEL_EIP712]);
            const tx = await ercData.connect(verifier).verifyData(id, enc);
            const receipt = await tx.wait();
            const event = receipt.events?.find(e => e.event === "DataVerified");
            expect(event?.args?.[2]).to.be.false;
        });

        it("Should fail EIP-712 when verifyingContract differs", async function () {
            const sig = await signEntry(provider, ercData, TEST_DATA_TYPE, TEST_DATA, TEST_METADATA);

            const ERCDataFactory = await ethers.getContractFactory("ERCData");
            const ercData2 = (await ERCDataFactory.deploy()) as ERCData;
            await ercData2.deployed();
            await ercData2.grantRole(await ercData2.PROVIDER_ROLE(), provider.address);
            await ercData2.grantRole(await ercData2.VERIFIER_ROLE(), verifier.address);
            await ercData2.registerDataType(TEST_DATA_TYPE);

            const txStore = await ercData2.connect(provider).storeData(
                TEST_DATA_TYPE,
                TEST_DATA,
                TEST_METADATA,
                ethers.utils.arrayify(sig)
            );
            const rc = await txStore.wait();
            const ev = rc.events?.find(e => e.event === "DataStored");
            const otherId = ev?.args?.[0].toNumber();

            const enc = defaultAbiCoder.encode(["bytes4"], [SEL_EIP712]);
            const tx = await ercData2.connect(verifier).verifyData(otherId, enc);
            const receipt = await tx.wait();
            const event = receipt.events?.find(e => e.event === "DataVerified");
            expect(event?.args?.[2]).to.be.false;
        });

        it("Should fail hash verification on mismatch", async function () {
            const wrong = keccak256(ethers.utils.toUtf8Bytes("not the data"));
            const encHash = defaultAbiCoder.encode(["bytes4", "bytes32"], [SEL_HASH, wrong]);
            const tx = await ercData.connect(verifier).verifyData(dataId, encHash);
            const receipt = await tx.wait();
            const event = receipt.events?.find(e => e.event === "DataVerified");
            expect(event?.args?.[2]).to.be.false;
        });
    });

    describe("Snapshots", function () {
        let dataId: number;

        beforeEach(async function () {
            const signature = await signEntry(provider, ercData, TEST_DATA_TYPE, TEST_DATA, TEST_METADATA);
            const tx = await ercData.connect(provider).storeData(
                TEST_DATA_TYPE,
                TEST_DATA,
                TEST_METADATA,
                ethers.utils.arrayify(signature)
            );
            const receipt = await tx.wait();
            const event = receipt.events?.find(e => e.event === "DataStored");
            dataId = event?.args?.[0].toNumber(); // dataId is the first argument
        });

        it("Should create snapshot correctly", async function () {
            const tx = await ercData.createSnapshot("Test Snapshot", [dataId]);
            const receipt = await tx.wait();
            const event = receipt.events?.find(e => e.event === "SnapshotTaken");
            expect(event).to.not.be.undefined;

            const snapshotId = event?.args?.[0]; // snapshotId is the first argument
            expect(snapshotId).to.not.be.undefined;
            
            const snapshot = await ercData.getSnapshot(snapshotId);
            expect(snapshot.name).to.equal("Test Snapshot");
        });

        it("Should list snapshots correctly", async function () {
            await ercData.createSnapshot("Test Snapshot 1", [dataId]);
            await ercData.createSnapshot("Test Snapshot 2", [dataId]);

            const snapshots = await ercData.listSnapshots();
            expect(snapshots.length).to.equal(2);
        });
    });

    describe("Data Updates", function () {
        let dataId: number;

        beforeEach(async function () {
            const signature = await signEntry(provider, ercData, TEST_DATA_TYPE, TEST_DATA, TEST_METADATA);
            const tx = await ercData.connect(provider).storeData(
                TEST_DATA_TYPE,
                TEST_DATA,
                TEST_METADATA,
                ethers.utils.arrayify(signature)
            );
            const receipt = await tx.wait();
            const event = receipt.events?.find(e => e.event === "DataStored");
            dataId = event?.args?.[0].toNumber(); // dataId is the first argument
        });

        it("Should update data correctly", async function () {
            const newData = ethers.utils.toUtf8Bytes("updated model weights");
            const newMetadata = ethers.utils.toUtf8Bytes('{"version": "2.0"}');
            const newSignature = ethers.utils.toUtf8Bytes("new signature");

            await ercData.connect(provider).updateData(dataId, newData, newMetadata, newSignature);
            
            const updatedData = await ercData.getData(dataId);
            expect(updatedData.isVerified).to.be.false; // Verification should be reset
        });

        it("Should prevent unauthorized updates", async function () {
            const newData = ethers.utils.toUtf8Bytes("updated model weights");
            await expect(
                ercData.connect(user).updateData(dataId, newData, TEST_METADATA, ethers.utils.toUtf8Bytes("sig"))
            ).to.be.revertedWith("ERCData: not the data provider");
        });
    });
}); 
