// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract FilecoinStakingContractV3 is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    struct InterestRateChange {
        uint256 rate;
        uint256 startTime;
    }

    struct StakeInfo {
        uint256 amount;
        uint256 startTime;
        uint256 interestAccrued;
    }

    struct UnstakeRequest {
        uint256 amount;
        uint256 requestTime;
        bool processed;
    }

    InterestRateChange[] public interestRateHistory;
    mapping(address => StakeInfo[]) public userStakes;
    mapping(address => UnstakeRequest[]) public unstakeRequests;

    uint256 public COOLING_PERIOD ;

    event Staked(address indexed user, uint256 amount, uint256 timestamp);
    event Unstaked(address indexed user, uint256 amount, uint256 interest, uint256 timestamp);
    event UnstakeRequested(address indexed user, uint256 amount, uint256 requestId, uint256 timestamp);
    event CoolingPeriodChanged(uint256 newCoolingPeriod, uint256 timestamp);

    function initialize() external initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __Pausable_init();
        interestRateHistory.push(InterestRateChange({
            rate: 50000000000000000, // initial interest rate
            startTime: block.timestamp
        }));
    }

     function initializeV2(uint256 _coolingPeriod) public onlyOwner {
        require(COOLING_PERIOD == 0, "Already initialized");
        COOLING_PERIOD = _coolingPeriod;
        emit CoolingPeriodChanged(COOLING_PERIOD, block.timestamp);
    }

    function setInterestRate(uint256 newRate) external onlyOwner whenNotPaused {
        interestRateHistory.push(InterestRateChange({
            rate: newRate,
            startTime: block.timestamp
        }));
    }

    function setCoolingPeriod(uint256 newCoolingPeriod) external onlyOwner whenNotPaused{
       require(newCoolingPeriod >= 1 minutes, "Cooling period must be at least 1 minute");
       COOLING_PERIOD = newCoolingPeriod;
     }

    function stake() external payable whenNotPaused nonReentrant {
        uint256 amount = msg.value;
        require(amount > 0, "Cannot stake 0");

        updateInterestForUser(msg.sender);

        StakeInfo memory newStake = StakeInfo({
            amount: amount,
            startTime: block.timestamp,
            interestAccrued: 0
        });

        userStakes[msg.sender].push(newStake);
        emit Staked(msg.sender, amount, block.timestamp);
    }

    function requestUnstake(uint256 amount, uint256 requestId) external whenNotPaused nonReentrant {
    require(amount > 0, "Cannot request unstake of 0");
    require(getAvailableToUnstake(msg.sender) >= amount, "Insufficient available staked amount");
    
    require(requestId == unstakeRequests[msg.sender].length, "Invalid request ID");

    unstakeRequests[msg.sender].push(UnstakeRequest({
        amount: amount,
        requestTime: block.timestamp,
        processed: false
    }));

    emit UnstakeRequested(msg.sender, amount, requestId, block.timestamp);
   }


    function completeUnstake(uint256 requestIndex) external whenNotPaused nonReentrant {
        require(requestIndex < unstakeRequests[msg.sender].length, "Invalid request index");
        UnstakeRequest storage request = unstakeRequests[msg.sender][requestIndex];
        require(!request.processed, "Request already processed");
        require(block.timestamp >= request.requestTime + COOLING_PERIOD, "Cooling period not yet passed");

        uint256 amount = request.amount;
        uint256 totalStaked = getTotalStaked(msg.sender);
        require(totalStaked >= amount, "Insufficient staked amount");

        (uint256 totalPrincipal, uint256 totalInterest) = processUnstake(msg.sender, amount);

        uint256 totalAmount = totalPrincipal + totalInterest;
        require(address(this).balance >= totalAmount, "Contract does not have enough balance");
        
        emit Unstaked(msg.sender, totalPrincipal, totalInterest, block.timestamp);
        payable(msg.sender).transfer(totalAmount);

        request.processed = true;
    }

    function processUnstake(address user, uint256 amount) internal returns (uint256 totalPrincipal, uint256 totalInterest) {
        uint256 remainingAmount = amount;
        totalInterest = 0;
        totalPrincipal = 0;
        StakeInfo[] storage stakes = userStakes[user];

        for (uint256 i = 0; i < stakes.length && remainingAmount > 0; i++) {
            StakeInfo storage stakeInfo = stakes[i];
            uint256 stakeAmount = stakeInfo.amount;

            if (stakeAmount > 0) {
                uint256 accruedInterest = calculateInterest(stakeInfo);

                if (stakeAmount >= remainingAmount) {
                    uint256 interestForUnstaked = accruedInterest * remainingAmount / stakeAmount;
                    totalInterest += interestForUnstaked;
                    totalPrincipal += remainingAmount;
                    stakeInfo.amount -= remainingAmount;

                    if (stakeInfo.amount == 0) {
                        stakeInfo.interestAccrued = 0;
                    } else {
                        stakeInfo.interestAccrued += accruedInterest - interestForUnstaked;
                        stakeInfo.startTime = block.timestamp;
                    }

                    remainingAmount = 0;
                } else {
                    totalInterest += accruedInterest;
                    totalPrincipal += stakeAmount;
                    remainingAmount -= stakeAmount;

                    stakeInfo.amount = 0;
                    stakeInfo.interestAccrued = 0;
                }
            }
        }

        return (totalPrincipal, totalInterest);
    }

    function calculateInterest(StakeInfo memory stakeInfo) internal view returns (uint256) {
        uint256 totalInterest = 0;
        uint256 lastTime = stakeInfo.startTime;
        uint256 amount = stakeInfo.amount;
        uint256 historyLength = interestRateHistory.length;

        for (uint256 i = 1; i < historyLength; i++) {
            InterestRateChange memory rateChange = interestRateHistory[i];
            if (rateChange.startTime > lastTime) {
                uint256 timePeriod = rateChange.startTime - lastTime;
                totalInterest += (amount * interestRateHistory[i - 1].rate * timePeriod) / (365 * 24 * 60 * 60 * (10**18));
                lastTime = rateChange.startTime;
            }
        }

        if (lastTime < block.timestamp) {
            uint256 timePeriod = block.timestamp - lastTime;
            totalInterest += (amount * interestRateHistory[historyLength - 1].rate * timePeriod) / (365 * 24 * 60 * 60 * (10**18));
        }

        return totalInterest;
    }

    function updateInterestForUser(address user) internal {
        uint256 stakeLength = userStakes[user].length;
        for (uint256 i = 0; i < stakeLength; i++) {
            StakeInfo storage stakeInfo = userStakes[user][i];
            uint256 accrued = calculateInterest(stakeInfo);
            stakeInfo.interestAccrued += accrued;
            stakeInfo.startTime = block.timestamp;
        }
    }

    function getTotalStaked(address user) public view returns (uint256 totalStaked) {
        totalStaked = 0;
        uint256 stakeLength = userStakes[user].length;
        for (uint256 i = 0; i < stakeLength; i++) {
            totalStaked += userStakes[user][i].amount;
        }
    }

    function getTotalRequestedUnstake(address user) public view returns (uint256 totalRequested) {
        totalRequested = 0;
        uint256 requestLength = unstakeRequests[user].length;
        for (uint256 i = 0; i < requestLength; i++) {
            if (!unstakeRequests[user][i].processed) {
                totalRequested += unstakeRequests[user][i].amount;
            }
        }
    }

    function getAvailableToUnstake(address user) public view returns (uint256 availableToUnstake) {
        uint256 totalStaked = getTotalStaked(user);
        uint256 totalRequested = getTotalRequestedUnstake(user);
        availableToUnstake = totalStaked - totalRequested;
    }

    function getTotalFilecoins(address user) external view returns (uint256 totalAmount) {
        totalAmount = 0;
        uint256 stakeLength = userStakes[user].length;
        for (uint256 i = 0; i < stakeLength; i++) {
            StakeInfo memory stakeInfo = userStakes[user][i];
            uint256 accruedInterest = calculateInterest(stakeInfo);
            totalAmount += stakeInfo.amount + stakeInfo.interestAccrued + accruedInterest;
        }
    }

    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getCurrentRate() external view returns (uint256) {
        require(interestRateHistory.length > 0, "No interest rate set");
        return interestRateHistory[interestRateHistory.length - 1].rate;
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

    fallback() external payable {
        require(msg.data.length == 0, "Invalid fallback call");
    }

    receive() external payable whenNotPaused {}
}
