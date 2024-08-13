// scripts/upgrade.js
const { ethers, upgrades } = require("hardhat");

async function main() {
  const stakingAddress = '0xC2ceA601D004a9a1f93F4aa0f584849D86d29CfF'; // Replace with your existing contract address

  const FixedTermFilecoinStakingV2 = await ethers.getContractFactory("FixedTermFilecoinStakingP");
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
