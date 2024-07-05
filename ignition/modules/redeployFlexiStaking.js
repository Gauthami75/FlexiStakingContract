//This script is to depoly the later versions of the flieStaking.sol
const { ethers, upgrades } = require("hardhat");

async function main() {
    const proxyAddress = "0x1777c208402869B69a25fb1CBe3EEFB74735Fd25"; // Your proxy address will be the address of the first deploed contract

    console.log("Upgrading FilecoinStakingContract...");
    const FilecoinStakingContractV2 = await ethers.getContractFactory("FilecoinStakingContractV2");
    await upgrades.upgradeProxy(proxyAddress, FilecoinStakingContractV2, {
        timeout: 1200000, // 20 minutes
        pollingInterval: 15000 // 15 seconds
    });

    console.log("FilecoinStakingContract upgraded to V2");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
