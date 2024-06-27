let expect;

before(async () => {
    const chai = await import('chai');
    expect = chai.expect;
});

const { ethers, upgrades } = require("hardhat");

describe("FilecoinStakingContract", function () {
    let stakingContract;
    let owner, addr1, addr2;

    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();
        const FilecoinStakingContract = await ethers.getContractFactory("FilecoinStakingContract");
        stakingContract = await upgrades.deployProxy(FilecoinStakingContract, [], { initializer: 'initialize' });
        await stakingContract.deployed(); // Ensure this is awaited correctly
    });

    it("Should initialize with correct owner", async function () {
        expect(await stakingContract.owner()).to.equal(owner.address);
    });

    it("Should allow staking", async function () {
        await stakingContract.connect(addr1).stake({ value: ethers.utils.parseEther("1") });
        const stakes = await stakingContract.getTotalFilecoins(addr1.address);
        expect(stakes).to.equal(ethers.utils.parseEther("1"));
    });

    it("Should calculate interest correctly", async function () {
        await stakingContract.connect(addr1).stake({ value: ethers.utils.parseEther("1") });
        
        // Fast forward time by 1 year
        await ethers.provider.send("evm_increaseTime", [365 * 24 * 60 * 60]);
        await ethers.provider.send("evm_mine");

        const stakesBefore = await stakingContract.getTotalFilecoins(addr1.address);

        // Change the interest rate and stake again
        await stakingContract.setInterestRate(ethers.utils.parseEther("0.1"));
        await stakingContract.connect(addr1).stake({ value: ethers.utils.parseEther("1") });

        const stakesAfter = await stakingContract.getTotalFilecoins(addr1.address);
        expect(stakesAfter).to.be.gt(stakesBefore);
    });

    it("Should allow unstaking", async function () {
        await stakingContract.connect(addr1).stake({ value: ethers.utils.parseEther("3") });
        await stakingContract.connect(addr1).unstake(ethers.utils.parseEther("1"));

        const stakes = await stakingContract.getTotalFilecoins(addr1.address);
        expect(stakes).to.equal(ethers.utils.parseEther("2"));
    });

    it("Should not allow unstaking more than staked", async function () {
        await stakingContract.connect(addr1).stake({ value: ethers.utils.parseEther("1") });
        await expect(stakingContract.connect(addr1).unstake(ethers.utils.parseEther("2")))
            .to.be.revertedWith("Insufficient staked amount");
    });

    it("Should allow owner to withdraw funds", async function () {
        await stakingContract.connect(addr1).stake({ value: ethers.utils.parseEther("1") });
        
        const initialOwnerBalance = await ethers.provider.getBalance(owner.address);
        await stakingContract.connect(owner).withdraw(ethers.utils.parseEther("0.5"));
        const finalOwnerBalance = await ethers.provider.getBalance(owner.address);

        expect(finalOwnerBalance).to.be.gt(initialOwnerBalance);
    });

    it("Should not allow non-owner to withdraw funds", async function () {
        await stakingContract.connect(addr1).stake({ value: ethers.utils.parseEther("1") });
        await expect(stakingContract.connect(addr1).withdraw(ethers.utils.parseEther("0.5")))
            .to.be.revertedWith("Ownable: caller is not the owner");
    });
});
