const { ethers, upgrades } = require("hardhat");

async function main() {
    const proxyAddress = "0x75BaC884d1a4577716C050E8765cBC2B8295c0B6"; // Your proxy address

    console.log("Upgrading FlexiStakingContract to V3...");

    // Get the contract factory for the new version
    const FlexiStakingContractV3 = await ethers.getContractFactory("FilecoinStakingContractV3");

    try {
        // Set gasPrice using a much higher value to ensure replacement of the pending transaction
        const gasPrice = ethers.parseUnits('187', 'gwei'); // Increase to 170 gwei or more

        await upgrades.upgradeProxy(proxyAddress, FlexiStakingContractV3, {
            timeout: 1800000, // 30 minutes
            pollingInterval: 15000, // 15 seconds
            gasLimit: 10000000, // Adjust based on network conditions
            gasPrice: gasPrice // Set a significantly higher gas price
        });

        console.log("FlexiStakingContract upgraded to V3");

        // // Initialize the V2 and V3 specific functions (if not already initialized)
        // const newCoolingPeriod = 21 * 24 * 60 * 60; // 21 days in seconds
        // await stakingContract.initializeV2(newCoolingPeriod, { gasLimit: 850000, gasPrice: gasPrice });

        // console.log("FlexiStakingContractV2 initialized");

        // // Initialize the V3 specific functions (Pausable, etc.)
        // console.log("Calling the initialize function for V3...");
        // await stakingContract.initialize({ gasLimit: 850000, gasPrice: gasPrice });

        console.log("FlexiStakingContractV3 updated");
    } catch (error) {
        console.error("Upgrade failed:", error);
    }
}

main().catch((error) => {
    console.error("Script failed:", error);
    process.exitCode = 1;
});
