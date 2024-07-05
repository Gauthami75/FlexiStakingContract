// scripts/upgrade.js
const { ethers, upgrades } = require("hardhat");

async function main() {
  const stakingAddress = '0xe7f781361F881A9f610Bf4E42BD61f3de3Ef5A4a'; // Replace with your existing contract address

  const FixedTermFilecoinStakingV2 = await ethers.getContractFactory("FixedTermFilecoinStakingV2");
  console.log("Upgrading FixedTermFilecoinStaking...");
 await upgrades.upgradeProxy(stakingAddress, FixedTermFilecoinStakingV2,{
    timeout: 1200000, // 20 minutes
        pollingInterval: 15000 // 15 seconds
 });
  console.log("FixedTermFilecoinStaking version 2 deployed");
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
