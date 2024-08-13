// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract FixedTermFilecoinStaking is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    enum StakePeriod { THREE_MONTHS, SIX_MONTHS, TWELVE_MONTHS, EIGHTEEN_MONTHS }

    struct StakeInfo {
        uint256 amount;
        uint256 startTime;
        uint256 interestAccrued;
        StakePeriod period;
        uint256 lastUnstakeTime;
    }

    struct UnstakeRequest {
        uint256 amount;
        StakePeriod period;
        uint256 requestTime;
        bool processed;
    }

    mapping(StakePeriod => uint256) public interestRates;
    mapping(address => StakeInfo[]) public userStakes;
    mapping(address => UnstakeRequest[]) public unstakeRequests;

    uint256 public COOLING_PERIOD;

    event Staked(address indexed user, uint256 amount, uint256 timestamp, StakePeriod period);
    event Unstaked(address indexed user, uint256 amount, uint256 interest, uint256 timestamp);
    event UnstakeRequested(address indexed user, uint256 amount, uint256 requestId, uint256 timestamp, StakePeriod period);
    event InterestRateChanged(StakePeriod period, uint256 newRate, uint256 timestamp);
    event CoolingPeriodChanged(uint256 newCoolingPeriod, uint256 timestamp);

    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __Pausable_init();

        // Initialize default interest rates
        interestRates[StakePeriod.THREE_MONTHS] = 10000000000000000;  // 1%
        interestRates[StakePeriod.SIX_MONTHS] = 20000000000000000;    // 2%
        interestRates[StakePeriod.TWELVE_MONTHS] = 30000000000000000; // 3%
        interestRates[StakePeriod.EIGHTEEN_MONTHS] = 40000000000000000; // 4%
    }

    function initializeV2(uint256 _coolingPeriod) public onlyOwner {
        require(COOLING_PERIOD == 0, "Already initialized");
        COOLING_PERIOD = _coolingPeriod;
        emit CoolingPeriodChanged(COOLING_PERIOD, block.timestamp);
    }

    function setInterestRate(StakePeriod period, uint256 newRate) external onlyOwner whenNotPaused {
        interestRates[period] = newRate;
        emit InterestRateChanged(period, newRate, block.timestamp);
    }

    function setCoolingPeriod(uint256 newCoolingPeriod) external onlyOwner whenNotPaused {
        require(newCoolingPeriod >= 1 minutes, "Cooling period must be at least 1 minute");
        COOLING_PERIOD = newCoolingPeriod;
        emit CoolingPeriodChanged(newCoolingPeriod, block.timestamp);
    }

    function stake(StakePeriod period) external payable whenNotPaused nonReentrant {
        uint256 amount = msg.value;
        require(amount > 0, "Cannot stake 0");

        _updateInterestForUser(msg.sender);

        StakeInfo memory newStake = StakeInfo({
            amount: amount,
            startTime: block.timestamp,
            interestAccrued: 0,
            period: period,
            lastUnstakeTime: 0
        });

        userStakes[msg.sender].push(newStake);
        emit Staked(msg.sender, amount, block.timestamp, period);
    }

    function requestUnstake(uint256 amount, StakePeriod period, uint256 requestId) external whenNotPaused nonReentrant {
        require(amount > 0, "Cannot request unstake of 0");

        (uint256 totalStakedInPeriod, bool periodCompleted) = _getStakedAmountAndCompletionStatus(msg.sender, period);
        uint256 pendingUnstakeAmount = _getPendingUnstakeAmount(msg.sender, period);

        require(totalStakedInPeriod >= amount + pendingUnstakeAmount, "Insufficient staked amount in the specified period");
        require(periodCompleted, "Stake period not yet completed for all stakes");

        // Use the provided request ID to ensure no duplication
        require(requestId == unstakeRequests[msg.sender].length, "Invalid request ID");

        unstakeRequests[msg.sender].push(UnstakeRequest({
            amount: amount,
            period: period,
            requestTime: block.timestamp,
            processed: false
        }));

        emit UnstakeRequested(msg.sender, amount, requestId, block.timestamp, period);
    }

    function completeUnstake(uint256 requestIndex) external whenNotPaused nonReentrant {
        require(requestIndex < unstakeRequests[msg.sender].length, "Invalid request index");
        UnstakeRequest storage request = unstakeRequests[msg.sender][requestIndex];
        require(!request.processed, "Request already processed");
        require(block.timestamp >= request.requestTime + COOLING_PERIOD, "Cooling period not yet passed");

        uint256 amount = request.amount;
        StakePeriod period = request.period;
        uint256 totalPrincipal = 0;
        uint256 totalInterest = 0;
        uint256 remainingAmount = amount;

        StakeInfo[] storage stakes = userStakes[msg.sender];
        for (uint256 i = 0; i < stakes.length && remainingAmount > 0; i++) {
            StakeInfo storage stakeInfo = stakes[i];
            if (stakeInfo.period == period && stakeInfo.amount > 0) {
                uint256 accruedInterest = calculateInterest(stakeInfo);
                uint256 stakeAmount = stakeInfo.amount;
                uint256 endTime = stakeInfo.startTime + getPeriodDuration(stakeInfo.period);  // Fixed Error

                require(block.timestamp >= endTime, "Stake period not yet completed");
                require(block.timestamp >= stakeInfo.lastUnstakeTime + COOLING_PERIOD, "Cooling period not yet passed for this stake");

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

                // Update the last unstake time
                stakeInfo.lastUnstakeTime = block.timestamp;
            }
        }

        require(remainingAmount == 0, "Unable to unstake the specified amount");
        uint256 totalAmount = totalPrincipal + totalInterest;
        require(address(this).balance >= totalAmount, "Contract does not have enough balance");
        payable(msg.sender).transfer(totalAmount);

        // Mark the request as processed
        request.processed = true;

        emit Unstaked(msg.sender, totalPrincipal, totalInterest, block.timestamp);
    }

    function calculateInterest(StakeInfo memory stakeInfo) internal view returns (uint256) {
        uint256 rate = interestRates[stakeInfo.period];
        uint256 amount = stakeInfo.amount;
        uint256 timeElapsed = block.timestamp - stakeInfo.startTime;

        return (amount * rate * timeElapsed) / (365 * 24 * 60 * 60 * (10**18));
    }

    function getPeriodDuration(StakePeriod period) internal pure returns (uint256) {
        if (period == StakePeriod.THREE_MONTHS) {
            return 3 minutes;
        } else if (period == StakePeriod.SIX_MONTHS) {
            return 5 minutes;
        } else if (period == StakePeriod.TWELVE_MONTHS) {
            return 7 minutes;
        } else if (period == StakePeriod.EIGHTEEN_MONTHS) {
            return 10 minutes;
        } else {
            revert("Invalid staking period");
        }
    }

    function getTotalStaked(address user) public view returns (uint256 totalStaked) {
        totalStaked = 0;
        for (uint256 i = 0; i < userStakes[user].length; i++) {
            totalStaked += userStakes[user][i].amount;
        }
    }

    function getStakedAmountByPeriod(address user, StakePeriod period) public view returns (uint256 totalStakedWithInterest) {
        totalStakedWithInterest = 0;
        for (uint256 i = 0; i < userStakes[user].length; i++) {
            StakeInfo memory stakeInfo = userStakes[user][i];
            if (stakeInfo.period == period) {
                uint256 accruedInterest = calculateInterest(stakeInfo);
                totalStakedWithInterest += stakeInfo.amount + stakeInfo.interestAccrued + accruedInterest;
            }
        }
    }

    function _updateInterestForUser(address user) internal {
        for (uint256 i = 0; i < userStakes[user].length; i++) {
            StakeInfo storage stakeInfo = userStakes[user][i];
            uint256 accrued = calculateInterest(stakeInfo);
            stakeInfo.interestAccrued += accrued;
            stakeInfo.startTime = block.timestamp;
        }
    }

    function _getStakedAmountAndCompletionStatus(address user, StakePeriod period) internal view returns (uint256 totalStakedInPeriod, bool periodCompleted) {
        totalStakedInPeriod = 0;
        periodCompleted = false;
        for (uint256 i = 0; i < userStakes[user].length; i++) {
            StakeInfo storage stakeInfo = userStakes[user][i];
            if (stakeInfo.period == period) {
                uint256 endTime = stakeInfo.startTime + getPeriodDuration(stakeInfo.period);
                if (block.timestamp >= endTime) {
                    periodCompleted = true;
                }
                totalStakedInPeriod += stakeInfo.amount;
            }
        }
    }

    function _getPendingUnstakeAmount(address user, StakePeriod period) internal view returns (uint256 pendingUnstakeAmount) {
        pendingUnstakeAmount = 0;
        for (uint256 i = 0; i < unstakeRequests[user].length; i++) {
            UnstakeRequest storage request = unstakeRequests[user][i];
            if (request.period == period && !request.processed) {
                pendingUnstakeAmount += request.amount;
            }
        }
    }

    function getContractBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function withdraw(uint256 amount) external onlyOwner whenNotPaused nonReentrant {
        require(amount > 0, "Cannot withdraw 0");
        require(address(this).balance >= amount, "Insufficient balance in contract");

        payable(msg.sender).transfer(amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    fallback() external payable {}

    receive() external payable whenNotPaused {}
}
