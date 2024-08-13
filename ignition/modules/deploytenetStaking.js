const { ethers, upgrades } = require("hardhat");

async function main() {
    const StakingContract  = await ethers.getContractFactory("StakingContract");
    console.log("Deploying FilecoinStakingContract...");

    const stakingContract = await upgrades.deployProxy(StakingContract , [], {
        initializer: 'initialize',
        timeout: 600000, 
        pollingInterval: 15000 
      });
    await stakingContract.waitForDeployment();

    console.log("Staking contract deployed to:", await stakingContract.getAddress());
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
