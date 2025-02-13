// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./interfaces/IStakingHooks.sol";
import "./errors/Error.sol";

/**
 * @title FlexStake Contract
 * @notice A flexible staking contract that supports multiple staking options with various features
 * including locking, vesting, penalties, and hooks.
 * @dev This contract allows creation and management of different staking options with customizable parameters
 * @custom:security-contact security@flexstake.example.com
 */
contract StakingContract is Error, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    struct Option {
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
        address token;
        bool paused;
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
    event StakingOperations(
        address indexed user,
        uint256 indexed optionId,
        uint256 amount,
        uint256 duration,
        bytes32 operationType
    );

    // State variables for emergency pause
    bool public emergencyPaused;
    
    // Batch events
    bytes32 private constant OPERATION_STAKE = keccak256("STAKE");
    bytes32 private constant OPERATION_WITHDRAW = keccak256("WITHDRAW");
    bytes32 private constant OPERATION_EXTEND = keccak256("EXTEND");

    /**
     * @dev Modifier to prevent reentrancy in functions that interact with hooks
     */
    modifier nonReentrantHooks() {
        if (emergencyPaused) revert EmergencyPauseActive();
        _;
    }

    /**
     * @dev Emergency pause modifier
     */
    modifier whenNotEmergencyPaused() {
        if (emergencyPaused) revert EmergencyPaused();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract replacing the constructor
     * @param _owner The address that will own the contract
     */
    function initialize(address _owner) external initializer {
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        nextOptionId = 1;
        emergencyPaused = false;
    }

    /**
     * @notice Checks if a stake requires additional data
     * @param optionId The ID of the staking option
     * @return bool True if the stake requires additional data
     */
    function requiresStakeData(uint256 optionId) external view returns (bool) {
        return options[optionId].requiresData;
    }

    /**
     * @notice Emergency pause all contract operations
     * @dev Only callable by contract owner
     */
    function setEmergencyPause(bool _paused) external onlyOwner {
        emergencyPaused = _paused;
    }

    /**
     * @notice Validates a hook contract address
     * @dev Checks if the contract exists and implements required interface
     * @param hookContract Address of the hook contract to validate
     */
    function _validateHookContract(address hookContract) internal {
        if (hookContract == address(0)) revert HookContractZeroAddress();
        
        // Check if contract exists
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(hookContract)
        }
        if (codeSize == 0) revert InvalidHookContract();

        // Optionally check interface implementation
        try IStakingHooks(hookContract).beforeStake{gas: 2300}(address(0), 0, 0, 0, "") {
            revert InvalidHookContract();
        } catch {
            // Expected to fail - this means the function exists
        }
    }

    // Option Management Functions
    function createOption(
        Option calldata option
    ) external onlyOwner returns (uint256) {
        if (option.hookContract != address(0)) {
            _validateHookContract(option.hookContract);
        }

        _validateBasicParams(option);
        _validateLockingParams(option);
        _validateVestingParams(option);
        _validateMultiplierParams(option);

        uint256 optionId;
        unchecked {
            optionId = nextOptionId++;
        }

        options[optionId] = option;
        options[optionId].paused = false; // Ensure new options start unpaused

        emit OptionCreated(optionId, options[optionId]);
        return optionId;
    }

    function pauseStaking(uint256 optionId) external onlyOwner {
        Option storage option = options[optionId];
        if (option.paused) revert AlreadyPaused();
        option.paused = true;
        emit OptionPaused(optionId);
    }

    function unpauseStaking(uint256 optionId) external onlyOwner {
        Option storage option = options[optionId];
        if (!option.paused) revert NotPaused();
        option.paused = false;
        emit OptionUnpaused(optionId);
    }

    // Staking Functions
    function stake(
        uint256 optionId,
        uint256 amount,
        uint256 lockDuration,
        bytes calldata data
    ) external nonReentrantHooks whenNotEmergencyPaused {
        Option storage option = options[optionId];
        address hookAddr = option.hookContract;

        if (option.requiresData && data.length == 0) revert DataRequired();
        if (!option.requiresData && data.length > 0) revert NoDataAllowed();

        if (hookAddr != address(0)) {
            IStakingHooks(hookAddr).beforeStake(
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

        if (hookAddr != address(0)) {
            IStakingHooks(hookAddr).afterStake(
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

        // Batch event
        emit StakingOperations(
            msg.sender,
            optionId,
            amount,
            lockDuration,
            OPERATION_STAKE
        );
    }

    function extendStake(
        uint256 optionId,
        uint256 additionalLockDuration
    ) external nonReentrantHooks whenNotEmergencyPaused {
        Option storage option = options[optionId];
        Stake storage userStake = stakes[optionId][msg.sender];
        address hookAddr = option.hookContract;

        if (userStake.amount == 0) revert StakeNotFound();

        uint256 newLockDuration = userStake.lockDuration +
            additionalLockDuration;
        if (newLockDuration > option.maxLockDuration)
            revert InvalidStakeAmount();

        if (hookAddr != address(0)) {
            IStakingHooks(hookAddr).beforeExtend(
                msg.sender,
                optionId,
                newLockDuration,
                userStake.data
            );
        }

        userStake.lockDuration = newLockDuration;
        userStake.lastExtensionTime = block.timestamp;

        if (hookAddr != address(0)) {
            IStakingHooks(hookAddr).afterExtend(
                msg.sender,
                optionId,
                newLockDuration,
                userStake.data
            );
        }

        emit StakeExtended(optionId, msg.sender, newLockDuration);

        // Batch event
        emit StakingOperations(
            msg.sender,
            optionId,
            0,
            newLockDuration,
            OPERATION_EXTEND
        );
    }

    function withdraw(uint256 optionId) external nonReentrantHooks whenNotEmergencyPaused {
        Option storage option = options[optionId];
        Stake storage userStake = stakes[optionId][msg.sender];
        address hookAddr = option.hookContract;

        if (userStake.amount == 0) revert StakeNotFound();

        if (hookAddr != address(0)) {
            IStakingHooks(hookAddr).beforeWithdraw(
                msg.sender,
                optionId,
                userStake.amount,
                userStake.data
            );
        }

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

        if (hookAddr != address(0)) {
            IStakingHooks(hookAddr).afterWithdraw(
                msg.sender,
                optionId,
                amountToWithdraw,
                penaltyApplied,
                userStake.data
            );
        }

        emit Withdraw(optionId, msg.sender, amountToWithdraw, penaltyApplied);

        // Batch event
        emit StakingOperations(
            msg.sender,
            optionId,
            amountToWithdraw,
            0,
            OPERATION_WITHDRAW
        );
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
    function _validateBasicParams(Option calldata option) internal pure {
        if (option.minStakeAmount == 0) revert MinimumStakeGreaterThanZero();
        if (
            option.maxStakeAmount != 0 &&
            option.maxStakeAmount < option.minStakeAmount
        ) revert MaxStakeGreaterThanMinStake();
    }

    function _validateLockingParams(Option calldata option) internal pure {
        if (option.isLocked) {
            if (option.minLockDuration == 0)
                revert LockedStakingMustHaveMinDuration();
            if (option.maxLockDuration < option.minLockDuration)
                revert MaxDurationGreaterThanMinDuration();

            if (option.hasEarlyExitPenalty) {
                if (
                    option.penaltyPercentage == 0 ||
                    option.penaltyPercentage > 10000
                ) revert InvalidPenaltyPercentage();
                if (option.penaltyRecipient == address(0))
                    revert PenaltyRecipientRequired();
            }
        } else {
            if (option.minLockDuration != 0 || option.maxLockDuration != 0)
                revert FlexibleStakingCannotHaveLockPeriods();
            if (option.hasEarlyExitPenalty)
                revert FlexibleStakingCannotHavePenalty();
            if (option.penaltyPercentage != 0)
                revert NoPenaltiesAllowedForFlexibleStaking();
            if (option.penaltyRecipient != address(0))
                revert NoPenaltyRecipientForFlexibleStaking();
        }
    }

    function _validateVestingParams(Option calldata option) internal pure {
        if (option.hasLinearVesting) {
            // Require locking if vesting is enabled
            if (!option.isLocked) revert VestingRequiresLocking();
            
            if (option.vestingDuration == 0) revert VestingMustHaveDuration();
            if (option.vestingStart == 0) revert VestingMustHaveStartTime();
            if (option.vestingCliff > option.vestingDuration)
                revert CliffMustBeLessThanOrEqualToVestingDuration();
        } else {
            if (
                option.vestingStart != 0 ||
                option.vestingCliff != 0 ||
                option.vestingDuration != 0
            ) revert NoVestingSettingsAllowed();
        }
    }

    function _validateMultiplierParams(Option calldata option) internal pure {
        if (option.hasTimeBasedMultiplier) {
            if (option.multiplierIncreaseRate == 0)
                revert MultiplierRateMustBeGreaterThanZero();
        } else {
            if (option.multiplierIncreaseRate != 0)
                revert NoMultiplierIncreaseRateIfDisabled();
        }
    }
}
