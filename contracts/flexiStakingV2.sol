// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract FilecoinStakingContractV2 is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    struct InterestRateChange {
        uint256 rate;
        uint256 startTime;
    }

    struct StakeInfo {
        uint256 amount;
        uint256 startTime;
        uint256 interestAccrued;
    }

    InterestRateChange[] public interestRateHistory;
    mapping(address => StakeInfo[]) public userStakes;

    event Staked(address indexed user, uint256 amount, uint256 timestamp);
    event Unstaked(address indexed user, uint256 amount, uint256 interest, uint256 timestamp);
    event Debug(string message, uint256 value);
    event DebugString(string message);

    function initialize() external initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        interestRateHistory.push(InterestRateChange({
            rate: 50000000000000000, // initial interest rate
            startTime: block.timestamp
        }));
    }

    function setInterestRate(uint256 newRate) external onlyOwner nonReentrant{
        interestRateHistory.push(InterestRateChange({
            rate: newRate,
            startTime: block.timestamp
        }));
    }

    function stake() external payable {
        uint256 amount = msg.value;
        require(amount > 0, "Cannot stake 0");
        emit Debug("Before Stake ContractBalance", address(this).balance);
        emit Debug("After Stake ContractBalance", address(this).balance);
        for (uint256 i = 0; i < userStakes[msg.sender].length; i++) {
            StakeInfo storage stakeInfo = userStakes[msg.sender][i];
            uint256 accrued = calculateInterest(stakeInfo);
            stakeInfo.interestAccrued += accrued;
            stakeInfo.startTime = block.timestamp; // Reset the start time for updated interest calculation
        }

        StakeInfo memory newStake = StakeInfo({
            amount: amount,
            startTime: block.timestamp,
            interestAccrued: 0
        });

        userStakes[msg.sender].push(newStake);
        emit Staked(msg.sender, amount, block.timestamp);
    }

    function unstake(uint256 amount) external nonReentrant {
    require(amount > 0, "Cannot unstake 0");
    require(address(this).balance >= amount, "Insufficient fund");

    uint256 totalStaked = 0;
    for (uint256 i = 0; i < userStakes[msg.sender].length; i++) {
        totalStaked += userStakes[msg.sender][i].amount;
    }
    emit Debug("Total Staked", totalStaked);

    require(totalStaked >= amount, "Insufficient staked amount");

    uint256 remainingAmount = amount;
    uint256 totalInterest = 0;
    uint256 totalPrincipal = 0;

    for (uint256 i = 0; i < userStakes[msg.sender].length && remainingAmount > 0; i++) {
        StakeInfo storage stakeInfo = userStakes[msg.sender][i];
        uint256 stakeAmount = stakeInfo.amount;

        emit Debug("Processing Stake Index", i);
        emit Debug("Current Stake Amount", stakeAmount);
        emit Debug("Remaining Amount", remainingAmount);

        if (stakeAmount > 0) {
            uint256 accruedInterest = calculateInterest(stakeInfo);
            emit Debug("Accrued Interest", accruedInterest);

            if (stakeAmount >= remainingAmount) {
                uint256 interestForUnstaked = accruedInterest * remainingAmount / stakeAmount;
                emit Debug("Accrued Interest for Partial/Full Unstake", interestForUnstaked);

                totalInterest += interestForUnstaked;
                totalPrincipal += remainingAmount;
                stakeInfo.amount -= remainingAmount;

                if (stakeInfo.amount == 0) {
                    // Fully unstaked
                    stakeInfo.interestAccrued = 0;
                } else {
                    // Partially unstaked
                    stakeInfo.interestAccrued += accruedInterest - interestForUnstaked;
                    stakeInfo.startTime = block.timestamp;
                }

                remainingAmount = 0;
            } else {
                totalInterest += accruedInterest;
                totalPrincipal += stakeAmount;
                remainingAmount -= stakeAmount;

                // Fully unstaked
                stakeInfo.amount = 0;
                stakeInfo.interestAccrued = 0;
            }

            emit Debug("Total Interest After Processing", totalInterest);
            emit Debug("Total Principal After Processing", totalPrincipal);
        }
    }

    uint256 totalAmount = totalPrincipal + totalInterest;
    emit Debug("Total Amount to Transfer", totalAmount);
    emit Debug("Remaining Amount", remainingAmount);

    uint256 contractBalance = address(this).balance;
    emit Debug("Token Balance in Contract", contractBalance);

    require(contractBalance >= totalAmount, "Contract does not have enough balance");
    emit Unstaked(msg.sender, totalPrincipal, totalInterest, block.timestamp);
    payable(msg.sender).transfer(totalAmount);
    
}

    function calculateInterest(StakeInfo memory stakeInfo) internal view returns (uint256) {
    uint256 totalInterest = 0;
    uint256 lastTime = stakeInfo.startTime;
    uint256 amount = stakeInfo.amount;

    for (uint256 i = 0; i < interestRateHistory.length; i++) {
        InterestRateChange memory rateChange = interestRateHistory[i];
        if (rateChange.startTime > lastTime) {
            uint256 timePeriod = rateChange.startTime - lastTime;
            totalInterest += (amount * interestRateHistory[i - 1].rate * timePeriod) / (365 * 24 * 60 * 60 * (10**18));
            lastTime = rateChange.startTime;
        }
    }

    if (lastTime < block.timestamp) {
        uint256 timePeriod = block.timestamp - lastTime;
        totalInterest += (amount * interestRateHistory[interestRateHistory.length - 1].rate * timePeriod) / (365 * 24 * 60 * 60 * (10**18));
    }

    return totalInterest;
}
    function getTotalFilecoins(address user) external view returns (uint256 totalAmount) {
        totalAmount = 0;

        for (uint256 i = 0; i < userStakes[user].length; i++) {
            StakeInfo memory stakeInfo = userStakes[user][i];
            uint256 accruedInterest = calculateInterest(stakeInfo);
            totalAmount += stakeInfo.amount + stakeInfo.interestAccrued + accruedInterest;
        }
    }

    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getCurrentRate() external view returns (uint256){
        require(interestRateHistory.length > 0, "No interest rate set");
        return interestRateHistory[interestRateHistory.length - 1].rate;
    }

    function withdraw(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "Cannot withdraw 0");
        require(address(this).balance >= amount, "Insufficient balance in contract");

        payable(msg.sender).transfer(amount);
    }

    fallback() external payable {}

    receive() external payable {}
}
