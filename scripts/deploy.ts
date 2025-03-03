import { ethers, run } from "hardhat";

async function main() {
  console.log("Deploying ERCData contract...");

  // Get the contract factory
  const ERCDataFactory = await ethers.getContractFactory("ERCData");
  
  // Deploy the contract
  const ercData = await ERCDataFactory.deploy();
  
  // Wait for deployment to finish
  await ercData.deployed();
  
  console.log(`ERCData deployed to: ${ercData.address}`);
  console.log("Transaction hash:", ercData.deployTransaction.hash);
  
  // Wait for 5 confirmations for Etherscan verification
  console.log("Waiting for 5 confirmations...");
  await ercData.deployTransaction.wait(5);
  console.log("Confirmed!");
  
  // Verify the contract on Etherscan/Basescan
  console.log("Verifying contract on Etherscan/Basescan...");
  try {
    await run("verify:verify", {
      address: ercData.address,
      constructorArguments: [],
    });
    console.log("Contract verified successfully");
  } catch (error) {
    console.error("Error verifying contract:", error);
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
}); 