// scripts/deploy_initial.js
const { ethers, upgrades } = require("hardhat");

async function main() {
  const FixedTermFilecoinStaking = await ethers.getContractFactory("FixedTermFilecoinStakingP");
  console.log("Deploying FixedTermFilecoinStaking...");
  const staking = await upgrades.deployProxy(FixedTermFilecoinStaking, { 
    initializer: 'initialize',
    timeout: 600000, 
    pollingInterval: 15000 
   });
  await staking.waitForDeployment();
  console.log("FixedTermFilecoinStaking deployed to:", await staking.getAddress());
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
