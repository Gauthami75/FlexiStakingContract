// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract FixedTermFilecoinStakingP is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    enum StakePeriod { ONE_DAYS, TWO_DAYS, THREE_DAYS, FOUR_DAYS }

    struct StakeInfo {
        uint256 amount;
        uint256 startTime;
        uint256 interestAccrued;
        StakePeriod period;
    }

    mapping(StakePeriod => uint256) public interestRates;
    mapping(address => StakeInfo[]) public userStakes;

    event Staked(address indexed user, uint256 amount, uint256 timestamp, StakePeriod period);
    event Unstaked(address indexed user, uint256 amount, uint256 interest, uint256 timestamp);
    event InterestRateChanged(StakePeriod period, uint256 newRate, uint256 timestamp);

    function initialize() external initializer nonReentrant{
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();

        // Initialize default plans with default interest rates
        interestRates[StakePeriod.ONE_DAYS] = 10000000000000000; // 1%
        interestRates[StakePeriod.TWO_DAYS] = 20000000000000000;   // 2%
        interestRates[StakePeriod.THREE_DAYS] = 30000000000000000; // 3%
        interestRates[StakePeriod.FOUR_DAYS] = 40000000000000000; // 4%
    }

    function setInterestRate(StakePeriod period, uint256 newRate) external onlyOwner {
        interestRates[period] = newRate;
        emit InterestRateChanged(period, newRate, block.timestamp);
    }

    function stake(StakePeriod period) external payable {
        uint256 amount = msg.value;
        require(amount > 0, "Cannot stake 0");
        require ((msg.sender).balance >= msg.value,"staker doesn't have enough coins");
        // Calculate accrued interest for existing stakes
        for (uint256 i = 0; i < userStakes[msg.sender].length; i++) {
            StakeInfo storage stakeInfo = userStakes[msg.sender][i];
            uint256 accrued = calculateInterest(stakeInfo);
            stakeInfo.interestAccrued += accrued;
            stakeInfo.startTime = block.timestamp;
        }

        StakeInfo memory newStake = StakeInfo({
            amount: amount,
            startTime: block.timestamp,
            interestAccrued: 0,
            period: period
        });

        userStakes[msg.sender].push(newStake);
        emit Staked(msg.sender, amount, block.timestamp, period);
    }

    function unstake(StakePeriod period, uint256 amount) external nonReentrant {
    require(amount > 0, "Cannot unstake 0");
    uint256 totalPrincipal = 0;
    uint256 totalInterest = 0;
    uint256 remainingAmount = amount;

    // Calculate the total amount staked in the specified period
    uint256 totalStakedInPeriod = 0;
    for (uint256 i = 0; i < userStakes[msg.sender].length; i++) {
        StakeInfo storage stakeInfo = userStakes[msg.sender][i];
        if (stakeInfo.period == period && stakeInfo.amount > 0) {
            totalStakedInPeriod += stakeInfo.amount;
        }
    }

    // Check if the user has enough staked amount in the specified period
    require(totalStakedInPeriod >= amount, "Insufficient staked amount in the specified period");

    for (uint256 i = 0; i < userStakes[msg.sender].length && remainingAmount > 0; i++) {
        StakeInfo storage stakeInfo = userStakes[msg.sender][i];
        if (stakeInfo.period == period && stakeInfo.amount > 0) {
            uint256 endTime = stakeInfo.startTime + getPeriodDuration(stakeInfo.period);
            require(block.timestamp >= endTime, "Stake period not yet completed");

            uint256 accruedInterest = calculateInterest(stakeInfo);
            uint256 stakeAmount = stakeInfo.amount;

            if (stakeAmount <= remainingAmount) {
                totalPrincipal += stakeAmount;
                totalInterest += accruedInterest + stakeInfo.interestAccrued;
                remainingAmount -= stakeAmount;

                // Mark stake as withdrawn
                stakeInfo.amount = 0;
                stakeInfo.interestAccrued = 0;
            } else {
                totalPrincipal += remainingAmount;
                totalInterest += (accruedInterest + stakeInfo.interestAccrued) * remainingAmount / stakeAmount;

                stakeInfo.amount -= remainingAmount;
                stakeInfo.interestAccrued = (accruedInterest + stakeInfo.interestAccrued) * (stakeAmount - remainingAmount) / stakeAmount;

                remainingAmount = 0;
            }
        }
    }
    require(remainingAmount == 0, "Unable to unstake the specified amount");
    uint256 totalAmount = totalPrincipal + totalInterest;
    require(address(this).balance >= totalAmount, "Contract does not have enough balance");
    emit Unstaked(msg.sender, totalPrincipal, totalInterest, block.timestamp);
    payable(msg.sender).transfer(totalAmount);
    
}

    function calculateInterest(StakeInfo memory stakeInfo) internal view returns (uint256) {
        uint256 rate = interestRates[stakeInfo.period];
        uint256 amount = stakeInfo.amount;
        uint256 timeElapsed = block.timestamp - stakeInfo.startTime;

        return (amount * rate * timeElapsed) / (365 * 24 * 60 * 60 * (10**18));
    }

    function getPeriodDuration(StakePeriod period) internal pure returns (uint256) {
        if (period == StakePeriod.ONE_DAYS) {
            return 1 *24 * 60 * 60;
        } else if (period == StakePeriod.TWO_DAYS) {
            return 2 *24 * 60 * 60;
        } else if (period == StakePeriod.THREE_DAYS) {
            return 3 *24 * 60 * 60;
        } else if (period == StakePeriod.FOUR_DAYS) {
            return 4 *24 * 60 * 60;
        } else {
            revert("Invalid staking period");
        }
    }

    function getTotalFilecoins(address user) external view returns (uint256 totalAmount) {
        totalAmount = 0;

        for (uint256 i = 0; i < userStakes[user].length; i++) {
            StakeInfo memory stakeInfo = userStakes[user][i];
            uint256 accruedInterest = calculateInterest(stakeInfo);
            totalAmount += stakeInfo.amount + stakeInfo.interestAccrued + accruedInterest;
        }
    }

    function getStakedAmountByPeriod(address user, StakePeriod period) external view returns (uint256 totalStakedWithInterest) {
    totalStakedWithInterest = 0;

    for (uint256 i = 0; i < userStakes[user].length; i++) {
        StakeInfo memory stakeInfo = userStakes[user][i];
        if (stakeInfo.period == period) {
            uint256 accruedInterest = calculateInterest(stakeInfo);
            totalStakedWithInterest += stakeInfo.amount + stakeInfo.interestAccrued + accruedInterest;
        }
    }
}

    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getCurrentRate(StakePeriod period) external view returns (uint256) {
        return interestRates[period];
    }

    function withdraw(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "Cannot withdraw 0");
        require(address(this).balance >= amount, "Insufficient balance in contract");

        payable(msg.sender).transfer(amount);
    }

    fallback() external payable {}

    receive() external payable {}
}
