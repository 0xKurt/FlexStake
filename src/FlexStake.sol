// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// New interface for hooks
interface IStakingHooks {
    function beforeStake(
        address user,
        uint256 optionId,
        uint256 amount,
        uint256 lockDuration,
        bytes calldata data
    ) external;

    function afterStake(
        address user,
        uint256 optionId,
        uint256 amount,
        uint256 lockDuration,
        bytes calldata data
    ) external;

    function beforeWithdraw(
        address user,
        uint256 optionId,
        uint256 amount,
        bytes calldata data
    ) external;

    function afterWithdraw(
        address user,
        uint256 optionId,
        uint256 amount,
        bool penaltyApplied,
        bytes calldata data
    ) external;

    function beforeExtend(
        address user,
        uint256 optionId,
        uint256 newDuration,
        bytes calldata data
    ) external;

    function afterExtend(
        address user,
        uint256 optionId,
        uint256 newDuration,
        bytes calldata data
    ) external;
}

contract StakingContract is Ownable {
    using SafeERC20 for IERC20;

    struct Option {
        uint256 id;
        bool isLocked;
        uint256 minLockDuration;
        uint256 maxLockDuration;
        bool hasEarlyExitPenalty;
        uint256 penaltyPercentage;
        address penaltyRecipient;
        uint256 minStakeAmount;
        uint256 maxStakeAmount;
        bool hasLinearVesting;
        uint256 vestingStart;
        uint256 vestingCliff;
        uint256 vestingDuration;
        uint256 baseMultiplier;
        bool hasTimeBasedMultiplier;
        uint256 multiplierIncreaseRate;
        bool allowReallocation;
        address token;
        bool paused;
        bool requiresData;
        address hookContract;
    }

    struct OptionParams {
        bool isLocked;
        uint256 minLockDuration;
        uint256 maxLockDuration;
        bool hasEarlyExitPenalty;
        uint256 penaltyPercentage;
        address penaltyRecipient;
        uint256 minStakeAmount;
        uint256 maxStakeAmount;
        bool hasLinearVesting;
        uint256 vestingStart;
        uint256 vestingCliff;
        uint256 vestingDuration;
        uint256 baseMultiplier;
        bool hasTimeBasedMultiplier;
        uint256 multiplierIncreaseRate;
        bool allowReallocation;
        address token;
        bool requiresData;
        address hookContract;
    }

    struct Stake {
        uint256 amount;
        uint256 lockDuration;
        uint256 creationTime;
        uint256 lastExtensionTime;
        bytes data;
    }

    mapping(uint256 => Option) public options;
    mapping(uint256 => mapping(address => Stake)) public stakes;
    uint256 public nextOptionId;

    // Events
    event OptionCreated(uint256 indexed id, Option option);
    event StakeCreated(
        uint256 indexed optionId,
        address indexed staker,
        uint256 amount,
        uint256 lockDuration,
        uint256 stakeId
    );
    event StakeExtended(
        uint256 indexed optionId,
        address indexed staker,
        uint256 newLockDuration
    );
    event Withdraw(
        uint256 indexed optionId,
        address indexed staker,
        uint256 amount,
        bool penaltyApplied
    );
    event OptionPaused(uint256 indexed optionId);
    event OptionUnpaused(uint256 indexed optionId);

    // Custom Errors
    error MinimumStakeGreaterThanZero();
    error MaxStakeGreaterThanMinStake();
    error LockedStakingMustHaveMinDuration();
    error MaxDurationGreaterThanMinDuration();
    error InvalidPenaltyPercentage();
    error PenaltyRecipientRequired();
    error FlexibleStakingCannotHaveLockPeriods();
    error FlexibleStakingCannotHavePenalty();
    error NoPenaltiesAllowedForFlexibleStaking();
    error NoPenaltyRecipientForFlexibleStaking();
    error VestingMustHaveDuration();
    error VestingMustHaveStartTime();
    error CliffMustBeLessThanOrEqualToVestingDuration();
    error NoVestingSettingsAllowed();
    error MultiplierRateMustBeGreaterThanZero();
    error NoMultiplierIncreaseRateIfDisabled();
    error InvalidStakeAmount();
    error StakeNotFound();
    error WithdrawBeforeLockPeriod();
    error InsufficientBalanceForPenalty();
    error NoPenaltiesForFlexibleStaking();
    error StakingPaused();
    error DataRequired();
    error NoDataAllowed();

    constructor(address _owner) Ownable(_owner) {}

    // Option Management Functions
    function createOption(
        OptionParams calldata params
    ) external onlyOwner returns (uint256) {
        _validateBasicParams(params);
        _validateLockingParams(params);
        _validateVestingParams(params);
        _validateMultiplierParams(params);

        uint256 optionId = nextOptionId++;
        _createOptionStorage(optionId, params);

        emit OptionCreated(optionId, options[optionId]);
        return optionId;
    }

    function pauseStaking(uint256 optionId) external onlyOwner {
        Option storage option = options[optionId];
        require(!option.paused, "Staking is already paused");
        option.paused = true;
        emit OptionPaused(optionId);
    }

    function unpauseStaking(uint256 optionId) external onlyOwner {
        Option storage option = options[optionId];
        require(option.paused, "Staking is not paused");
        option.paused = false;
        emit OptionUnpaused(optionId);
    }

    // Staking Functions
    function stake(
        uint256 optionId,
        uint256 amount,
        uint256 lockDuration,
        bytes calldata data
    ) external {
        Option storage option = options[optionId];

        if (option.requiresData && data.length == 0) revert DataRequired();
        if (!option.requiresData && data.length > 0) revert NoDataAllowed();

        if (option.hookContract != address(0)) {
            IStakingHooks(option.hookContract).beforeStake(
                msg.sender,
                optionId,
                amount,
                lockDuration,
                data
            );
        }

        if (option.paused) revert StakingPaused();
        if (
            amount < option.minStakeAmount ||
            (option.maxStakeAmount > 0 && amount > option.maxStakeAmount)
        ) revert InvalidStakeAmount();

        if (option.isLocked) {
            if (
                lockDuration < option.minLockDuration ||
                lockDuration > option.maxLockDuration
            ) revert InvalidStakeAmount();
        } else {
            if (lockDuration != 0)
                revert FlexibleStakingCannotHaveLockPeriods();
        }

        IERC20 token = IERC20(option.token);
        token.safeTransferFrom(msg.sender, address(this), amount);

        stakes[optionId][msg.sender] = Stake({
            amount: amount,
            lockDuration: lockDuration,
            creationTime: block.timestamp,
            lastExtensionTime: block.timestamp,
            data: data
        });

        if (option.hookContract != address(0)) {
            IStakingHooks(option.hookContract).afterStake(
                msg.sender,
                optionId,
                amount,
                lockDuration,
                data
            );
        }

        emit StakeCreated(
            optionId,
            msg.sender,
            amount,
            lockDuration,
            nextOptionId
        );
    }

    function extendStake(
        uint256 optionId,
        uint256 additionalLockDuration
    ) external {
        Option storage option = options[optionId];
        Stake storage userStake = stakes[optionId][msg.sender];

        if (userStake.amount == 0) revert StakeNotFound();

        uint256 newLockDuration = userStake.lockDuration +
            additionalLockDuration;
        if (newLockDuration > option.maxLockDuration)
            revert InvalidStakeAmount();

        if (option.hookContract != address(0)) {
            IStakingHooks(option.hookContract).beforeExtend(
                msg.sender,
                optionId,
                newLockDuration,
                userStake.data
            );
        }

        userStake.lockDuration = newLockDuration;
        userStake.lastExtensionTime = block.timestamp;

        if (option.hookContract != address(0)) {
            IStakingHooks(option.hookContract).afterExtend(
                msg.sender,
                optionId,
                newLockDuration,
                userStake.data
            );
        }

        emit StakeExtended(optionId, msg.sender, newLockDuration);
    }

    function withdraw(uint256 optionId) external {
        Option storage option = options[optionId];
        Stake storage userStake = stakes[optionId][msg.sender];

        if (option.hookContract != address(0)) {
            IStakingHooks(option.hookContract).beforeWithdraw(
                msg.sender,
                optionId,
                userStake.amount,
                userStake.data
            );
        }

        if (userStake.amount == 0) revert StakeNotFound();

        uint256 amountToWithdraw = userStake.amount;
        bool penaltyApplied = false;

        if (option.isLocked) {
            amountToWithdraw = _checkLockAndApplyPenalty(
                option,
                userStake,
                amountToWithdraw
            );
            penaltyApplied = amountToWithdraw != userStake.amount;
        }

        _transferTokens(option.token, msg.sender, amountToWithdraw);
        _resetUserStake(optionId, msg.sender);

        if (option.hookContract != address(0)) {
            IStakingHooks(option.hookContract).afterWithdraw(
                msg.sender,
                optionId,
                amountToWithdraw,
                penaltyApplied,
                userStake.data
            );
        }

        emit Withdraw(optionId, msg.sender, amountToWithdraw, penaltyApplied);
    }

    // Helper Functions
    function getWithdrawableAmount(
        uint256 optionId
    ) external view returns (uint256) {
        Option storage option = options[optionId];
        Stake storage userStake = stakes[optionId][msg.sender];

        if (userStake.amount == 0) revert StakeNotFound();

        uint256 amountToWithdraw = userStake.amount;

        if (option.isLocked) {
            uint256 lockEndTime = userStake.creationTime +
                userStake.lockDuration;
            if (block.timestamp < lockEndTime) {
                return 0; // Cannot withdraw before the lock period ends
            }

            if (option.hasEarlyExitPenalty) {
                uint256 penaltyAmount = (amountToWithdraw *
                    option.penaltyPercentage) / 10000;
                amountToWithdraw -= penaltyAmount;
            }
        }

        if (option.hasLinearVesting) {
            uint256 vestedAmount = _getVestedAmount(option, userStake);
            amountToWithdraw = amountToWithdraw > vestedAmount
                ? vestedAmount
                : amountToWithdraw;
        }

        return amountToWithdraw;
    }

    function _checkLockAndApplyPenalty(
        Option storage option,
        Stake storage userStake,
        uint256 amountToWithdraw
    ) internal returns (uint256) {
        uint256 lockEndTime = userStake.creationTime + userStake.lockDuration;
        if (block.timestamp < lockEndTime) revert WithdrawBeforeLockPeriod();

        if (option.hasEarlyExitPenalty) {
            uint256 penaltyAmount = (amountToWithdraw *
                option.penaltyPercentage) / 10000;
            amountToWithdraw -= penaltyAmount;

            if (option.penaltyRecipient != address(0)) {
                IERC20(option.token).safeTransfer(
                    option.penaltyRecipient,
                    penaltyAmount
                );
            } else {
                revert InsufficientBalanceForPenalty();
            }
        }

        return amountToWithdraw;
    }

    function _getVestedAmount(
        Option storage option,
        Stake storage userStake
    ) internal view returns (uint256) {
        if (block.timestamp < option.vestingStart + option.vestingCliff) {
            return 0; // No amount vested before the cliff period
        }

        uint256 vestingEndTime = option.vestingStart + option.vestingDuration;
        if (block.timestamp >= vestingEndTime) {
            return userStake.amount; // Fully vested
        }

        uint256 timeElapsed = block.timestamp - option.vestingStart;
        uint256 vestedAmount = (userStake.amount * timeElapsed) /
            option.vestingDuration;

        return vestedAmount;
    }

    function _transferTokens(
        address token,
        address to,
        uint256 amount
    ) internal {
        IERC20(token).safeTransfer(to, amount);
    }

    function _resetUserStake(uint256 optionId, address staker) internal {
        delete stakes[optionId][staker];
    }

    // Validation Functions
    function _validateBasicParams(OptionParams calldata params) internal pure {
        if (params.minStakeAmount == 0) revert MinimumStakeGreaterThanZero();
        if (
            params.maxStakeAmount != 0 &&
            params.maxStakeAmount < params.minStakeAmount
        ) revert MaxStakeGreaterThanMinStake();
    }

    function _validateLockingParams(
        OptionParams calldata params
    ) internal pure {
        if (params.isLocked) {
            if (params.minLockDuration == 0)
                revert LockedStakingMustHaveMinDuration();
            if (params.maxLockDuration < params.minLockDuration)
                revert MaxDurationGreaterThanMinDuration();

            if (params.hasEarlyExitPenalty) {
                if (
                    params.penaltyPercentage == 0 ||
                    params.penaltyPercentage > 10000
                ) revert InvalidPenaltyPercentage();
                if (params.penaltyRecipient == address(0))
                    revert PenaltyRecipientRequired();
            }
        } else {
            if (params.minLockDuration != 0 || params.maxLockDuration != 0)
                revert FlexibleStakingCannotHaveLockPeriods();
            if (params.hasEarlyExitPenalty)
                revert FlexibleStakingCannotHavePenalty();
            if (params.penaltyPercentage != 0)
                revert NoPenaltiesAllowedForFlexibleStaking();
            if (params.penaltyRecipient != address(0))
                revert NoPenaltyRecipientForFlexibleStaking();
        }
    }

    function _validateVestingParams(
        OptionParams calldata params
    ) internal pure {
        if (params.hasLinearVesting) {
            if (params.vestingDuration == 0) revert VestingMustHaveDuration();
            if (params.vestingStart == 0) revert VestingMustHaveStartTime();
            if (params.vestingCliff > params.vestingDuration)
                revert CliffMustBeLessThanOrEqualToVestingDuration();
        } else {
            if (
                params.vestingStart != 0 ||
                params.vestingCliff != 0 ||
                params.vestingDuration != 0
            ) revert NoVestingSettingsAllowed();
        }
    }

    function _validateMultiplierParams(
        OptionParams calldata params
    ) internal pure {
        if (params.hasTimeBasedMultiplier) {
            if (params.multiplierIncreaseRate == 0)
                revert MultiplierRateMustBeGreaterThanZero();
        } else {
            if (params.multiplierIncreaseRate != 0)
                revert NoMultiplierIncreaseRateIfDisabled();
        }
    }

    function _createOptionStorage(
        uint256 optionId,
        OptionParams calldata params
    ) internal {
        options[optionId] = Option({
            id: optionId,
            isLocked: params.isLocked,
            minLockDuration: params.minLockDuration,
            maxLockDuration: params.maxLockDuration,
            hasEarlyExitPenalty: params.hasEarlyExitPenalty,
            penaltyPercentage: params.penaltyPercentage,
            penaltyRecipient: params.penaltyRecipient,
            minStakeAmount: params.minStakeAmount,
            maxStakeAmount: params.maxStakeAmount,
            hasLinearVesting: params.hasLinearVesting,
            vestingStart: params.vestingStart,
            vestingCliff: params.vestingCliff,
            vestingDuration: params.vestingDuration,
            baseMultiplier: params.baseMultiplier,
            hasTimeBasedMultiplier: params.hasTimeBasedMultiplier,
            multiplierIncreaseRate: params.multiplierIncreaseRate,
            allowReallocation: params.allowReallocation,
            token: params.token,
            paused: false,
            requiresData: params.requiresData,
            hookContract: params.hookContract
        });
    }
}
