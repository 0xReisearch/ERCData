import { ethers } from "hardhat";

async function main() {
  console.log("🚀 Deploying ERCData v2 with Privacy/Access Control to Base Mainnet...");
  
  const [deployer] = await ethers.getSigners();
  
  console.log("Deploying with account:", deployer.address);
  console.log("Account balance:", ethers.utils.formatEther(await deployer.getBalance()));

  // Deploy ERCData contract
  console.log("\n📄 Deploying ERCData contract...");
  const ERCData = await ethers.getContractFactory("ERCData");
  
  // Set gas parameters for Base mainnet
  const gasPrice = await deployer.provider!.getGasPrice();
  console.log("Current gas price:", ethers.utils.formatUnits(gasPrice, "gwei"), "gwei");
  
  const ercData = await ERCData.deploy({
    gasPrice: gasPrice.mul(110).div(100), // 10% higher than current
    gasLimit: 5000000 // 5M gas limit
  });

  await ercData.deployed();

  console.log("✅ ERCData deployed to:", ercData.address);
  console.log("📄 Transaction hash:", ercData.deployTransaction.hash);
  
  // Wait for some confirmations
  console.log("\n⏳ Waiting for confirmations...");
  await ercData.deployTransaction.wait(3);
  
  console.log("✅ Contract deployed successfully!");

  // Grant roles to deployer
  console.log("\n🔐 Setting up roles...");
  
  // Grant provider role to deployer
  const PROVIDER_ROLE = await ercData.PROVIDER_ROLE();
  await ercData.grantRole(PROVIDER_ROLE, deployer.address);
  console.log("✅ Granted PROVIDER_ROLE to deployer");
  
  // Grant verifier role to deployer
  const VERIFIER_ROLE = await ercData.VERIFIER_ROLE();
  await ercData.grantRole(VERIFIER_ROLE, deployer.address);
  console.log("✅ Granted VERIFIER_ROLE to deployer");
  
  console.log("\n📋 Deployment Summary:");
  console.log("=====================");
  console.log("Contract Address:", ercData.address);
  console.log("Network: Base Mainnet");
  console.log("Chain ID: 8453");
  console.log("Deployer:", deployer.address);
  console.log("Transaction Hash:", ercData.deployTransaction.hash);
  console.log("Gas Used:", ercData.deployTransaction.gasLimit?.toString());
  
  return ercData.address;
}

main()
  .then((address) => {
    console.log(`\n🎉 Contract deployed at: ${address}`);
    process.exit(0);
  })
  .catch((error) => {
    console.error("\n❌ Deployment failed:", error);
    process.exit(1);
  });