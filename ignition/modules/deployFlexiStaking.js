const { ethers, upgrades } = require("hardhat");

async function main() {
    const FilecoinStakingContract = await ethers.getContractFactory("FilecoinStakingContract");
    console.log("Deploying FilecoinStakingContract...");

    const stakingContract = await upgrades.deployProxy(FilecoinStakingContract, [], {
        initializer: 'initialize',
        timeout: 600000, 
        pollingInterval: 15000 
      });
    await stakingContract.waitForDeployment();

    console.log("FilecoinStakingContract deployed to:", await stakingContract.getAddress());
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
