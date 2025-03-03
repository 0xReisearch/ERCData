import { expect } from "chai";
import { ethers } from "hardhat";
import { ERCData } from "../typechain-types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Contract } from "ethers";

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
    const TEST_SIGNATURE = ethers.utils.toUtf8Bytes("signature");
    const TEST_VERIFICATION_DATA = ethers.utils.toUtf8Bytes("verification data");

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

    describe("Data Storage", function () {
        it("Should store data correctly", async function () {
            const tx = await ercData.connect(provider).storeData(
                TEST_DATA_TYPE,
                TEST_DATA,
                TEST_METADATA,
                TEST_SIGNATURE
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
                    TEST_SIGNATURE
                )
            ).to.be.revertedWith("ERCData: must have provider role");
        });
    });

    describe("Batch Operations", function () {
        it("Should store batch data correctly", async function () {
            const dataArray = [TEST_DATA, TEST_DATA];
            const metadataArray = [TEST_METADATA, TEST_METADATA];
            const signatureArray = [TEST_SIGNATURE, TEST_SIGNATURE];

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

        it("Should verify batch correctly", async function () {
            const dataArray = [TEST_DATA, TEST_DATA];
            const metadataArray = [TEST_METADATA, TEST_METADATA];
            const signatureArray = [TEST_SIGNATURE, TEST_SIGNATURE];

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

            const verifyTx = await ercData.connect(verifier).verifyBatch(batchId, TEST_VERIFICATION_DATA);
            const verifyReceipt = await verifyTx.wait();
            const verifyEvent = verifyReceipt.events?.find(e => e.event === "BatchVerified");
            expect(verifyEvent?.args?.[2]).to.be.true; // isValid is the third argument
        });
    });

    describe("Verification", function () {
        let dataId: number;

        beforeEach(async function () {
            const tx = await ercData.connect(provider).storeData(
                TEST_DATA_TYPE,
                TEST_DATA,
                TEST_METADATA,
                TEST_SIGNATURE
            );
            const receipt = await tx.wait();
            const event = receipt.events?.find(e => e.event === "DataStored");
            dataId = event?.args?.[0].toNumber(); // dataId is the first argument
        });

        it("Should verify data correctly", async function () {
            const tx = await ercData.connect(verifier).verifyData(dataId, TEST_VERIFICATION_DATA);
            const receipt = await tx.wait();
            const event = receipt.events?.find(e => e.event === "DataVerified");
            expect(event?.args?.[2]).to.be.true; // isValid is the third argument

            const verificationInfo = await ercData.getVerificationInfo(dataId);
            expect(verificationInfo.isValid).to.be.true;
            expect(verificationInfo.verifier).to.equal(verifier.address);
        });

        it("Should prevent unauthorized verification", async function () {
            await expect(
                ercData.connect(user).verifyData(dataId, TEST_VERIFICATION_DATA)
            ).to.be.revertedWith("ERCData: must have verifier role");
        });
    });

    describe("Snapshots", function () {
        let dataId: number;

        beforeEach(async function () {
            const tx = await ercData.connect(provider).storeData(
                TEST_DATA_TYPE,
                TEST_DATA,
                TEST_METADATA,
                TEST_SIGNATURE
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
            const tx = await ercData.connect(provider).storeData(
                TEST_DATA_TYPE,
                TEST_DATA,
                TEST_METADATA,
                TEST_SIGNATURE
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
                ercData.connect(user).updateData(dataId, newData, TEST_METADATA, TEST_SIGNATURE)
            ).to.be.revertedWith("ERCData: not the data provider");
        });
    });
}); 